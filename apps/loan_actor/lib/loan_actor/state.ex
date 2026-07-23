defmodule LoanActor.State do
  @moduledoc """
  In-memory loan state (FT-010) + the single mutation gate `transition/2`
  (FT-011). Held by `LoanActor.Server`; persisted only via diary replay
  (constitution Principle IV) — never directly stored.

  Fields per `specs/001-loan-actor-foundation/data-model.md` `%LoanActor.State{}`.

  `transition/2` is pure — no I/O, no diary append. Per clarifications Q4,
  the invariant "every mutation is paired with a diary append" is enforced
  by the Server (FT-017): it calls `transition/2`, and on success appends the
  diary entry in the same atomic step; on `LoanActor.IllegalTransitionError`
  it appends the documented `:illegal_transition_attempted` entry instead.
  That pairing is a Server concern, not this module's.

  Direct struct updates outside `transition/2` are a constitution violation,
  detected by the custom Credo check `LoanActor.Credo.NoDirectStateMutation`
  (FT-012).

  `add_goal/2`, `satisfy_goal/2`, and `record_heartbeat/2` (added in
  support of FT-018) cover the mutation surface `transition/2` deliberately
  does not: goals and `last_heartbeat_at` are not part of the status
  state-machine graph, so nothing about them belongs in `transition/2` —
  but they still must not be mutated ad hoc outside this module, so they
  live here as their own named functions, using the same bare `%{state |
  ...}` form `transition/2` uses (not the struct-named form the Credo
  check watches for — deliberately consistent, not a loophole: this
  module IS the sanctioned place for all of it).
  """

  alias LoanActor.Goal
  alias LoanActor.State.Model

  @statuses [
    :spawned,
    :awaiting_documents,
    :documents_under_review,
    :awaiting_operator_approval,
    :processing,
    :completed,
    :errored
  ]

  @enforce_keys [:loan_id, :status, :goals, :context, :version]
  defstruct [:loan_id, :status, :goals, :context, :version, :last_heartbeat_at]

  @type status ::
          :spawned
          | :awaiting_documents
          | :documents_under_review
          | :awaiting_operator_approval
          | :processing
          | :completed
          | :errored

  @type t :: %__MODULE__{
          loan_id: String.t(),
          status: status(),
          goals: [Goal.t()],
          context: map(),
          version: non_neg_integer(),
          last_heartbeat_at: DateTime.t() | nil
        }

  @doc "The closed set of legal `status` values (the state-machine's status enum)."
  @spec statuses() :: [status()]
  def statuses, do: @statuses

  @doc """
  Build a new state. Defaults: a freshly `:spawned` loan, no goals, empty
  context, `version: 0`, no heartbeat yet. Raises `ArgumentError` on
  invariant violations.
  """
  @spec new(map() | keyword()) :: t()
  def new(attrs) do
    attrs = Map.new(attrs)

    fields = %{
      loan_id: attrs |> Map.fetch!(:loan_id) |> validate_loan_id(),
      status: attrs |> Map.get(:status, :spawned) |> validate_status(),
      goals: attrs |> Map.get(:goals, []) |> validate_goals(),
      context: attrs |> Map.get(:context, %{}) |> validate_context(),
      version: attrs |> Map.get(:version, 0) |> validate_version(),
      last_heartbeat_at: attrs |> Map.get(:last_heartbeat_at) |> validate_last_heartbeat_at()
    }

    struct!(__MODULE__, fields)
  end

  @doc """
  Advance `state` by `event_type`, per the graph in `LoanActor.State.Model`.

  Returns the new state on a legal edge: `status` updated, `version`
  incremented by 1. `goals`/`context`/`last_heartbeat_at` are unchanged here
  — those are mutated by other means introduced in later tasks (tools).

  Raises `LoanActor.IllegalTransitionError` (carrying `from` and
  `event_type`) if `{state.status, event_type}` has no edge.
  """
  @spec transition(t(), Model.event_type()) :: t()
  def transition(%__MODULE__{status: status} = state, event_type) do
    case Model.next_status(status, event_type) do
      {:ok, next_status} ->
        %{state | status: next_status, version: state.version + 1}

      :error ->
        raise LoanActor.IllegalTransitionError, from: status, event_type: event_type
    end
  end

  @doc """
  Append `goal` to `state.goals`. Does not touch `status`/`version` — per
  the field's own documentation, `version` increments only on
  `transition/2`-driven status changes.
  """
  @spec add_goal(t(), Goal.t()) :: t()
  def add_goal(%__MODULE__{} = state, %Goal{} = goal) do
    %{state | goals: [goal | state.goals]}
  end

  @doc """
  Mark the goal with `goal_id` `:satisfied`. A no-op if no such goal
  exists — callers (the `satisfy_goal` tool) are expected to have already
  confirmed existence via a pure read of the same `state`, so this is a
  defensive fallback, not a normal path.
  """
  @spec satisfy_goal(t(), String.t()) :: t()
  def satisfy_goal(%__MODULE__{} = state, goal_id) do
    goals =
      Enum.map(state.goals, fn
        %Goal{goal_id: ^goal_id} = goal -> %{goal | status: :satisfied}
        other -> other
      end)

    %{state | goals: goals}
  end

  @doc "Record that the periodic loop fired at `timestamp` (FT-018)."
  @spec record_heartbeat(t(), DateTime.t()) :: t()
  def record_heartbeat(%__MODULE__{} = state, %DateTime{} = timestamp) do
    %{state | last_heartbeat_at: timestamp}
  end

  @doc """
  Set a single `state.context` fact key (intent 0003, ADH-008; `research.md`
  R-3's incremental-facts mechanism — the same shape as `add_goal/2`,
  extended to `context` instead of `goals`). Last-write-wins per key;
  callers decide when a fact changes (e.g. the reactive pipeline, on a
  `:document_uploaded` event, sets `"document_completeness" => :complete`).
  """
  @spec set_context_fact(t(), String.t(), term()) :: t()
  def set_context_fact(%__MODULE__{} = state, key, value) when is_binary(key) do
    %{state | context: Map.put(state.context, key, value)}
  end

  @doc """
  Record `goal_id`'s creation `timestamp` under `state.context["goal_created_at"]`
  (intent 0003, ADH-008) — the incremental fact `LoanActor.Assessment.goal_ages/1`
  reads. Called alongside `add_goal/2` at the same call site (the `set_goal`
  tool's effect application), never independently — a goal without a
  recorded creation time is a bug in that call site, not a state this
  function needs to guard against.
  """
  @spec record_goal_created_at(t(), String.t(), DateTime.t()) :: t()
  def record_goal_created_at(%__MODULE__{} = state, goal_id, %DateTime{} = timestamp) when is_binary(goal_id) do
    created_ats = Map.get(state.context, "goal_created_at", %{})
    %{state | context: Map.put(state.context, "goal_created_at", Map.put(created_ats, goal_id, timestamp))}
  end

  defp validate_loan_id(v) when is_binary(v) and byte_size(v) > 0, do: v

  defp validate_loan_id(v),
    do: raise(ArgumentError, "loan_id must be a non-empty binary, got: #{inspect(v)}")

  defp validate_status(v) when v in @statuses, do: v

  defp validate_status(v),
    do: raise(ArgumentError, "status must be one of #{inspect(@statuses)}, got: #{inspect(v)}")

  defp validate_goals(v) when is_list(v) do
    if Enum.all?(v, &match?(%Goal{}, &1)) do
      v
    else
      raise ArgumentError, "goals must be a list of %LoanActor.Goal{}, got: #{inspect(v)}"
    end
  end

  defp validate_goals(v), do: raise(ArgumentError, "goals must be a list, got: #{inspect(v)}")

  defp validate_context(v) when is_map(v), do: v
  defp validate_context(v), do: raise(ArgumentError, "context must be a map, got: #{inspect(v)}")

  defp validate_version(v) when is_integer(v) and v >= 0, do: v

  defp validate_version(v),
    do: raise(ArgumentError, "version must be a non-negative integer, got: #{inspect(v)}")

  defp validate_last_heartbeat_at(nil), do: nil
  defp validate_last_heartbeat_at(%DateTime{} = v), do: v

  defp validate_last_heartbeat_at(v),
    do: raise(ArgumentError, "last_heartbeat_at must be nil or a DateTime, got: #{inspect(v)}")
end
