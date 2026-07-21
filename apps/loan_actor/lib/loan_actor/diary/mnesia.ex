defmodule LoanActor.Diary.Mnesia do
  @moduledoc """
  Primary `DiaryStore` implementation (FT-008): Mnesia, transactional,
  `disc_copies` on the local node.

  Table (per `data-model.md` Mnesia schema):

      loan_diary  ordered_set  disc_copies  {{loan_id, sequence}, entry_binary}

  The contract's "per-loan tail pointer" is realized by the ordered_set key
  order itself: `{loan_id, :infinity}` sorts after every `{loan_id, seq}`
  (integers < atoms in term order), so `:mnesia.prev/2` from that sentinel key
  yields the loan's tail in O(log n) — no auxiliary table, nothing extra to
  keep atomic.

  `append/2` runs entirely inside one `:mnesia.transaction/1`: read tail,
  `Chain.verify_append/2`, write. Concurrent appenders against the same tail
  serialize; the loser's entry no longer links and its transaction aborts with
  the linkage error (callers rebuild from the fresh tail and retry — the loan
  Server is single-process per loan, so contention is exceptional by design).

  Diary sequences are gap-free from 0 (chain invariant), so `stream/2` walks
  `sequence` upward with dirty reads — replay does not pay transaction costs.
  """

  @behaviour LoanActor.Diary.Store

  alias LoanActor.Diary.Chain
  alias LoanActor.Diary.Entry
  alias LoanActor.Diary.Store

  @table :loan_diary
  @idem_table :loan_idem

  # ---- behaviour callbacks ----

  @impl Store
  def init(opts) do
    with :ok <- ensure_dir(Keyword.get(opts, :dir)),
         :ok <- ensure_schema_and_start(),
         :ok <- ensure_table(),
         :ok <- ensure_idem_table() do
      case :mnesia.wait_for_tables([@table, @idem_table], 10_000) do
        :ok -> :ok
        {:timeout, tabs} -> {:error, {:table_timeout, tabs}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @impl Store
  def append(loan_id, %Entry{loan_id: loan_id} = entry) do
    case :mnesia.transaction(fn -> txn_append(loan_id, entry) end) do
      {:atomic, sequence} -> {:ok, sequence}
      {:aborted, reason} -> {:error, reason}
    end
  end

  def append(_loan_id, %Entry{}), do: {:error, :loan_id_mismatch}

  defp txn_append(loan_id, entry) do
    case Chain.verify_append(txn_tail(loan_id), entry) do
      :ok ->
        :ok = :mnesia.write({@table, Entry.entry_id(entry), :erlang.term_to_binary(entry)})
        entry.sequence

      {:error, reason} ->
        :mnesia.abort(reason)
    end
  end

  @impl Store
  def tail(loan_id) do
    case :mnesia.transaction(fn -> txn_tail(loan_id) end) do
      {:atomic, tail} -> {:ok, tail}
      {:aborted, reason} -> {:error, reason}
    end
  end

  @impl Store
  def read_range(_loan_id, from, to) when from > to, do: {:ok, []}

  @impl Store
  def read_range(loan_id, from, to) do
    spec = [
      {{@table, {loan_id, :"$1"}, :"$2"}, [{:andalso, {:>=, :"$1", from}, {:"=<", :"$1", to}}],
       [:"$2"]}
    ]

    case :mnesia.transaction(fn -> :mnesia.select(@table, spec) end) do
      # ordered_set select returns rows in key (= sequence) order
      {:atomic, binaries} -> {:ok, Enum.map(binaries, &:erlang.binary_to_term/1)}
      {:aborted, reason} -> {:error, reason}
    end
  end

  @impl Store
  def stream(loan_id, _opts) do
    Stream.unfold(0, fn sequence ->
      case :mnesia.dirty_read(@table, {loan_id, sequence}) do
        [{@table, _key, binary}] -> {:erlang.binary_to_term(binary), sequence + 1}
        [] -> nil
      end
    end)
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
      raise "Diary.Mnesia.wipe/1 is test-only and MUST NOT run in :prod"
    end
  else
    @impl Store
    def wipe(loan_id) do
      result =
        :mnesia.transaction(fn ->
          delete_from(loan_id, 0)
        end)

      case result do
        {:atomic, :ok} -> :ok
        {:aborted, reason} -> {:error, reason}
      end
    end
  end

  # ---- transaction helpers ----

  defp txn_tail(loan_id) do
    case :mnesia.prev(@table, {loan_id, :infinity}) do
      {^loan_id, sequence} ->
        [{@table, _key, binary}] = :mnesia.read(@table, {loan_id, sequence})
        :erlang.binary_to_term(binary)

      _other_loan_or_end ->
        nil
    end
  end

  defp delete_from(loan_id, sequence) do
    case :mnesia.read(@table, {loan_id, sequence}) do
      [] ->
        :ok

      [_row] ->
        :ok = :mnesia.delete({@table, {loan_id, sequence}})
        delete_from(loan_id, sequence + 1)
    end
  end

  # ---- init plumbing ----

  defp ensure_dir(nil), do: :ok

  defp ensure_dir(dir) do
    dir_charlist = String.to_charlist(Path.expand(dir))

    if running?() and :mnesia.system_info(:directory) != dir_charlist do
      :stopped = :mnesia.stop()
    end

    :ok = :application.set_env(:mnesia, :dir, dir_charlist)
    :ok
  end

  defp ensure_schema_and_start do
    unless running?() do
      case :mnesia.create_schema([node()]) do
        :ok -> :ok
        {:error, {_node, {:already_exists, _}}} -> :ok
        {:error, reason} -> throw({:schema_error, reason})
      end

      :ok = :mnesia.start()
    end

    :ok
  catch
    {:schema_error, reason} -> {:error, {:schema_error, reason}}
  end

  defp ensure_table do
    case :mnesia.create_table(@table,
           type: :ordered_set,
           attributes: [:key, :entry],
           disc_copies: [node()]
         ) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, @table}} -> :ok
      {:aborted, reason} -> {:error, {:table_error, reason}}
    end
  end

  # loan_idem — FT-015 idempotency table (data-model.md Mnesia schema):
  # {{loan_id, event_id, source}, received_at}. Consumed by
  # LoanActor.Idempotency.check_and_record/3.
  defp ensure_idem_table do
    case :mnesia.create_table(@idem_table,
           type: :set,
           attributes: [:key, :received_at],
           disc_copies: [node()]
         ) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, @idem_table}} -> :ok
      {:aborted, reason} -> {:error, {:table_error, reason}}
    end
  end

  defp running?, do: :mnesia.system_info(:is_running) == :yes
end
