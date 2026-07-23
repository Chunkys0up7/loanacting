defmodule LoanActor.Tools.EvaluateGateTest do
  @moduledoc """
  ADH-004 — `LoanActor.Tools.EvaluateGate`.
  Taxonomy: happy / boundary / error / replay (determinism).
  """

  use LoanActor.ToolSharedTests, tool: LoanActor.Tools.EvaluateGate
  use ExUnitProperties

  alias LoanActor.Factory
  alias LoanActor.State
  alias LoanActor.Tools.EvaluateGate

  def example_args, do: %{"gate_id" => "document-completeness"}

  def example_ctx do
    Factory.tool_context(%{
      gate: Factory.gate(),
      state: Factory.state(%{context: %{"document_completeness" => :complete}})
    })
  end

  describe "execute/2 — happy" do
    test "a passing gate reports :pass with the gate id/version/cause" do
      ctx = example_ctx()
      assert {:ok, %{gate_outcome: outcome}} = EvaluateGate.execute(example_args(), ctx)
      assert outcome.gate_id == "document-completeness"
      assert outcome.gate_version == "1.0.0"
      assert outcome.outcome == :pass
    end

    test "a failing gate reports :fail with a cause naming the failing field" do
      ctx =
        Factory.tool_context(%{
          gate: Factory.gate(),
          state: Factory.state(%{context: %{"document_completeness" => :incomplete}})
        })

      assert {:ok, %{gate_outcome: %{outcome: :fail, cause: cause}}} =
               EvaluateGate.execute(example_args(), ctx)

      assert cause =~ "document_completeness"
    end

    test "an indeterminate gate reports :indeterminate" do
      ctx =
        Factory.tool_context(%{
          gate: Factory.gate(),
          state: Factory.state(%{context: %{}})
        })

      assert {:ok, %{gate_outcome: %{outcome: :indeterminate}}} =
               EvaluateGate.execute(example_args(), ctx)
    end
  end

  describe "execute/2 — boundary" do
    test "the assessment is derived fresh from ctx.state, not passed via args" do
      gate =
        Factory.gate(%{
          rule: %{
            "combinator" => "all",
            "predicates" => [%{"field" => "assessment.sla_state", "op" => "eq", "value" => "breached"}]
          }
        })

      state =
        Factory.state(%{
          goals: [Factory.goal(%{due_at: ~U[2020-01-01 00:00:00Z], status: :open})],
          last_heartbeat_at: ~U[2026-01-01 00:00:00Z]
        })

      ctx = Factory.tool_context(%{gate: gate, state: state})
      assert {:ok, %{gate_outcome: %{outcome: :pass}}} = EvaluateGate.execute(%{"gate_id" => gate.gate_id}, ctx)
    end
  end

  describe "execute/2 — error" do
    test "ctx.gate absent (never resolved by the Server) is an error, not a crash" do
      ctx = Factory.tool_context(%{state: Factory.state()})
      assert {:error, {:gate_not_resolved, "document-completeness"}} =
               EvaluateGate.execute(example_args(), ctx)
    end

    test "ctx.gate present but its gate_id doesn't match args is an error, not a silent mismatch" do
      ctx = Factory.tool_context(%{gate: Factory.gate(%{gate_id: "other-gate"}), state: Factory.state()})
      assert {:error, {:gate_not_resolved, "document-completeness"}} =
               EvaluateGate.execute(example_args(), ctx)
    end
  end

  describe "execute/2 — replay (determinism, contract: gate-behaviour.md invariant 7)" do
    property "the same gate + same state always produces the same outcome" do
      check all(event_types <- Factory.legal_event_walk_gen(), max_runs: 30) do
        loan_id = Factory.unique_loan_id()

        state =
          Enum.reduce(event_types, Factory.state(%{loan_id: loan_id}), fn event_type, acc ->
            State.transition(acc, event_type)
          end)

        ctx = Factory.tool_context(%{gate: Factory.gate(), state: state})
        assert EvaluateGate.execute(example_args(), ctx) == EvaluateGate.execute(example_args(), ctx)
      end
    end
  end
end
