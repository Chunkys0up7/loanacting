defmodule LoanActor.Idempotency do
  @moduledoc """
  Composite-key `(loan_id, event_id, source)` idempotency check (FT-015;
  clarifications.md Q6 locks the composite key over `event_id` alone;
  clarifications.md's FT-017 resolution — record the diary sequence so
  duplicates report `{:duplicate, sequence}` per `contracts/loan-actor-api.md`).

  Backed by the `loan_idem` Mnesia table created in
  `LoanActor.Diary.Mnesia.init/1` — value is `{received_at, sequence}`
  (extended from `data-model.md`'s originally-documented bare `received_at`
  to carry the sequence the documented `{:duplicate, sequence}` return
  shape requires; `data-model.md` is updated to match).

  Two-phase because the diary sequence for a FRESH event isn't known until
  *after* the diary append succeeds (it depends on the store's current
  tail), while duplicate detection must happen *before* any append (FR-004:
  no second diary entry for a duplicate). `check_and_record/3` atomically
  reserves the key (sequence `nil`) so concurrent callers still serialize
  to exactly one `:fresh` winner; that winner calls `record_sequence/4`
  once it knows the real sequence. Callers are expected to be a single
  serialized process per loan (`LoanActor.Server`, FT-017 — GenServer
  mailbox order), so no other caller can observe the reserved-but-unfilled
  window for the same key.

  **Known limitation** (not built — out of scope, not asked for by any
  task): if the diary append itself fails *after* a successful reservation,
  the key remains reserved with `sequence: nil` forever (no rollback/undo
  path). This is an extremely narrow failure mode (disk full, store
  unreachable) that neither `data-model.md` nor `tasks.md` addresses;
  building compensating-transaction logic for it would be invention beyond
  what was asked.
  """

  @table :loan_idem

  @doc """
  Atomically check-and-reserve `{loan_id, event_id, source}`.

  Returns `:fresh` — the key is reserved with `received_at` set and
  `sequence: nil`, to be filled by `record_sequence/4` — or
  `{:duplicate, sequence}` with the ORIGINALLY recorded sequence if this
  key was already seen (the caller MUST NOT append a second diary entry).

  Concurrent callers racing the same key serialize through Mnesia's
  transaction manager: exactly one sees `:fresh`.
  """
  @spec check_and_record(String.t(), String.t(), atom()) ::
          :fresh | {:duplicate, non_neg_integer()}
  def check_and_record(loan_id, event_id, source) do
    key = {loan_id, event_id, source}

    {:atomic, result} =
      :mnesia.transaction(fn ->
        case :mnesia.read(@table, key) do
          [] ->
            :ok = :mnesia.write({@table, key, {DateTime.utc_now(), nil}})
            :fresh

          [{@table, ^key, {_received_at, sequence}}] ->
            {:duplicate, sequence}
        end
      end)

    result
  end

  @doc """
  Fill in the diary `sequence` for a key previously reserved as `:fresh` by
  `check_and_record/3`. Raises (via a failed match, inside the transaction)
  if the key isn't in the reserved (`sequence: nil`) state — a programming
  error, not a runtime condition: this must be called at most once, only
  after the corresponding `:fresh` result.
  """
  @spec record_sequence(String.t(), String.t(), atom(), non_neg_integer()) :: :ok
  def record_sequence(loan_id, event_id, source, sequence) do
    key = {loan_id, event_id, source}

    {:atomic, :ok} =
      :mnesia.transaction(fn ->
        [{@table, ^key, {received_at, nil}}] = :mnesia.read(@table, key)
        :mnesia.write({@table, key, {received_at, sequence}})
      end)

    :ok
  end
end
