defmodule LoanActor.Diary.Chain do
  @moduledoc """
  Chain-link math for the immutable diary.

  Per constitution Principle IV and `contracts/diary-store-behaviour.md`:

  - For every loan, `diary[N].prev_hash == compute_next_prev_hash(diary[N-1])`
    for `N > 0`.
  - `diary[0].prev_hash == LoanActor.Diary.Entry.genesis_prev_hash()` (32 zero bytes).
  - Mutating any persisted entry's `payload_hash` causes `verify/1` to fail.

  Hash function: BLAKE2b truncated to 32 bytes (BLAKE2b-256). See research R-4.

  This module is FT-005 (Track 2 — diary bedrock). It is pure (no I/O); each
  `DiaryStore` implementation calls into these functions when appending.
  """

  alias LoanActor.Diary.Entry

  @doc """
  Compute the `prev_hash` field that an entry **following** `prev_entry` must carry.

  Returns the 32-byte BLAKE2b-256 digest of `prev_entry.payload_hash`.
  """
  @spec next_prev_hash(Entry.t()) :: binary()
  def next_prev_hash(%Entry{payload_hash: payload_hash}) do
    hash(payload_hash)
  end

  @doc """
  Verify the link between two consecutive entries: `prev` at sequence N and
  `current` at sequence N+1.

  Returns `:ok` if `current.prev_hash == next_prev_hash(prev)` AND
  `current.sequence == prev.sequence + 1` AND they share a `loan_id`.

  Returns `{:error, reason}` otherwise.
  """
  @spec verify_pair(Entry.t(), Entry.t()) :: :ok | {:error, atom()}
  def verify_pair(%Entry{} = prev, %Entry{} = current) do
    cond do
      prev.loan_id != current.loan_id ->
        {:error, :loan_id_mismatch}

      current.sequence != prev.sequence + 1 ->
        {:error, :sequence_gap}

      current.prev_hash != next_prev_hash(prev) ->
        {:error, :prev_hash_mismatch}

      true ->
        :ok
    end
  end

  @doc """
  Verify an entire chain in order. Accepts any `Enumerable.t` yielding `%Entry{}`
  values in ascending sequence order, starting at sequence 0.

  Returns `:ok` on success, or `{:error, {:tamper, sequence}}` identifying the
  first entry whose linkage is broken. Returns `{:error, :empty}` if the chain
  is empty (callers can choose to treat this as ok via pattern matching).

  Walks the stream lazily — verifies in O(n) time and O(1) memory beyond the
  pair of entries currently being compared.
  """
  @spec verify(Enumerable.t()) :: :ok | {:error, {:tamper, non_neg_integer()} | atom()}
  def verify(entries) do
    entries
    |> Stream.with_index()
    |> Enum.reduce_while({:start, nil}, fn {%Entry{} = entry, idx}, acc ->
      case verify_step(acc, entry, idx) do
        {:ok, state} -> {:cont, state}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:start, nil} -> {:error, :empty}
      {:ok, _} -> :ok
      :ok -> :ok
      {:error, _} = err -> err
    end
  end

  defp verify_step({:start, nil}, %Entry{sequence: 0, prev_hash: prev_hash} = entry, 0) do
    if prev_hash == Entry.genesis_prev_hash() do
      {:ok, {:ok, entry}}
    else
      {:error, {:tamper, 0}}
    end
  end

  defp verify_step({:start, nil}, _entry, _idx) do
    # First yielded entry was not sequence 0
    {:error, {:tamper, 0}}
  end

  defp verify_step({:ok, %Entry{} = prev}, %Entry{} = current, idx) do
    case verify_pair(prev, current) do
      :ok -> {:ok, {:ok, current}}
      {:error, _} -> {:error, {:tamper, idx}}
    end
  end

  @doc """
  BLAKE2b-256 digest helper. Public because diary store implementations need to
  compute `payload_hash` over canonical-JSON of a stripped payload.
  """
  @spec hash(iodata()) :: binary()
  def hash(data) do
    :crypto.hash(:blake2b, data) |> :binary.part(0, Entry.hash_size())
  end
end
