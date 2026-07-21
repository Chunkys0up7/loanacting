defmodule LoanActor.Idempotency do
  @moduledoc """
  Composite-key `(loan_id, event_id, source)` idempotency check (FT-015;
  clarifications.md Q6 locks the composite key over `event_id` alone).

  Backed by the `loan_idem` Mnesia table created in
  `LoanActor.Diary.Mnesia.init/1` (`data-model.md` Mnesia schema:
  `{{loan_id, event_id, source}, received_at}`).
  """

  @table :loan_idem

  @doc """
  Atomically check-and-record `{loan_id, event_id, source}`.

  Returns `:fresh` if this is the first time this key has been seen — the
  key is recorded with the current `received_at` timestamp in the same
  transaction — or `:duplicate` if it was already recorded (the caller MUST
  NOT append a second diary entry for a `:duplicate` result).

  Concurrent callers racing the same key serialize through Mnesia's
  transaction manager: exactly one sees `:fresh`.
  """
  @spec check_and_record(String.t(), String.t(), atom()) :: :fresh | :duplicate
  def check_and_record(loan_id, event_id, source) do
    key = {loan_id, event_id, source}

    {:atomic, result} =
      :mnesia.transaction(fn ->
        case :mnesia.read(@table, key) do
          [] ->
            :ok = :mnesia.write({@table, key, DateTime.utc_now()})
            :fresh

          [_existing] ->
            :duplicate
        end
      end)

    result
  end
end
