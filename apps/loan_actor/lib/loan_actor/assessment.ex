defmodule LoanActor.Assessment do
  @moduledoc """
  A point-in-time, typed summary of a loan's situation (intent 0003, ADH-002).

  Fields per `specs/002-autonomous-decision-harness/data-model.md`
  `%LoanActor.Assessment{}`. Not itself persisted — reproducible by
  re-running `LoanActor.Tools.AssessLoan.execute/2` against the same
  state (purity invariant: `assess(state) == assess(state)`, always;
  see `research.md` R-6 — no wall-clock reads, no diary I/O).
  """

  @sla_states [:on_track, :at_risk, :breached, :n_a]
  @document_completeness_values [:complete, :incomplete, :unknown]

  @enforce_keys [
    :loan_id,
    :document_completeness,
    :goal_ages,
    :sla_state,
    :data_quality_flags,
    :computed_at_version
  ]
  defstruct [
    :loan_id,
    :document_completeness,
    :goal_ages,
    :sla_state,
    :data_quality_flags,
    :computed_at_version
  ]

  @type document_completeness :: :complete | :incomplete | :unknown
  @type sla_state :: :on_track | :at_risk | :breached | :n_a

  @type t :: %__MODULE__{
          loan_id: String.t(),
          document_completeness: document_completeness(),
          goal_ages: %{String.t() => non_neg_integer()},
          sla_state: sla_state(),
          data_quality_flags: [atom()],
          computed_at_version: non_neg_integer()
        }

  @doc "The closed set of legal `document_completeness` values."
  @spec document_completeness_values() :: [document_completeness()]
  def document_completeness_values, do: @document_completeness_values

  @doc "The closed set of legal `sla_state` values."
  @spec sla_states() :: [sla_state()]
  def sla_states, do: @sla_states

  @doc """
  Build a validated assessment. Raises `ArgumentError` on invariant
  violations. Defaults `data_quality_flags` to `[]`.
  """
  @spec new(map() | keyword()) :: t()
  def new(attrs) do
    attrs = Map.new(attrs)

    fields = %{
      loan_id: attrs |> Map.fetch!(:loan_id) |> validate_binary(:loan_id),
      document_completeness:
        attrs |> Map.fetch!(:document_completeness) |> validate_document_completeness(),
      goal_ages: attrs |> Map.fetch!(:goal_ages) |> validate_goal_ages(),
      sla_state: attrs |> Map.fetch!(:sla_state) |> validate_sla_state(),
      data_quality_flags: attrs |> Map.get(:data_quality_flags, []) |> validate_flags(),
      computed_at_version: attrs |> Map.fetch!(:computed_at_version) |> validate_version()
    }

    struct!(__MODULE__, fields)
  end

  defp validate_binary(v, _field) when is_binary(v) and byte_size(v) > 0, do: v

  defp validate_binary(v, field),
    do: raise(ArgumentError, "#{field} must be a non-empty binary, got: #{inspect(v)}")

  defp validate_document_completeness(v) when v in @document_completeness_values, do: v

  defp validate_document_completeness(v),
    do:
      raise(
        ArgumentError,
        "document_completeness must be one of #{inspect(@document_completeness_values)}, got: #{inspect(v)}"
      )

  defp validate_goal_ages(v) when is_map(v) do
    if Enum.all?(v, fn {k, age} -> is_binary(k) and is_integer(age) and age >= 0 end) do
      v
    else
      raise(ArgumentError, "goal_ages must be a map of goal_id => non_neg_integer, got: #{inspect(v)}")
    end
  end

  defp validate_goal_ages(v),
    do: raise(ArgumentError, "goal_ages must be a map, got: #{inspect(v)}")

  defp validate_sla_state(v) when v in @sla_states, do: v

  defp validate_sla_state(v),
    do: raise(ArgumentError, "sla_state must be one of #{inspect(@sla_states)}, got: #{inspect(v)}")

  defp validate_flags(v) when is_list(v) do
    if Enum.all?(v, &is_atom/1) do
      v
    else
      raise(ArgumentError, "data_quality_flags must be a list of atoms, got: #{inspect(v)}")
    end
  end

  defp validate_flags(v),
    do: raise(ArgumentError, "data_quality_flags must be a list, got: #{inspect(v)}")

  defp validate_version(v) when is_integer(v) and v >= 0, do: v

  defp validate_version(v),
    do: raise(ArgumentError, "computed_at_version must be a non_neg_integer, got: #{inspect(v)}")
end
