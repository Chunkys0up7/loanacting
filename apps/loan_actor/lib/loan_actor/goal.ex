defmodule LoanActor.Goal do
  @moduledoc """
  An outstanding objective the planning loop pursues (FT-010).

  Fields per `specs/001-loan-actor-foundation/data-model.md` `%LoanActor.Goal{}`.
  Held in a `%LoanActor.State{}`'s `goals` list; mutated only via
  `LoanActor.State.transition/2` (goal-status changes are a later task's
  concern — this module is the struct + validated constructor only).
  """

  @statuses [:open, :satisfied, :abandoned]

  @enforce_keys [:goal_id, :description, :status]
  defstruct [:goal_id, :description, :status, :due_at]

  @type status :: :open | :satisfied | :abandoned

  @type t :: %__MODULE__{
          goal_id: String.t(),
          description: String.t(),
          status: status(),
          due_at: DateTime.t() | nil
        }

  @doc "The closed set of legal `status` values."
  @spec statuses() :: [status()]
  def statuses, do: @statuses

  @doc """
  Build a new goal. Raises `ArgumentError` on invariant violations. Defaults
  `status` to `:open` (a goal is created open).
  """
  @spec new(map() | keyword()) :: t()
  def new(attrs) do
    attrs = Map.new(attrs)

    fields = %{
      goal_id: attrs |> Map.fetch!(:goal_id) |> validate_binary(:goal_id),
      description: attrs |> Map.fetch!(:description) |> validate_binary(:description),
      status: attrs |> Map.get(:status, :open) |> validate_status(),
      due_at: attrs |> Map.get(:due_at) |> validate_due_at()
    }

    struct!(__MODULE__, fields)
  end

  defp validate_binary(v, _field) when is_binary(v) and byte_size(v) > 0, do: v

  defp validate_binary(v, field),
    do: raise(ArgumentError, "#{field} must be a non-empty binary, got: #{inspect(v)}")

  defp validate_status(v) when v in @statuses, do: v

  defp validate_status(v),
    do: raise(ArgumentError, "status must be one of #{inspect(@statuses)}, got: #{inspect(v)}")

  defp validate_due_at(nil), do: nil
  defp validate_due_at(%DateTime{} = v), do: v

  defp validate_due_at(v),
    do: raise(ArgumentError, "due_at must be nil or a DateTime, got: #{inspect(v)}")
end
