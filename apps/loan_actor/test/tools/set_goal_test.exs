defmodule LoanActor.Tools.SetGoalTest do
  @moduledoc """
  FT-043 — `LoanActor.Tools.SetGoal`. Taxonomy: happy / boundary / error / replay.
  """

  use LoanActor.ToolSharedTests, tool: LoanActor.Tools.SetGoal

  alias LoanActor.Factory
  alias LoanActor.Goal
  alias LoanActor.Tools.SetGoal

  def example_args, do: %{"description" => "obtain income documentation"}

  describe "execute/2 — happy" do
    test "returns an add_goal effect carrying a validated, :open Goal" do
      ctx = Factory.tool_context()
      assert {:ok, %{add_goal: %Goal{} = goal}} = SetGoal.execute(example_args(), ctx)
      assert goal.description == "obtain income documentation"
      assert goal.status == :open
      assert goal.due_at == nil
      assert goal.goal_id == ctx.invocation_id
    end

    test "a due_at ISO8601 string is parsed into a DateTime" do
      args = Map.put(example_args(), "due_at", "2026-08-01T00:00:00Z")
      {:ok, %{add_goal: goal}} = SetGoal.execute(args, Factory.tool_context())
      assert goal.due_at == ~U[2026-08-01 00:00:00Z]
    end
  end

  describe "execute/2 — error" do
    test "an invalid due_at is rejected without constructing a goal" do
      args = Map.put(example_args(), "due_at", "not-a-date")
      assert {:error, {:invalid_due_at, _reason}} =
               SetGoal.execute(args, Factory.tool_context())
    end
  end

  describe "execute/2 — replay (determinism, beyond the shared suite's single check)" do
    test "the same ctx.invocation_id always yields the same goal_id" do
      ctx = Factory.tool_context(%{invocation_id: "inv-fixed"})
      {:ok, %{add_goal: g1}} = SetGoal.execute(example_args(), ctx)
      {:ok, %{add_goal: g2}} = SetGoal.execute(example_args(), ctx)
      assert g1 == g2
    end
  end
end
