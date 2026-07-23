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

  @callback append_with_dedup(loan_id, event_id :: String.t, source :: atom, entry_builder) ::
              {:fresh, sequence, entry} | {:duplicate, sequence} | {:error, term}
  # entry_builder :: (tail :: entry | nil -> entry)
  #
  # Added by intent 0005. Combines the reactive pipeline's duplicate-detection
  # (composite key {loan_id, event_id, source}) with the diary append it gates.
  # A `:duplicate` result performs NO diary write. A `:fresh` result performs
  # exactly one diary append (built by calling `entry_builder` with the
  # current tail) and durably records the winning `{received_at, sequence}`
  # for the composite key, as a single unit — no implementation may leave a
  # duplicate-check side effect (e.g. a reservation) visible without the
  # corresponding diary entry also being visible, or vice versa.
end
```

## Invariants every implementation MUST uphold

1. **Append-only**: `append/2` always increases the per-loan sequence by exactly 1.
2. **Atomicity**: an `append/2` that fails after writing partial data is rolled back; verification cannot detect a torn write.
3. **Chain linkage**: `entry.prev_hash == BLAKE2b-256(prev_entry.payload_hash)`. `verify_chain/1` walks the chain end-to-end.
4. **Tamper detection**: mutating any persisted entry's `payload_hash` after the fact causes `verify_chain/1` to return `{:error, {:tamper, sequence}}`.
5. **PII boundary**: implementations do not log, snapshot, or copy `payload_hash` inputs anywhere; they only store the hash.
6. **Combined atomicity** *(0005)*: `append_with_dedup/4`'s duplicate-check and diary append are indivisible from an external observer's perspective — a crash between them MUST be impossible by construction (single transaction, or the implementation's equivalent), not merely made narrow. This replaces the two-phase reserve/fill design's accepted "orphaned reservation" limitation with an actual guarantee.

## Implementations

- `LoanActor.Diary.Mnesia` — primary. Transactional. Uses `:mnesia.transaction/1` for `append/2`. `append_with_dedup/4` *(0005)* performs the duplicate check and the append inside one transaction (a dirty-read peek precedes it as a fast path; the transaction itself re-checks before writing).
- `LoanActor.Diary.File` — alternative, test-only. Per-loan JSONL file under `priv/diary_files/<loan_id>.jsonl`. fsync after every append. `append_with_dedup/4` *(0005)* keeps the pre-0005 two-call shape internally (idempotency is always Mnesia-backed regardless of diary backend — `data-model.md`'s `loan_idem` table; File has no transaction of its own to fold the check into). `NFR-001` is measured against the Mnesia implementation specifically.

## Test pins

Both implementations are exercised by the shared property-based suite at `apps/loan_actor/test/diary/shared_behaviour_test.exs`, parameterized by the implementation module. CI runs both passes. `append_with_dedup/4` *(0005)* is covered by the same shared suite: fresh-then-duplicate, concurrent-duplicate-delivery race (exactly one `:fresh` winner), and duplicate-produces-no-diary-write assertions, for both implementations.
