defmodule LoanActor.GoalTest do
  @moduledoc """
  FT-010 — `LoanActor.Goal` struct + validated constructor.
  Taxonomy: happy / boundary / error. Data via `LoanActor.Factory` (test-data-forge).
  """

  use ExUnit.Case, async: true

  alias LoanActor.Factory
  alias LoanActor.Goal

  describe "new/1 — happy" do
    test "builds a goal with defaults (status :open, due_at nil)" do
      goal = Factory.goal()
      assert %Goal{status: :open, due_at: nil} = goal
      assert goal.goal_id != ""
      assert goal.description != ""
    end

    test "accepts a due_at DateTime" do
      due = ~U[2026-08-01 00:00:00Z]
      goal = Factory.goal(%{due_at: due})
      assert goal.due_at == due
    end
  end

  describe "statuses/0 — boundary" do
    test "every documented status value builds a valid goal" do
      for status <- Goal.statuses() do
        assert %Goal{status: ^status} = Factory.goal(%{status: status})
      end
    end

    test "statuses/0 is exactly the three documented values" do
      assert Goal.statuses() == [:open, :satisfied, :abandoned]
    end
  end

  describe "new/1 — error (parametrized invalid catalog)" do
    test "every invalid variant raises ArgumentError" do
      for {label, attrs} <- Factory.invalid_goal_variants() do
        assert_raise ArgumentError, fn -> Goal.new(attrs) end
        _ = label
      end
    end

    test "missing required keys raise KeyError" do
      assert_raise KeyError, fn -> Goal.new(%{description: "x"}) end
      assert_raise KeyError, fn -> Goal.new(%{goal_id: "G-1"}) end
    end
  end
end
