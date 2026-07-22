defmodule LoanActor.Diary.File do
  @moduledoc """
  File-backed `DiaryStore` implementation (FT-007) — the alternative to the
  primary Mnesia store. One JSONL file per loan under the configured diary
  directory; every append is fsynced before returning.

  Properties:

  - **Serialization** — appends for a loan are serialized with
    `:global.trans/2` on a per-loan key, so concurrent callers cannot produce
    torn or interleaved chains.
  - **Atomicity/repair** — a line is only valid once its trailing newline is
    durably written; a crash mid-write leaves a partial trailing line that is
    truncated away by the next operation (`repair!/1`), which is the rollback
    the contract's invariant 2 requires.
  - **Tail reads** — `tail/1` seeks backward from EOF for the last line rather
    than scanning the file, keeping appends O(entry size), not O(diary size).
  - **PII boundary** — only `Entry` structs (hashes, never payloads) are
    serialized.

  Directory resolution: `init/1`'s `:dir` option (persisted to the
  `:loan_actor, :diary_dir` app env), else the previously configured env,
  else `priv/diary_files`.
  """

  @behaviour LoanActor.Diary.Store

  alias LoanActor.Diary.Chain
  alias LoanActor.Diary.Entry
  alias LoanActor.Diary.Store
  alias LoanActor.Idempotency

  @tail_scan_chunk 4096

  # ---- behaviour callbacks ----

  @impl Store
  def init(opts) do
    if dir = Keyword.get(opts, :dir) do
      Application.put_env(:loan_actor, :diary_dir, dir)
    end

    case File.mkdir_p(dir()) do
      :ok -> :ok
      {:error, reason} -> {:error, {:mkdir_failed, reason}}
    end
  end

  @impl Store
  def append(loan_id, %Entry{} = entry) do
    if entry.loan_id == loan_id do
      locked(loan_id, fn -> do_append(loan_id, entry) end)
    else
      {:error, :loan_id_mismatch}
    end
  end

  @impl Store
  def append_with_dedup(loan_id, event_id, source, entry_builder) when is_function(entry_builder, 1) do
    # No Mnesia transaction of File's own to fold the dedup check into
    # (`loan_idem` is Mnesia-backed regardless of diary backend, per
    # data-model.md) — keeps the pre-0005 two-call shape internally. File is
    # a test-only backend; NFR-001 is measured against Mnesia specifically.
    case Idempotency.check_and_record(loan_id, event_id, source) do
      {:duplicate, sequence} ->
        {:duplicate, sequence}

      :fresh ->
        {:ok, tail} = tail(loan_id)
        entry = entry_builder.(tail)

        case append(loan_id, entry) do
          {:ok, sequence} ->
            :ok = Idempotency.record_sequence(loan_id, event_id, source, sequence)
            {:fresh, sequence, entry}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @impl Store
  def tail(loan_id) do
    locked(loan_id, fn ->
      repair!(path(loan_id))

      case last_line(path(loan_id)) do
        nil -> {:ok, nil}
        line -> {:ok, decode!(line)}
      end
    end)
  end

  @impl Store
  def read_range(_loan_id, from, to) when from > to, do: {:ok, []}

  @impl Store
  def read_range(loan_id, from, to) do
    entries =
      loan_id
      |> stream([])
      |> Stream.drop_while(&(&1.sequence < from))
      |> Enum.take_while(&(&1.sequence <= to))

    {:ok, entries}
  end

  @impl Store
  def stream(loan_id, _opts) do
    path = path(loan_id)

    Stream.resource(
      fn ->
        if File.exists?(path) do
          repair!(path)
          File.open!(path, [:read, :raw, :binary, :read_ahead])
        end
      end,
      fn
        nil ->
          {:halt, nil}

        io ->
          case :file.read_line(io) do
            {:ok, line} -> {[decode!(line)], io}
            :eof -> {:halt, io}
          end
      end,
      fn
        nil -> :ok
        io -> File.close(io)
      end
    )
  end

  @impl Store
  def verify_chain(loan_id) do
    case Chain.verify(stream(loan_id, [])) do
      :ok -> :ok
      # An empty diary is trivially valid.
      {:error, :empty} -> :ok
      {:error, _} = err -> err
    end
  end

  if Mix.env() == :prod do
    @impl Store
    def wipe(_loan_id) do
      raise "Diary.File.wipe/1 is test-only and MUST NOT run in :prod"
    end
  else
    @impl Store
    def wipe(loan_id) do
      locked(loan_id, fn ->
        case File.rm(path(loan_id)) do
          :ok -> :ok
          {:error, :enoent} -> :ok
          {:error, reason} -> {:error, reason}
        end
      end)
    end
  end

  # ---- append internals ----

  defp do_append(loan_id, entry) do
    path = path(loan_id)
    repair!(path)

    tail =
      case last_line(path) do
        nil -> nil
        line -> decode!(line)
      end

    with :ok <- Chain.verify_append(tail, entry) do
      write_line!(path, encode!(entry))
      {:ok, entry.sequence}
    end
  end

  defp write_line!(path, line) do
    io = File.open!(path, [:append, :raw, :binary])

    try do
      :ok = :file.write(io, [line, ?\n])
      :ok = :file.sync(io)
    after
      File.close(io)
    end
  end

  # Truncate a partial (no trailing newline) last line left by a crash.
  # A missing file ({:error, :enoent}) needs no repair.
  defp repair!(path) do
    case :file.open(path, [:read, :write, :raw, :binary]) do
      {:ok, io} ->
        try do
          truncate_partial_tail(io)
        after
          :file.close(io)
        end

      {:error, _} ->
        :ok
    end

    :ok
  end

  defp truncate_partial_tail(io) do
    size = file_size(io)

    _not_partial =
      with true <- size > 0,
           {:ok, last} when last != "\n" <- :file.pread(io, size - 1, 1) do
        keep =
          case last_newline_at(io, size) do
            nil -> 0
            at -> at + 1
          end

        {:ok, _} = :file.position(io, keep)
        :ok = :file.truncate(io)
        :ok = :file.sync(io)
      end

    :ok
  end

  defp last_line(path) do
    case :file.open(path, [:read, :raw, :binary]) do
      {:error, :enoent} ->
        nil

      {:ok, io} ->
        try do
          size = file_size(io)

          if size == 0 do
            nil
          else
            # The file ends with "\n" (repair! guarantees it); the last line
            # sits between the previous newline (or BOF) and EOF - 1.
            from =
              case last_newline_at(io, size - 1) do
                nil -> 0
                at -> at + 1
              end

            {:ok, line} = :file.pread(io, from, size - 1 - from)
            line
          end
        after
          :file.close(io)
        end
    end
  end

  # Byte offset of the last "\n" strictly before `before_pos`, or nil.
  defp last_newline_at(_io, before_pos) when before_pos <= 0, do: nil

  defp last_newline_at(io, before_pos) do
    from = max(before_pos - @tail_scan_chunk, 0)
    {:ok, chunk} = :file.pread(io, from, before_pos - from)

    case last_index_of(chunk, ?\n) do
      nil -> last_newline_at(io, from)
      idx -> from + idx
    end
  end

  defp last_index_of(binary, byte) do
    binary
    |> byte_size()
    |> Kernel.-(1)
    |> then(&scan_back(binary, byte, &1))
  end

  defp scan_back(_binary, _byte, idx) when idx < 0, do: nil

  defp scan_back(binary, byte, idx) do
    if :binary.at(binary, idx) == byte, do: idx, else: scan_back(binary, byte, idx - 1)
  end

  defp file_size(io) do
    {:ok, size} = :file.position(io, :eof)
    size
  end

  # ---- codec ----

  @doc false
  @spec encode!(Entry.t()) :: binary()
  def encode!(%Entry{} = entry) do
    Jason.encode!(%{
      "loan_id" => entry.loan_id,
      "sequence" => entry.sequence,
      "timestamp" => DateTime.to_iso8601(entry.timestamp),
      "type" => Atom.to_string(entry.type),
      "actor" => entry.actor,
      "payload_hash" => Base.encode64(entry.payload_hash),
      "payload_ref" => entry.payload_ref && Base.encode64(entry.payload_ref),
      "prev_hash" => Base.encode64(entry.prev_hash)
    })
  end

  @doc false
  @spec decode!(binary()) :: Entry.t()
  def decode!(line) do
    map = Jason.decode!(String.trim_trailing(line, "\n"))
    {:ok, timestamp, 0} = DateTime.from_iso8601(Map.fetch!(map, "timestamp"))

    Entry.new(%{
      loan_id: Map.fetch!(map, "loan_id"),
      sequence: Map.fetch!(map, "sequence"),
      timestamp: timestamp,
      # Diary types are a closed enum (data-model.md); to_existing_atom keeps
      # replay from minting atoms out of untrusted files.
      type: map |> Map.fetch!("type") |> String.to_existing_atom(),
      actor: Map.fetch!(map, "actor"),
      payload_hash: map |> Map.fetch!("payload_hash") |> Base.decode64!(),
      payload_ref:
        with(ref when ref != nil <- Map.get(map, "payload_ref"), do: Base.decode64!(ref)),
      prev_hash: map |> Map.fetch!("prev_hash") |> Base.decode64!()
    })
  end

  # ---- plumbing ----

  defp locked(loan_id, fun) do
    :global.trans({{:loan_diary_file, loan_id}, self()}, fun)
  end

  defp path(loan_id) do
    if String.contains?(loan_id, ["/", "\\", ".."]) do
      raise ArgumentError, "unsafe loan_id for file store: #{inspect(loan_id)}"
    end

    Path.join(dir(), "#{loan_id}.jsonl")
  end

  defp dir do
    Application.get_env(:loan_actor, :diary_dir, default_dir())
  end

  defp default_dir do
    case :code.priv_dir(:loan_actor) do
      {:error, _} -> Path.join("priv", "diary_files")
      priv -> Path.join(List.to_string(priv), "diary_files")
    end
  end
end
