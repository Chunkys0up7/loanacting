defmodule LoanActor.StateTest do
  @moduledoc """
  FT-010 — `LoanActor.State` struct + validated constructor.
  Taxonomy: happy / boundary / error. Boundary explicitly covers every
  status enum value (per the FT-010 task's stated test requirement).
  Data via `LoanActor.Factory` (test-data-forge).
  """

  use ExUnit.Case, async: true

  alias LoanActor.Factory
  alias LoanActor.State

  describe "new/1 — happy" do
    test "builds a fresh :spawned state with foundation defaults" do
      state = Factory.state()

      assert %State{
               status: :spawned,
               goals: [],
               context: %{},
               version: 0,
               last_heartbeat_at: nil
             } = state

      assert state.loan_id != ""
    end

    test "accepts a populated goals list and context" do
      goals = [Factory.goal(), Factory.goal(%{status: :satisfied})]
      state = Factory.state(%{goals: goals, context: %{"note" => "x"}})
      assert state.goals == goals
      assert state.context == %{"note" => "x"}
    end
  end

  describe "statuses/0 — boundary (every status enum value)" do
    test "every documented status builds a valid state" do
      for status <- State.statuses() do
        assert %State{status: ^status} = Factory.state_at(status)
      end
    end

    test "statuses/0 is exactly the seven documented values, including :errored" do
      assert State.statuses() == [
               :spawned,
               :awaiting_documents,
               :documents_under_review,
               :awaiting_operator_approval,
               :processing,
               :completed,
               :errored
             ]
    end
  end

  describe "new/1 — boundary" do
    test "version accepts zero (the initial value)" do
      assert %State{version: 0} = Factory.state(%{version: 0})
    end

    test "version accepts an arbitrary positive integer" do
      assert %State{version: 42} = Factory.state(%{version: 42})
    end

    test "goals accepts an empty list and a multi-element list" do
      assert %State{goals: []} = Factory.state(%{goals: []})
      many = for _ <- 1..5, do: Factory.goal()
      assert %State{goals: ^many} = Factory.state(%{goals: many})
    end
  end

  describe "new/1 — error (parametrized invalid catalog)" do
    test "every invalid variant raises ArgumentError" do
      for {label, attrs} <- Factory.invalid_state_variants() do
        assert_raise ArgumentError, fn -> State.new(attrs) end
        _ = label
      end
    end

    test "missing loan_id raises KeyError" do
      assert_raise KeyError, fn -> State.new(%{}) end
    end

    test "goals containing a non-Goal element is rejected even alongside valid ones" do
      attrs = Factory.state_attrs(%{goals: [Factory.goal(), %{not: "a goal"}]})
      assert_raise ArgumentError, fn -> State.new(attrs) end
    end
  end

  describe "add_goal/2 — happy (added in support of FT-018)" do
    test "prepends the goal to an empty goals list" do
      state = Factory.state()
      goal = Factory.goal()
      new_state = State.add_goal(state, goal)
      assert new_state.goals == [goal]
    end

    test "does not change status or version" do
      state = Factory.state(%{version: 3, status: :awaiting_documents})
      new_state = State.add_goal(state, Factory.goal())
      assert new_state.status == :awaiting_documents
      assert new_state.version == 3
    end

    test "appends alongside existing goals without disturbing them" do
      existing = Factory.goal()
      state = Factory.state(%{goals: [existing]})
      added = Factory.goal()
      new_state = State.add_goal(state, added)
      assert new_state.goals == [added, existing]
    end
  end

  describe "satisfy_goal/2 — happy + boundary (added in support of FT-018)" do
    test "marks the matching goal :satisfied, leaves others untouched" do
      g1 = Factory.goal(%{goal_id: "G-1"})
      g2 = Factory.goal(%{goal_id: "G-2"})
      state = Factory.state(%{goals: [g1, g2]})

      new_state = State.satisfy_goal(state, "G-1")
      assert Enum.find(new_state.goals, &(&1.goal_id == "G-1")).status == :satisfied
      assert Enum.find(new_state.goals, &(&1.goal_id == "G-2")).status == :open
    end

    test "a goal_id with no match is a no-op (defensive fallback)" do
      state = Factory.state(%{goals: [Factory.goal(%{goal_id: "G-1"})]})
      new_state = State.satisfy_goal(state, "G-nonexistent")
      assert new_state == state
    end
  end

  describe "record_heartbeat/2 — happy (added in support of FT-018)" do
    test "sets last_heartbeat_at, leaves everything else untouched" do
      state = Factory.state(%{version: 2, status: :spawned})
      ts = ~U[2026-07-21 12:00:00Z]
      new_state = State.record_heartbeat(state, ts)
      assert new_state.last_heartbeat_at == ts
      assert new_state.version == 2
      assert new_state.status == :spawned
    end
  end
end
