defmodule LoanActor.StateTransitionTest do
  @moduledoc """
  FT-011 — `LoanActor.State.transition/2` + `LoanActor.State.Model`.

  Taxonomy: happy = every documented edge; error = every illegal
  `{status, event_type}` pair across the full closed universe (7 statuses ×
  11 event types). Data via `LoanActor.Factory` (test-data-forge).
  """

  use ExUnit.Case, async: true

  alias LoanActor.Factory
  alias LoanActor.IllegalTransitionError
  alias LoanActor.State
  alias LoanActor.State.Model

  describe "transition/2 — happy (every documented edge)" do
    test "each of the seven diagram edges advances status and increments version" do
      for {from, event_type, to} <- Model.edges() do
        state = Factory.state_at(from, %{version: 3})
        next = State.transition(state, event_type)

        assert next.status == to
        assert next.version == 4
        # unrelated fields are untouched by transition/2
        assert next.loan_id == state.loan_id
        assert next.goals == state.goals
        assert next.context == state.context
      end
    end

    test "there are exactly seven documented edges" do
      assert length(Model.edges()) == 7
    end
  end

  describe "transition/2 — error (every illegal pair)" do
    test "every {status, event_type} pair not in the edge table raises IllegalTransitionError" do
      legal = MapSet.new(Model.edges(), fn {s, e, _n} -> {s, e} end)

      for status <- Model.statuses(), event_type <- Model.event_types() do
        unless MapSet.member?(legal, {status, event_type}) do
          state = Factory.state_at(status)

          exception =
            assert_raise IllegalTransitionError, fn -> State.transition(state, event_type) end

          assert exception.from == status
          assert exception.event_type == event_type
        end
      end
    end

    test "the illegal universe is exactly 77 - 7 = 70 pairs" do
      total = length(Model.statuses()) * length(Model.event_types())
      assert total == 77
      assert total - length(Model.edges()) == 70
    end

    test "an illegal transition does not mutate the state (raise happens before any change)" do
      state = Factory.state_at(:spawned, %{version: 5})

      assert_raise IllegalTransitionError, fn ->
        State.transition(state, :complete)
      end

      # the original binding is provably untouched (Elixir immutability +
      # explicit re-check that no partial update occurred).
      assert state.status == :spawned
      assert state.version == 5
    end

    test "an event type outside the documented enum is also illegal" do
      state = Factory.state_at(:spawned)
      assert_raise IllegalTransitionError, fn -> State.transition(state, :not_a_real_event) end
    end
  end

  describe "Model.next_events_for/1 — boundary" do
    test "terminal/unreachable states have no legal next events" do
      assert Model.next_events_for(:completed) == []
      assert Model.next_events_for(:errored) == []
    end

    test "each non-terminal status's next_events_for matches the edge table (as a set — map iteration order is not guaranteed)" do
      for status <- Model.statuses() do
        expected =
          Model.edges()
          |> Enum.filter(fn {s, _e, _n} -> s == status end)
          |> Enum.map(fn {_s, e, _n} -> e end)
          |> MapSet.new()

        assert MapSet.new(Model.next_events_for(status)) == expected
      end
    end

    test "next_events_for/1 is ordered per the documented event-type enum (data-model.md), not map order" do
      documented_order = Model.event_types()

      for status <- Model.statuses() do
        actual = Model.next_events_for(status)
        expected_positions = Enum.map(actual, &Enum.find_index(documented_order, fn e -> e == &1 end))
        assert expected_positions == Enum.sort(expected_positions)
      end
    end
  end

  describe "Model.legal?/2 + next_status/2 — contract (internal consistency)" do
    test "legal?/2 agrees with next_status/2 for every pair in the closed universe" do
      for status <- Model.statuses(), event_type <- Model.event_types() do
        case Model.next_status(status, event_type) do
          {:ok, _next} -> assert Model.legal?(status, event_type)
          :error -> refute Model.legal?(status, event_type)
        end
      end
    end
  end
end
