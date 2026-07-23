defmodule LoanActor.Tools.AssessLoan do
  @moduledoc """
  Deterministic assessment derivation (intent 0003, ADH-002; FR-001).

  Reads ONLY `ctx.state` — no diary I/O, no wall-clock reads
  (`research.md` R-6) — so the same state always produces the same
  `%Assessment{}`. "Diary-derived facts" (goal creation timestamps,
  document-completeness signals) live in `state.context`, incrementally
  maintained by other handlers (`research.md` R-3, ADH-008) — this tool
  reads them, never recomputes them from the diary itself.

  Gracefully degrades before ADH-008's incremental-fact maintenance has
  ever run for a given loan: missing context keys default to the most
  neutral value (`:unknown` completeness, zero goal age) rather than
  raising, so this tool is usable standalone from the moment it lands.
  """

  @behaviour LoanActor.Tool

  alias LoanActor.Assessment
  alias LoanActor.Tool.Spec

  @at_risk_window_ms 24 * 60 * 60 * 1000

  @impl LoanActor.Tool
  def spec do
    Spec.new(%{
      name: "assess_loan",
      description: "Derive a deterministic assessment of the loan's current situation.",
      parameters: %{"type" => "object"}
    })
  end

  @impl LoanActor.Tool
  def execute(_args, ctx) do
    state = ctx.state

    assessment =
      Assessment.new(%{
        loan_id: state.loan_id,
        document_completeness: document_completeness(state),
        goal_ages: goal_ages(state),
        sla_state: sla_state(state),
        data_quality_flags: [],
        computed_at_version: state.version
      })

    {:ok, %{assessment: assessment}}
  end

  defp document_completeness(state) do
    case Map.get(state.context, "document_completeness", :unknown) do
      value when value in [:complete, :incomplete, :unknown] -> value
      _other -> :unknown
    end
  end

  defp goal_ages(state) do
    created_ats = Map.get(state.context, "goal_created_at", %{})

    state.goals
    |> Enum.filter(&(&1.status == :open))
    |> Map.new(fn goal ->
      {goal.goal_id, age_ms(state.last_heartbeat_at, Map.get(created_ats, goal.goal_id))}
    end)
  end

  defp age_ms(nil, _created_at), do: 0
  defp age_ms(_now, nil), do: 0
  defp age_ms(now, created_at), do: max(DateTime.diff(now, created_at, :millisecond), 0)

  defp sla_state(state) do
    open_with_due = Enum.filter(state.goals, &(&1.status == :open and &1.due_at != nil))

    cond do
      open_with_due == [] -> :n_a
      state.last_heartbeat_at == nil -> :on_track
      Enum.any?(open_with_due, &breached?(&1, state.last_heartbeat_at)) -> :breached
      Enum.any?(open_with_due, &at_risk?(&1, state.last_heartbeat_at)) -> :at_risk
      true -> :on_track
    end
  end

  defp breached?(goal, now), do: DateTime.compare(now, goal.due_at) == :gt

  defp at_risk?(goal, now) do
    ms_until_due = DateTime.diff(goal.due_at, now, :millisecond)
    ms_until_due >= 0 and ms_until_due <= @at_risk_window_ms
  end
end
