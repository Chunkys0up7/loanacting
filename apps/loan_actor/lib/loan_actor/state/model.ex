defmodule LoanActor.State.Model do
  @moduledoc """
  Pure state-machine graph mirroring the diagram in
  `specs/001-loan-actor-foundation/data-model.md` (FT-011). Single source of
  truth for legal `{status, event_type} -> next_status` edges —
  `LoanActor.State.transition/2` and property-based tests (FT-034) both
  consult this module instead of duplicating the graph.

  Foundation models **exactly** the seven edges drawn in the diagram. Event
  types documented in data-model.md's Event-type enum but not drawn on the
  diagram (`:document_review_requested`, `:heartbeat`, `:goal_abandoned`,
  `:abort`) have **no** legal edge from any status in foundation — they are
  valid `%LoanActor.Event{}` types (FT-013) but do not drive a `status`
  change here. `:errored` is reachable only via the supervisor's
  crash-recovery path (a later task), never via `transition/2` — it has no
  legal edges in or out, by design.
  """

  alias LoanActor.State

  @type status :: State.status()

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

  @edges %{
    {:spawned, :goal_set} => :awaiting_documents,
    {:awaiting_documents, :document_uploaded} => :documents_under_review,
    {:documents_under_review, :operator_approval_required} => :awaiting_operator_approval,
    {:documents_under_review, :goal_satisfied} => :processing,
    {:awaiting_operator_approval, :operator_approval_granted} => :processing,
    {:awaiting_operator_approval, :operator_approval_denied} => :awaiting_documents,
    {:processing, :complete} => :completed
  }

  @doc "The closed set of status values (delegates to `LoanActor.State`, the single source)."
  @spec statuses() :: [status()]
  def statuses, do: State.statuses()

  @doc "The closed set of event types documented in data-model.md, whether or not they drive a transition."
  @spec event_types() :: [event_type()]
  def event_types, do: @event_types

  @doc "`{:ok, next_status}` if `{status, event_type}` is a legal edge, else `:error`."
  @spec next_status(status(), event_type()) :: {:ok, status()} | :error
  def next_status(status, event_type), do: Map.fetch(@edges, {status, event_type})

  @doc "Whether `{status, event_type}` is a legal edge."
  @spec legal?(status(), event_type()) :: boolean()
  def legal?(status, event_type), do: Map.has_key?(@edges, {status, event_type})

  @doc """
  Every event type with a legal edge out of `status`, in enum order.
  `[]` for terminal/unreachable states (`:completed`, `:errored`).
  """
  @spec next_events_for(status()) :: [event_type()]
  def next_events_for(status) do
    Enum.filter(@event_types, &legal?(status, &1))
  end

  @doc """
  The subset of `event_types/0` that has a legal edge from AT LEAST ONE
  status — i.e. an event type that can actually drive `State.transition/2`
  somewhere. Narrower than `event_types/0`: the four types this
  moduledoc already documents as having no edge anywhere
  (`:document_review_requested`, `:heartbeat`, `:goal_abandoned`,
  `:abort`) are valid `%LoanActor.Event{}` types but never belong in this
  set. `LoanActor.Server.rehydrate/2` (FT-017, fixed by FT-034's property
  test) uses this — not `event_types/0` — to decide which diary entries
  replay through `State.transition/2`: feeding it a type with no edge
  ANYWHERE always raises `LoanActor.IllegalTransitionError`, and every
  long-lived loan's diary contains `:heartbeat` entries by the time it
  first crashes, so using the wrong set here was a real, always-reachable
  rehydration bug, not a hypothetical one.
  """
  @spec transition_driving_event_types() :: MapSet.t(event_type())
  def transition_driving_event_types do
    @edges |> Map.keys() |> Enum.map(fn {_status, event_type} -> event_type end) |> MapSet.new()
  end

  @doc """
  Every documented edge as `{status, event_type, next_status}` — the happy-path
  table property/example tests enumerate.
  """
  @spec edges() :: [{status(), event_type(), status()}]
  def edges, do: for({{s, e}, n} <- @edges, do: {s, e, n})
end
