defmodule LoanActor.FactoryTest do
  @moduledoc """
  Tests for the test-data factory itself (test-data-forge discipline: the
  factory is code, so it is tested — determinism, validity, and the negative
  catalog all get proven here). FT-006.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias LoanActor.Diary.Chain
  alias LoanActor.Diary.Entry
  alias LoanActor.Factory
  alias LoanActor.Skill
  alias LoanActor.Skill.Loader

  describe "determinism" do
    test "entry/1 is byte-identical across calls" do
      assert Factory.entry() == Factory.entry()
      assert Factory.entry(%{loan_id: "L-X", sequence: 0}) == Factory.entry(%{loan_id: "L-X"})
    end

    test "chain/2 is deterministic for a fixed loan_id" do
      assert Factory.chain(10, %{loan_id: "L-DET"}) == Factory.chain(10, %{loan_id: "L-DET"})
    end

    test "payload_hash/2 is a pure function of loan_id and sequence" do
      assert Factory.payload_hash("L-A", 1) == Factory.payload_hash("L-A", 1)
      refute Factory.payload_hash("L-A", 1) == Factory.payload_hash("L-A", 2)
      refute Factory.payload_hash("L-A", 1) == Factory.payload_hash("L-B", 1)
    end
  end

  describe "validity — happy" do
    test "entry/1 builds a validated genesis entry" do
      entry = Factory.entry()
      assert %Entry{sequence: 0} = entry
      assert entry.prev_hash == Entry.genesis_prev_hash()
    end

    test "chain/2 output always passes Chain.verify/1" do
      for n <- [1, 2, 5, 50] do
        assert :ok = Chain.verify(Factory.chain(n, %{loan_id: "L-V#{n}"}))
      end
    end

    test "next_entry/2 links to the given tail and inherits its loan_id" do
      [tail] = Factory.chain(1, %{loan_id: "L-NEXT"})
      next = Factory.next_entry(tail, %{type: :document_uploaded})

      assert next.loan_id == "L-NEXT"
      assert next.sequence == 1
      assert next.type == :document_uploaded
      assert :ok = Chain.verify_pair(tail, next)
    end

    test "unique_loan_id/0 never repeats" do
      ids = for _ <- 1..1000, do: Factory.unique_loan_id()
      assert length(Enum.uniq(ids)) == 1000
    end
  end

  describe "invalid variants catalog" do
    test "covers every field of the Entry schema at least once" do
      covered =
        Factory.invalid_entry_variants()
        |> Enum.map(fn {label, _} -> label |> Atom.to_string() |> String.split("_") |> hd() end)
        |> MapSet.new()

      for field <- ~w(loan sequence timestamp type actor payload prev) do
        assert field in covered, "no invalid variant exercises field family #{field}"
      end
    end

    test "every variant is rejected by Entry.new/1" do
      for {label, attrs} <- Factory.invalid_entry_variants() do
        assert_raise ArgumentError, fn -> Entry.new(attrs) end
        _ = label
      end
    end
  end

  describe "generators (property)" do
    property "chain_gen/1 only generates chains that verify" do
      check all(entries <- Factory.chain_gen(12), max_runs: 50) do
        assert :ok = Chain.verify(entries)
        assert length(entries) in 1..12
        assert [%Entry{sequence: 0} | _] = entries
      end
    end
  end

  describe "skill/1 — happy (FT-037)" do
    test "builds a %Skill{} with the documented defaults" do
      skill = Factory.skill()

      assert %Skill{id: "0099-factory-skill", name: "factory-skill"} = skill
      assert skill.tools_required == ["verify_diary_chain"]
      assert skill.files == []
    end

    test "every field is overridable" do
      skill = Factory.skill(%{id: "0042-custom", name: "custom", tools_required: ["set_goal"]})

      assert skill.id == "0042-custom"
      assert skill.name == "custom"
      assert skill.tools_required == ["set_goal"]
    end
  end

  describe "write_skill_pack!/2 — happy + error (FT-037)" do
    test "writes a pack that LoanActor.Skill.Loader accepts, matching skill_attrs/1's defaults" do
      dir = Factory.unique_tmp_dir("loan_actor_factory_skill_pack")

      assert ^dir = Factory.write_skill_pack!(dir)

      assert {:ok, %Skill{} = loaded} = Loader.load_pack(Path.join(dir, "0099-factory-skill"))
      assert loaded.name == "factory-skill"
      assert loaded.version == "1.0.0"
      assert loaded.tools_required == ["verify_diary_chain"]
      assert String.contains?(loaded.body, "Body.")
    end

    test "overrides feed straight into the written front-matter" do
      dir = Factory.unique_tmp_dir("loan_actor_factory_skill_pack_override")
      pack_id = "0007-override-pack"

      Factory.write_skill_pack!(dir, %{
        id: pack_id,
        name: "override-pack",
        description: "During plan review, ask the operator to approve or reject.",
        tools_required: ["request_operator_approval"]
      })

      assert {:ok, %Skill{name: "override-pack", tools_required: ["request_operator_approval"]}} =
               Loader.load_pack(Path.join(dir, pack_id))
    end

    test "a pack naming an unresolvable tool is rejected by the real loader (error)" do
      dir = Factory.unique_tmp_dir("loan_actor_factory_skill_pack_bad_tool")
      pack_id = "0008-bad-tool"

      Factory.write_skill_pack!(dir, %{id: pack_id, tools_required: ["not_a_real_tool"]})

      assert {:error, {:unresolvable_tools, ["not_a_real_tool"]}} =
               Loader.load_pack(Path.join(dir, pack_id))
    end
  end

  describe "tool_invocation_diary_pair/2 — happy + boundary (FT-037)" do
    test "continuing from a real tail produces a chain-linked :tool_invoked/:tool_completed pair" do
      [tail] = Factory.chain(1, %{loan_id: "L-TOOLPAIR"})
      {invoked, completed} = Factory.tool_invocation_diary_pair(tail)

      assert invoked.type == :tool_invoked
      assert completed.type == :tool_completed
      assert :ok = Chain.verify_pair(tail, invoked)
      assert :ok = Chain.verify_pair(invoked, completed)
    end

    test "outcome: :failed produces a :tool_failed second entry" do
      [tail] = Factory.chain(1, %{loan_id: "L-TOOLPAIR-FAIL"})
      {_invoked, completed} = Factory.tool_invocation_diary_pair(tail, %{outcome: :failed})

      assert completed.type == :tool_failed
    end

    test "a nil tail anchors the pair as the diary's own first two entries (boundary)" do
      {invoked, completed} = Factory.tool_invocation_diary_pair(nil, %{loan_id: "L-TOOLPAIR-GENESIS", tool_name: "set_goal"})

      assert invoked.sequence == 0
      assert invoked.type == :tool_invoked
      assert completed.sequence == 1
      assert :ok = Chain.verify_pair(invoked, completed)
    end
  end
end
