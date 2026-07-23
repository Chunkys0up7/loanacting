defmodule LoanActor.Event do
  @moduledoc """
  Inbound message into a loan actor's mailbox or HTTP endpoint (FT-013).
  Fields per `specs/001-loan-actor-foundation/data-model.md` `%LoanActor.Event{}`.

  Unlike the other foundation structs (which raise on invariant violations
  at construction — `Diary.Entry`, `Goal`, `State`, `Tool.Spec`),
  `%LoanActor.Event{}` is a plain struct (all fields default `nil`)
  validated separately via `validate/1`, which returns
  `{:error, :invalid_event}` rather than raising. This matches the
  documented Server contract (`contracts/loan-actor-api.md`):
  `send_event/2` returns `{:error, :invalid_event}` for a structurally
  invalid event — since events arrive from external callers (HTTP, tests)
  whose payloads cannot be trusted, a raising constructor would force every
  caller into a try/rescue instead of a plain pattern match on the result.

  The `type` enum here is independently declared from
  `LoanActor.State.Model`'s (which needs the same domain enum before this
  module exists in the dependency graph — FT-011 depends only on FT-010).
  Both lists mirror data-model.md's Event-type enum; this is intentional
  duplication across two tasks' scopes, not drift.
  """

  @sources [:operator, :system, :test]

  @event_types [
    :document_uploaded,
    :document_review_requested,
    :operator_approval_required,
    :operator_approval_granted,
    :operator_approval_denied,
    :heartbeat,
    :goal_set,
    :goal_satisfied,
    :goal_abandoned,
    :complete,
    :abort
  ]

  defstruct [:event_id, :source, :type, :payload, :created_at, :received_at]

  @type source :: :operator | :system | :test

  @type event_type ::
          :document_uploaded
          | :document_review_requested
          | :operator_approval_required
          | :operator_approval_granted
          | :operator_approval_denied
          | :heartbeat
          | :goal_set
          | :goal_satisfied
          | :goal_abandoned
          | :complete
          | :abort

  @type t :: %__MODULE__{
          event_id: String.t() | nil,
          source: source() | nil,
          type: event_type() | nil,
          payload: map() | nil,
          created_at: DateTime.t() | nil,
          received_at: DateTime.t() | nil
        }

  @doc "The closed set of legal `source` values. Foundation enum; extensions require an amendment."
  @spec sources() :: [source()]
  def sources, do: @sources

  @doc "The closed set of documented `type` values (data-model.md Event-type enum)."
  @spec event_types() :: [event_type()]
  def event_types, do: @event_types

  @doc """
  Validate `event`'s invariants: `event_id` a non-empty binary, `source` in
  the closed enum, `type` in the closed enum, `payload` a map,
  `created_at`/`received_at` both `DateTime.t`.

  Returns `:ok` or `{:error, :invalid_event}` — the exact shape documented
  in `contracts/loan-actor-api.md`'s lifecycle errors table.
  """
  @spec validate(t()) :: :ok | {:error, :invalid_event}
  def validate(%__MODULE__{} = event) do
    if valid?(event), do: :ok, else: {:error, :invalid_event}
  end

  defp valid?(event) do
    valid_event_id?(event.event_id) and
      event.source in @sources and
      event.type in @event_types and
      is_map(event.payload) and
      match?(%DateTime{}, event.created_at) and
      match?(%DateTime{}, event.received_at)
  end

  defp valid_event_id?(v), do: is_binary(v) and byte_size(v) > 0
end
