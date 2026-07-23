defmodule LoanActor.Tools.AssessLoanTest do
  @moduledoc """
  ADH-002 — `LoanActor.Tools.AssessLoan`.
  Taxonomy: happy / boundary / replay (determinism).
  """

  use LoanActor.ToolSharedTests, tool: LoanActor.Tools.AssessLoan
  use ExUnitProperties

  alias LoanActor.Factory
  alias LoanActor.State
  alias LoanActor.Tools.AssessLoan

  def example_args, do: %{}

  def example_ctx do
    Factory.tool_context(%{state: Factory.state(%{loan_id: "L-assess-loan"})})
  end

  describe "execute/2 — happy" do
    test "an empty, fresh state assesses as unknown completeness, n/a SLA, no goal ages" do
      ctx = Factory.tool_context(%{state: Factory.state()})
      assert {:ok, %{assessment: assessment}} = AssessLoan.execute(%{}, ctx)
      assert assessment.document_completeness == :unknown
      assert assessment.sla_state == :n_a
      assert assessment.goal_ages == %{}
    end

    test "reads document_completeness from state.context" do
      state = Factory.state(%{context: %{"document_completeness" => :complete}})
      ctx = Factory.tool_context(%{state: state})
      assert {:ok, %{assessment: %{document_completeness: :complete}}} = AssessLoan.execute(%{}, ctx)
    end

    test "computed_at_version mirrors state.version" do
      state = Factory.state(%{version: 3})
      ctx = Factory.tool_context(%{state: state})
      assert {:ok, %{assessment: %{computed_at_version: 3}}} = AssessLoan.execute(%{}, ctx)
    end

    test "goal_ages computed from last_heartbeat_at minus context goal_created_at, for open goals only" do
      now = ~U[2026-07-23 12:00:00Z]
      created = ~U[2026-07-23 11:00:00Z]

      goal = Factory.goal(%{goal_id: "G-1", status: :open})
      satisfied_goal = Factory.goal(%{goal_id: "G-2", status: :satisfied})

      state =
        Factory.state(%{
          goals: [goal, satisfied_goal],
          last_heartbeat_at: now,
          context: %{"goal_created_at" => %{"G-1" => created, "G-2" => created}}
        })

      ctx = Factory.tool_context(%{state: state})
      assert {:ok, %{assessment: %{goal_ages: goal_ages}}} = AssessLoan.execute(%{}, ctx)

      assert goal_ages == %{"G-1" => 3_600_000}
      refute Map.has_key?(goal_ages, "G-2")
    end

    test "sla_state is :breached when an open goal's due_at is before last_heartbeat_at" do
      state =
        Factory.state(%{
          goals: [Factory.goal(%{due_at: ~U[2026-07-01 00:00:00Z], status: :open})],
          last_heartbeat_at: ~U[2026-07-02 00:00:00Z]
        })

      ctx = Factory.tool_context(%{state: state})
      assert {:ok, %{assessment: %{sla_state: :breached}}} = AssessLoan.execute(%{}, ctx)
    end

    test "sla_state is :at_risk when due_at is within the risk window of last_heartbeat_at" do
      now = ~U[2026-07-23 00:00:00Z]

      state =
        Factory.state(%{
          goals: [Factory.goal(%{due_at: DateTime.add(now, 3_600, :second), status: :open})],
          last_heartbeat_at: now
        })

      ctx = Factory.tool_context(%{state: state})
      assert {:ok, %{assessment: %{sla_state: :at_risk}}} = AssessLoan.execute(%{}, ctx)
    end

    test "sla_state is :on_track when due_at is far in the future" do
      now = ~U[2026-07-23 00:00:00Z]

      state =
        Factory.state(%{
          goals: [Factory.goal(%{due_at: DateTime.add(now, 30, :day), status: :open})],
          last_heartbeat_at: now
        })

      ctx = Factory.tool_context(%{state: state})
      assert {:ok, %{assessment: %{sla_state: :on_track}}} = AssessLoan.execute(%{}, ctx)
    end
  end

  describe "execute/2 — boundary" do
    test "no goals with due_at at all is :n_a, not :on_track" do
      state = Factory.state(%{goals: [Factory.goal(%{due_at: nil, status: :open})]})
      ctx = Factory.tool_context(%{state: state})
      assert {:ok, %{assessment: %{sla_state: :n_a}}} = AssessLoan.execute(%{}, ctx)
    end

    test "nil last_heartbeat_at with a due goal is :on_track (never crashes on a nil clock)" do
      state =
        Factory.state(%{
          goals: [Factory.goal(%{due_at: ~U[2026-01-01 00:00:00Z], status: :open})],
          last_heartbeat_at: nil
        })

      ctx = Factory.tool_context(%{state: state})
      assert {:ok, %{assessment: %{sla_state: :on_track}}} = AssessLoan.execute(%{}, ctx)
    end

    test "an unrecognized state.context completeness value defaults to :unknown rather than raising" do
      state = Factory.state(%{context: %{"document_completeness" => :something_unexpected}})
      ctx = Factory.tool_context(%{state: state})
      assert {:ok, %{assessment: %{document_completeness: :unknown}}} = AssessLoan.execute(%{}, ctx)
    end
  end

  describe "execute/2 — replay (determinism property, FR-001/research.md R-6)" do
    property "the same state always produces the same assessment" do
      check all(event_types <- Factory.legal_event_walk_gen(), max_runs: 50) do
        loan_id = Factory.unique_loan_id()

        state =
          Enum.reduce(event_types, Factory.state(%{loan_id: loan_id}), fn event_type, acc ->
            State.transition(acc, event_type)
          end)

        ctx = Factory.tool_context(%{state: state})
        assert AssessLoan.execute(%{}, ctx) == AssessLoan.execute(%{}, ctx)
      end
    end
  end
end
