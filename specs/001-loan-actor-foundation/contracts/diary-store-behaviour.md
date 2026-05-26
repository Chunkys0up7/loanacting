# Contract — `DiaryStore` behaviour

A swappable diary backend. Foundation ships two implementations (Mnesia, File); both pass the same test suite.

```elixir
defmodule LoanActor.Diary.Store do
  @moduledoc "Append-only, chain-linked diary store."

  @type loan_id :: String.t
  @type sequence :: non_neg_integer
  @type entry :: %LoanActor.Diary.Entry{}

  @callback init(opts :: keyword) :: :ok | {:error, term}

  @callback append(loan_id, entry) :: {:ok, sequence} | {:error, term}
  # Atomic: writes the entry, validates prev_hash, updates per-loan tail pointer.

  @callback tail(loan_id) :: {:ok, entry | nil} | {:error, term}
  # Returns the most recent entry or nil if loan has no entries.

  @callback read_range(loan_id, from :: sequence, to :: sequence) :: {:ok, [entry]} | {:error, term}

  @callback stream(loan_id, opts :: keyword) :: Enumerable.t
  # Lazy stream of entries; used by replay and AG-UI snapshot.

  @callback verify_chain(loan_id) :: :ok | {:error, {:tamper, sequence}} | {:error, term}

  @callback wipe(loan_id) :: :ok | {:error, term}
  # TEST ONLY. Implementations MUST raise if Mix.env() == :prod.
end
```

## Invariants every implementation MUST uphold

1. **Append-only**: `append/2` always increases the per-loan sequence by exactly 1.
2. **Atomicity**: an `append/2` that fails after writing partial data is rolled back; verification cannot detect a torn write.
3. **Chain linkage**: `entry.prev_hash == BLAKE2b-256(prev_entry.payload_hash)`. `verify_chain/1` walks the chain end-to-end.
4. **Tamper detection**: mutating any persisted entry's `payload_hash` after the fact causes `verify_chain/1` to return `{:error, {:tamper, sequence}}`.
5. **PII boundary**: implementations do not log, snapshot, or copy `payload_hash` inputs anywhere; they only store the hash.

## Implementations

- `LoanActor.Diary.Mnesia` — primary. Transactional. Uses `:mnesia.transaction/1` for `append/2`.
- `LoanActor.Diary.File` — alternative. Per-loan JSONL file under `priv/diary_files/<loan_id>.jsonl`. fsync after every append.

## Test pins

Both implementations are exercised by the shared property-based suite at `apps/loan_actor/test/diary/shared_behaviour_test.exs`, parameterized by the implementation module. CI runs both passes.
