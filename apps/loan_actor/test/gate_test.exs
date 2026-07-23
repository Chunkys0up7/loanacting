defmodule LoanActor.GateTest do
  @moduledoc """
  ADH-003 — `LoanActor.Gate` (rule-predicate DSL parser + evaluator).
  Taxonomy: happy / boundary / error / contract (pins `contracts/gate-behaviour.md`'s hard cap).
  """

  use ExUnit.Case, async: true

  alias LoanActor.Factory
  alias LoanActor.Gate

  defp eval_ctx(assessment_overrides \\ %{}, state_overrides \\ %{}) do
    %{
      assessment: Factory.assessment(assessment_overrides),
      state: Factory.state(state_overrides)
    }
  end

  describe "new/1 — happy" do
    test "parses a valid single-predicate rule" do
      assert {:ok, %Gate{gate_id: "document-completeness", version: "1.0.0", combinator: :all}} =
               Gate.new(Factory.gate_attrs())
    end

    test "parses an :any combinator" do
      attrs =
        Factory.gate_attrs(%{
          rule: %{
            "combinator" => "any",
            "predicates" => [
              %{"field" => "assessment.sla_state", "op" => "eq", "value" => "on_track"}
            ]
          }
        })

      assert {:ok, %Gate{combinator: :any}} = Gate.new(attrs)
    end

    test "parses a nested predicate group (one level)" do
      attrs =
        Factory.gate_attrs(%{
          rule: %{
            "combinator" => "all",
            "predicates" => [
              %{
                "combinator" => "any",
                "predicates" => [
                  %{"field" => "assessment.sla_state", "op" => "eq", "value" => "on_track"},
                  %{"field" => "assessment.sla_state", "op" => "eq", "value" => "n_a"}
                ]
              }
            ]
          }
        })

      assert {:ok, %Gate{predicates: [%{combinator: :any, predicates: [_, _]}]}} = Gate.new(attrs)
    end
  end

  describe "ops/0 and combinators/0 — boundary" do
    test "ops/0 is exactly the nine documented operators" do
      assert Gate.ops() == [:eq, :neq, :gt, :gte, :lt, :lte, :present, :absent, :contains]
    end

    test "combinators/0 is exactly the two documented values" do
      assert Gate.combinators() == [:all, :any]
    end

    test "every op parses successfully with an appropriately-shaped value" do
      for op <- Gate.ops() -- [:present, :absent] do
        value = "x"

        attrs =
          Factory.gate_attrs(%{
            rule: %{
              "combinator" => "all",
              "predicates" => [%{"field" => "assessment.loan_id", "op" => Atom.to_string(op), "value" => value}]
            }
          })

        assert {:ok, _gate} = Gate.new(attrs)
      end
    end

    test "present/absent parse successfully with no value" do
      for op <- [:present, :absent] do
        attrs =
          Factory.gate_attrs(%{
            rule: %{
              "combinator" => "all",
              "predicates" => [%{"field" => "assessment.loan_id", "op" => Atom.to_string(op)}]
            }
          })

        assert {:ok, _gate} = Gate.new(attrs)
      end
    end
  end

  describe "new/1 — error (parametrized invalid catalog, contract: hard-capped grammar)" do
    test "every invalid variant returns {:error, _}, never raises" do
      for {label, attrs} <- Factory.invalid_gate_variants() do
        assert {:error, _reason} = Gate.new(attrs)
        _ = label
      end
    end
  end

  describe "evaluate/2 — happy" do
    test "a matching eq predicate passes" do
      gate = Factory.gate()
      ctx = eval_ctx(%{document_completeness: :complete})
      assert {:pass, _cause} = Gate.evaluate(gate, ctx)
    end

    test "a non-matching eq predicate against a KNOWN (non-sentinel) value fails" do
      gate = Factory.gate()
      ctx = eval_ctx(%{document_completeness: :incomplete})
      assert {:fail, cause} = Gate.evaluate(gate, ctx)
      assert cause =~ "document_completeness"
    end

    test "an :any combinator passes if at least one predicate passes" do
      attrs =
        Factory.gate_attrs(%{
          rule: %{
            "combinator" => "any",
            "predicates" => [
              %{"field" => "assessment.sla_state", "op" => "eq", "value" => "breached"},
              %{"field" => "assessment.sla_state", "op" => "eq", "value" => "on_track"}
            ]
          }
        })

      {:ok, gate} = Gate.new(attrs)
      ctx = eval_ctx(%{sla_state: :on_track})
      assert {:pass, _} = Gate.evaluate(gate, ctx)
    end

    test "contains matches a value in a list field" do
      attrs =
        Factory.gate_attrs(%{
          rule: %{
            "combinator" => "all",
            "predicates" => [%{"field" => "assessment.data_quality_flags", "op" => "contains", "value" => "missing_source_field"}]
          }
        })

      {:ok, gate} = Gate.new(attrs)
      ctx = eval_ctx(%{data_quality_flags: [:missing_source_field]})
      assert {:pass, _} = Gate.evaluate(gate, ctx)
    end
  end

  describe "evaluate/2 — boundary (the sentinel-value indeterminate rule)" do
    test "comparing document_completeness == complete when it's actually :unknown is indeterminate, not fail" do
      gate = Factory.gate()
      ctx = eval_ctx(%{document_completeness: :unknown})
      assert {:indeterminate, cause} = Gate.evaluate(gate, ctx)
      assert cause =~ "unknown_value"
    end

    test "explicitly checking eq :unknown against an :unknown value is a confident pass, not indeterminate" do
      attrs =
        Factory.gate_attrs(%{
          rule: %{
            "combinator" => "all",
            "predicates" => [%{"field" => "assessment.document_completeness", "op" => "eq", "value" => "unknown"}]
          }
        })

      {:ok, gate} = Gate.new(attrs)
      ctx = eval_ctx(%{document_completeness: :unknown})
      assert {:pass, _} = Gate.evaluate(gate, ctx)
    end

    test "an :all combinator with one fail and one indeterminate reports :fail (fail short-circuits over indeterminate)" do
      attrs =
        Factory.gate_attrs(%{
          rule: %{
            "combinator" => "all",
            "predicates" => [
              %{"field" => "assessment.document_completeness", "op" => "eq", "value" => "complete"},
              %{"field" => "assessment.sla_state", "op" => "eq", "value" => "on_track"}
            ]
          }
        })

      {:ok, gate} = Gate.new(attrs)
      ctx = eval_ctx(%{document_completeness: :incomplete, sla_state: :n_a})
      assert {:fail, _} = Gate.evaluate(gate, ctx)
    end

    test "referencing a field path the struct doesn't have is engine-level indeterminate" do
      attrs =
        Factory.gate_attrs(%{
          rule: %{
            "combinator" => "all",
            "predicates" => [%{"field" => "assessment.not_a_real_field", "op" => "present"}]
          }
        })

      {:ok, gate} = Gate.new(attrs)
      ctx = eval_ctx()
      assert {:indeterminate, cause} = Gate.evaluate(gate, ctx)
      assert cause =~ "unresolvable_field"
    end
  end

  describe "evaluate/2 — determinism (contract: same gate + same assessment -> same outcome)" do
    test "evaluating twice against identical input yields identical output" do
      gate = Factory.gate()
      ctx = eval_ctx(%{document_completeness: :complete})
      assert Gate.evaluate(gate, ctx) == Gate.evaluate(gate, ctx)
    end
  end

  describe "field resolution — contract (assessment.* and state.* only)" do
    test "a state.* field resolves against the real %LoanActor.State{}" do
      attrs =
        Factory.gate_attrs(%{
          rule: %{
            "combinator" => "all",
            "predicates" => [%{"field" => "state.status", "op" => "eq", "value" => "spawned"}]
          }
        })

      {:ok, gate} = Gate.new(attrs)
      ctx = eval_ctx(%{}, %{status: :spawned})
      assert {:pass, _} = Gate.evaluate(gate, ctx)
    end
  end
end
