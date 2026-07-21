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
end
