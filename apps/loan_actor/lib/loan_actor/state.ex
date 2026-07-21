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
