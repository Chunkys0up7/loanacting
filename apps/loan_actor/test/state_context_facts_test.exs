defmodule LoanActor.StateContextFactsTest do
  @moduledoc """
  ADH-008 — `LoanActor.State`'s incremental diary-derived facts
  (`set_context_fact/3`, `record_goal_created_at/3`; `research.md` R-3).
  Taxonomy: happy / boundary / replay.

  The replay invariant (R-3's own wording): "for any diary prefix,
  folding the incremental update handlers over it MUST produce a
  `state.context` identical to computing the same facts by a full,
  from-scratch derivation over that same prefix." Proven here as a pure
  property over a synthetic operation sequence — mirrors
  `replay_test.exs`'s own established shape (an incremental fold vs. an
  independently-written "ground truth" computation), scoped to the fold
  mechanism itself: goal-keyed facts still inherit `rehydrate/2`'s own,
  separately-tracked, pre-existing gap (goals aren't reconstructed from a
  real diary at all yet) — this test does not claim to close that gap.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias LoanActor.Factory
  alias LoanActor.State

  @goal_ids ~w(goal-a goal-b goal-c)

  defp timestamp_gen do
    StreamData.integer(0..1_000_000)
    |> StreamData.map(&DateTime.add(~U[2026-01-01 00:00:00Z], &1, :second))
  end

  defp operation_gen do
    StreamData.one_of([
      StreamData.constant({:document_uploaded}),
      StreamData.bind(StreamData.member_of(@goal_ids), fn goal_id ->
        StreamData.map(timestamp_gen(), &{:goal_created, goal_id, &1})
      end)
    ])
  end

  defp operations_gen, do: StreamData.list_of(operation_gen(), max_length: 20)

  # Incremental: thread a REAL %State{} through the actual State module
  # functions, one operation at a time — exactly how the Server applies
  # them live (apply_context_facts/2, apply_add_goal/2).
  defp apply_incremental(state, {:document_uploaded}) do
    State.set_context_fact(state, "document_completeness", :complete)
  end

  defp apply_incremental(state, {:goal_created, goal_id, timestamp}) do
    State.record_goal_created_at(state, goal_id, timestamp)
  end

  defp fold_incremental(operations) do
    Enum.reduce(operations, Factory.state(), &apply_incremental(&2, &1))
  end

  # Full, from-scratch derivation — an INDEPENDENTLY-written ground
  # truth, not the same fold restated: document_completeness is "any
  # occurrence anywhere in the list"; goal_created_at is grouped, then
  # last-occurrence-wins — both computed over the WHOLE list at once,
  # never threading a %State{} at all.
  defp recompute_context(operations) do
    %{}
    |> maybe_put("document_completeness", recompute_document_completeness(operations))
    |> maybe_put("goal_created_at", recompute_goal_created_at(operations))
  end

  defp recompute_document_completeness(operations) do
    if Enum.any?(operations, &match?({:document_uploaded}, &1)), do: :complete, else: nil
  end

  defp recompute_goal_created_at(operations) do
    created =
      operations
      |> Enum.filter(&match?({:goal_created, _, _}, &1))
      |> Enum.group_by(fn {:goal_created, goal_id, _ts} -> goal_id end)
      |> Map.new(fn {goal_id, occurrences} ->
        {:goal_created, ^goal_id, last_timestamp} = List.last(occurrences)
        {goal_id, last_timestamp}
      end)

    if created == %{}, do: nil, else: created
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  describe "prefix-consistency — property (R-3's replay invariant)" do
    property "any prefix's incremental fold matches a from-scratch recomputation over that same prefix" do
      check all(operations <- operations_gen(), max_runs: 100) do
        for prefix_length <- 0..length(operations) do
          prefix = Enum.take(operations, prefix_length)

          incremental = fold_incremental(prefix).context
          recomputed = recompute_context(prefix)

          assert incremental == recomputed
        end
      end
    end
  end

  describe "set_context_fact/3 — happy" do
    test "sets a key, last-write-wins on repeated calls" do
      state = Factory.state()
      state = State.set_context_fact(state, "document_completeness", :incomplete)
      state = State.set_context_fact(state, "document_completeness", :complete)
      assert state.context["document_completeness"] == :complete
    end
  end

  describe "record_goal_created_at/3 — happy + boundary" do
    test "records a timestamp under goal_created_at, keyed by goal_id" do
      state = Factory.state()
      timestamp = ~U[2026-01-01 00:00:00Z]
      state = State.record_goal_created_at(state, "goal-1", timestamp)
      assert state.context["goal_created_at"]["goal-1"] == timestamp
    end

    test "recording a second goal_id does not overwrite the first" do
      state = Factory.state()
      state = State.record_goal_created_at(state, "goal-1", ~U[2026-01-01 00:00:00Z])
      state = State.record_goal_created_at(state, "goal-2", ~U[2026-01-02 00:00:00Z])

      assert state.context["goal_created_at"]["goal-1"] == ~U[2026-01-01 00:00:00Z]
      assert state.context["goal_created_at"]["goal-2"] == ~U[2026-01-02 00:00:00Z]
    end
  end
end
