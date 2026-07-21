defmodule LoanActor.Tools.SatisfyGoal do
  @moduledoc """
  Marks an existing goal `:satisfied` (FT-043; planning loop). Returns the
  effect `%{satisfy_goal: goal_id}`; the Server (FT-019) applies it by
  updating the matching goal in `state.goals` and diary-logging
  `:goal_satisfied`. Reads `ctx.state` to confirm the goal actually exists
  (a pure lookup, no mutation) — `{:error, :goal_not_found}` otherwise.
  """

  @behaviour LoanActor.Tool

  alias LoanActor.Goal
  alias LoanActor.Tool.Spec

  @impl LoanActor.Tool
  def spec do
    Spec.new(%{
      name: "satisfy_goal",
      description: "Mark an open goal as satisfied.",
      parameters: %{
        "type" => "object",
        "properties" => %{"goal_id" => %{"type" => "string"}},
        "required" => ["goal_id"]
      }
    })
  end

  @impl LoanActor.Tool
  def execute(%{"goal_id" => goal_id}, ctx) do
    goals = state_goals(ctx.state)

    if Enum.any?(goals, &match?(%Goal{goal_id: ^goal_id}, &1)) do
      {:ok, %{satisfy_goal: goal_id}}
    else
      {:error, :goal_not_found}
    end
  end

  defp state_goals(%{goals: goals}) when is_list(goals), do: goals
  defp state_goals(_state), do: []
end
