defmodule LoanActor.Skill.GatePackLoaderTest do
  @moduledoc """
  ADH-005 — `LoanActor.Skill.Loader`'s gate-pack extension
  (`contracts/gate-pack-format.md`): `gate_id`/`rule` recognition,
  load-time rejection, `resolve_gate/2`'s highest-version tie-break, and
  `match/2`'s `assessment:`-enriched `loan_context`.

  Taxonomy: happy / boundary / error / contract. Extends `loader_test.exs`
  rather than duplicating its fixture-directory setup (per
  `gate-pack-format.md`'s own test-pin wording).
  """

  use ExUnit.Case, async: false

  alias LoanActor.Factory
  alias LoanActor.Gate
  alias LoanActor.Skill
  alias LoanActor.Skill.Loader

  setup do
    previous = Application.get_env(:loan_actor, :skills_dir)
    Application.delete_env(:loan_actor, :skills_dir)

    on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:loan_actor, :skills_dir)
        dir -> Application.put_env(:loan_actor, :skills_dir, dir)
      end
    end)

    :ok
  end

  defp gate_pack_overrides(extra \\ %{}) do
    Map.merge(
      %{
        id: "0002-demo-gate-pack",
        name: "document-completeness-gate",
        description: "When assessing document completeness for an income goal, check the required documents are complete and current.",
        tools_required: ["evaluate_gate"],
        gate_id: "document-completeness",
        rule: %{
          "combinator" => "all",
          "predicates" => [
            %{"field" => "assessment.document_completeness", "op" => "eq", "value" => "complete"}
          ]
        }
      },
      extra
    )
  end

  describe "load_pack/1 — happy (valid gate pack)" do
    test "a valid gate pack loads with a validated %Gate{} attached" do
      dir = Factory.unique_tmp_dir("loan_actor_gate_pack_valid")
      File.mkdir_p!(dir)
      Factory.write_skill_pack!(dir, gate_pack_overrides())

      assert {:ok, %Skill{gate: %Gate{} = gate}} =
               Loader.load_pack(Path.join(dir, "0002-demo-gate-pack"))

      assert gate.gate_id == "document-completeness"
      assert gate.version == "1.0.0"
      assert gate.pack_id == "0002-demo-gate-pack"
      assert gate.combinator == :all
    end

    test "an ordinary (non-gate) pack's gate field stays nil" do
      assert {:ok, %Skill{gate: nil}} =
               Loader.load_pack(Path.join([__DIR__, "..", "fixtures", "skills", "0001-valid-pack"]))
    end
  end

  describe "load_pack/1 — error (contract: gate_id/rule required + hard-capped grammar)" do
    test "a gate pack missing gate_id is rejected" do
      dir = Factory.unique_tmp_dir("loan_actor_gate_pack_no_id")
      File.mkdir_p!(dir)
      Factory.write_skill_pack!(dir, gate_pack_overrides(%{gate_id: nil}))

      assert {:error, {:invalid_gate, {:missing_or_invalid, :gate_id}}} =
               Loader.load_pack(Path.join(dir, "0002-demo-gate-pack"))
    end

    test "a gate pack missing rule is rejected" do
      dir = Factory.unique_tmp_dir("loan_actor_gate_pack_no_rule")
      File.mkdir_p!(dir)
      Factory.write_skill_pack!(dir, gate_pack_overrides(%{rule: nil}))

      assert {:error, {:invalid_gate, {:missing_or_invalid, :rule}}} =
               Loader.load_pack(Path.join(dir, "0002-demo-gate-pack"))
    end

    test "a gate pack whose rule violates the hard-capped grammar is rejected" do
      dir = Factory.unique_tmp_dir("loan_actor_gate_pack_bad_rule")
      File.mkdir_p!(dir)

      Factory.write_skill_pack!(
        dir,
        gate_pack_overrides(%{
          rule: %{"combinator" => "xor", "predicates" => []}
        })
      )

      assert {:error, {:invalid_gate, {:invalid_combinator, "xor"}}} =
               Loader.load_pack(Path.join(dir, "0002-demo-gate-pack"))
    end

    test "an ordinary pack (evaluate_gate not required) never validates gate fields at all" do
      dir = Factory.unique_tmp_dir("loan_actor_gate_pack_ordinary")
      File.mkdir_p!(dir)
      Factory.write_skill_pack!(dir, %{id: "0099-ordinary", tools_required: ["verify_diary_chain"]})

      assert {:ok, %Skill{gate: nil}} = Loader.load_pack(Path.join(dir, "0099-ordinary"))
    end
  end

  describe "resolve_gate/2 — boundary (contract: additive-only, highest version wins)" do
    test "among multiple packs sharing a gate_id, the highest version is current" do
      dir = Factory.unique_tmp_dir("loan_actor_gate_pack_versions")
      File.mkdir_p!(dir)

      Factory.write_skill_pack!(
        dir,
        gate_pack_overrides(%{id: "0002-demo-gate-pack-v1", version: "1.0.0"})
      )

      Factory.write_skill_pack!(
        dir,
        gate_pack_overrides(%{
          id: "0002-demo-gate-pack-v2",
          version: "2.0.0",
          rule: %{
            "combinator" => "any",
            "predicates" => [
              %{"field" => "assessment.sla_state", "op" => "eq", "value" => "on_track"}
            ]
          }
        })
      )

      {:ok, skills} = Loader.load_all(dir: dir)

      assert %Gate{version: "2.0.0", combinator: :any} =
               Loader.resolve_gate("document-completeness", skills)
    end

    test "an unknown gate_id resolves to nil" do
      assert Loader.resolve_gate("not-a-real-gate", []) == nil
    end
  end

  describe "match/2 — happy (contract: loan_context gains an assessment: key)" do
    test "a gate pack triggers when the assessment (not just status/goals) overlaps its description" do
      dir = Factory.unique_tmp_dir("loan_actor_gate_pack_match")
      File.mkdir_p!(dir)
      Factory.write_skill_pack!(dir, gate_pack_overrides())
      {:ok, skills} = Loader.load_all(dir: dir)

      loan_context = %{
        status: :processing,
        event_type: nil,
        goal_descriptions: [],
        assessment: Factory.assessment(%{document_completeness: :complete})
      }

      assert Enum.any?(Loader.match(loan_context, skills), &(&1.id == "0002-demo-gate-pack"))
    end

    test "omitting the assessment key entirely still works (backward-compatible input)" do
      dir = Factory.unique_tmp_dir("loan_actor_gate_pack_match_no_assessment")
      File.mkdir_p!(dir)
      Factory.write_skill_pack!(dir, gate_pack_overrides())
      {:ok, skills} = Loader.load_all(dir: dir)

      loan_context = %{status: :processing, event_type: nil, goal_descriptions: []}
      assert Loader.match(loan_context, skills) == []
    end
  end
end
