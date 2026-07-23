defmodule LoanActor.Tools.SatisfyGoalTest do
  @moduledoc """
  FT-043 — `LoanActor.Tools.SatisfyGoal`. Taxonomy: happy / boundary / error.
  """

  use LoanActor.ToolSharedTests, tool: LoanActor.Tools.SatisfyGoal

  alias LoanActor.Factory
  alias LoanActor.Tools.SatisfyGoal

  @goal_id "G-existing"

  def example_args, do: %{"goal_id" => @goal_id}

  def example_ctx do
    Factory.tool_context(%{state: %{goals: [Factory.goal(%{goal_id: @goal_id})]}})
  end

  describe "execute/2 — happy" do
    test "returns a satisfy_goal effect when the goal exists in ctx.state" do
      assert {:ok, %{satisfy_goal: @goal_id}} =
               SatisfyGoal.execute(example_args(), example_ctx())
    end
  end

  describe "execute/2 — error" do
    test "a goal_id absent from ctx.state.goals is rejected" do
      ctx = Factory.tool_context(%{state: %{goals: []}})
      assert {:error, :goal_not_found} = SatisfyGoal.execute(example_args(), ctx)
    end
  end

  describe "execute/2 — boundary" do
    test "a bare map state (no :goals key) is treated as having zero goals" do
      ctx = Factory.tool_context(%{state: %{}})
      assert {:error, :goal_not_found} = SatisfyGoal.execute(example_args(), ctx)
    end
  end
end
