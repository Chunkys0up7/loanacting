defmodule LoanActor.Diary.Store do
  @moduledoc """
  Append-only, chain-linked diary store behaviour.

  Contract: `specs/001-loan-actor-foundation/contracts/diary-store-behaviour.md`
  (FT-006). Foundation ships two implementations — `LoanActor.Diary.Mnesia`
  (primary, FT-008) and `LoanActor.Diary.File` (alternative, FT-007) — both
  exercised by the same parameterized suite
  (`test/support/diary_store_shared.ex`, instantiated per implementation in
  `test/diary/shared_behaviour_test.exs`).

  Invariants every implementation MUST uphold (normative wording in the
  contract doc):

  1. **Append-only** — `append/2` increases the per-loan sequence by exactly 1.
  2. **Atomicity** — a failed `append/2` leaves no partial data behind.
  3. **Chain linkage** — validated on every append via
     `LoanActor.Diary.Chain.verify_append/2`.
  4. **Tamper detection** — `verify_chain/1` walks the persisted chain.
  5. **PII boundary** — implementations only ever see and store hashes.
  """

  alias LoanActor.Diary.Entry

  @type loan_id :: String.t()
  @type sequence :: non_neg_integer()
  @type entry :: Entry.t()

  @doc "Prepare the backing store (create tables / directories). Idempotent."
  @callback init(opts :: keyword()) :: :ok | {:error, term()}

  @doc """
  Atomically append `entry` for `loan_id`: validates chain linkage against the
  current tail, writes the entry, updates the per-loan tail pointer. Returns
  the entry's sequence on success.
  """
  @callback append(loan_id, entry) :: {:ok, sequence} | {:error, term()}

  @doc "Most recent entry, or `nil` if the loan has no entries."
  @callback tail(loan_id) :: {:ok, entry | nil} | {:error, term()}

  @doc "Entries with `from <= sequence <= to`, ascending. Missing sequences are simply absent."
  @callback read_range(loan_id, from :: sequence, to :: sequence) ::
              {:ok, [entry]} | {:error, term()}

  @doc "Lazy ascending stream of all entries; used by replay and AG-UI snapshot."
  @callback stream(loan_id, opts :: keyword()) :: Enumerable.t()

  @doc "Walk the persisted chain end-to-end (see `LoanActor.Diary.Chain.verify/1`)."
  @callback verify_chain(loan_id) ::
              :ok | {:error, {:tamper, sequence}} | {:error, term()}

  @doc "TEST ONLY. Remove every entry for `loan_id`. MUST raise in `:prod`."
  @callback wipe(loan_id) :: :ok | {:error, term()}

  @typedoc "Builds the entry to append, given the current tail (`nil` for an empty diary)."
  @type entry_builder :: (entry | nil -> entry)

  @doc """
  Combines the reactive pipeline's duplicate-detection (composite key
  `{loan_id, event_id, source}`, `contracts/diary-store-behaviour.md`) with the
  diary append it gates (FT-046, intent 0005).

  A `:duplicate` result performs no diary write. A `:fresh` result performs
  exactly one diary append (the entry returned by calling `entry_builder`
  with the current tail) and durably records the winning
  `{received_at, sequence}` for the composite key — both as a single,
  indivisible unit (see the contract's invariant 6).
  """
  @callback append_with_dedup(loan_id, event_id :: String.t(), source :: atom(), entry_builder) ::
              {:fresh, sequence, entry} | {:duplicate, sequence} | {:error, term()}
end
