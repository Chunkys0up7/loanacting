defmodule LoanActor.Skill.LoaderTest do
  @moduledoc """
  FT-044 — `LoanActor.Skill.Loader`. Taxonomy: happy / boundary / error / contract.

  Fixture packs live under `test/fixtures/skills/` (test-data-forge):
  valid, bad front-matter (missing required key), unresolvable
  `tools_required`, multi-file. `async: false` — mutates the global
  `:skills_dir` Application env (mirrors `Diary.File`/`Diary.Mnesia`'s
  dir-remembering pattern).
  """

  use ExUnit.Case, async: false

  alias LoanActor.Skill
  alias LoanActor.Skill.Loader

  @fixtures_dir Path.join([__DIR__, "..", "fixtures", "skills"])

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

  describe "load_pack/1 — happy" do
    test "a valid pack loads with all documented fields populated" do
      assert {:ok, %Skill{} = skill} =
               Loader.load_pack(Path.join(@fixtures_dir, "0001-valid-pack"))

      assert skill.id == "0001-valid-pack"
      assert skill.name == "valid-pack"
      assert skill.version == "1.0.0"
      assert skill.description == "A minimal valid pack for testing the loader."
      assert skill.tools_required == ["request_document"]
      assert String.contains?(skill.body, "Body content")
      assert skill.files == []
    end

    test "a multi-file pack's reference files are all listed" do
      assert {:ok, %Skill{} = skill} =
               Loader.load_pack(Path.join(@fixtures_dir, "0004-multi-file"))

      assert skill.tools_required == []
      basenames = Enum.map(skill.files, &Path.basename/1)
      assert "a.md" in basenames
      assert "b.md" in basenames
      assert length(skill.files) == 2
    end
  end

  describe "load_pack/1 — error" do
    test "a pack missing a required key is rejected with the missing key named" do
      assert {:error, {:missing_keys, ["version"]}} =
               Loader.load_pack(Path.join(@fixtures_dir, "0002-bad-front-matter"))
    end

    test "a pack whose tools_required names an absent tool is rejected" do
      assert {:error, {:unresolvable_tools, ["not_a_real_tool"]}} =
               Loader.load_pack(Path.join(@fixtures_dir, "0003-unresolvable-tools"))
    end

    test "a directory with no SKILL.md is rejected" do
      assert {:error, :missing_skill_md} = Loader.load_pack(@fixtures_dir)
    end
  end

  describe "load_all/1 — happy + boundary (rejected packs never trigger)" do
    test "only valid packs are returned; invalid ones are silently skipped" do
      assert {:ok, skills} = Loader.load_all(dir: @fixtures_dir)
      ids = Enum.map(skills, & &1.id)

      assert "0001-valid-pack" in ids
      assert "0004-multi-file" in ids
      refute "0002-bad-front-matter" in ids
      refute "0003-unresolvable-tools" in ids
      assert length(skills) == 2
    end

    test "an empty directory yields zero skills" do
      empty_dir = Path.join(System.tmp_dir!(), "loan_actor_skills_empty_#{System.unique_integer([:positive])}")
      File.mkdir_p!(empty_dir)
      assert {:ok, []} = Loader.load_all(dir: empty_dir)
    end
  end

  describe "reload/0 — happy (analysis Gap-1 inherited: picks up an added pack)" do
    test "adding a pack after the first load_all is visible on the next call" do
      tmp_dir = Path.join(System.tmp_dir!(), "loan_actor_skills_reload_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp_dir)

      assert {:ok, []} = Loader.load_all(dir: tmp_dir)

      pack_dir = Path.join(tmp_dir, "0001-added-later")
      File.mkdir_p!(pack_dir)

      File.write!(Path.join(pack_dir, "SKILL.md"), """
      ---
      name: added-later
      version: 1.0.0
      description: Added after the first load_all call.
      tools_required: []
      ---

      Body.
      """)

      assert {:ok, [%Skill{name: "added-later"}]} = Loader.reload()
    end
  end

  describe "match/2 — contract (trigger matching)" do
    test "a non-matching loan_context activates nothing" do
      {:ok, skills} = Loader.load_all(dir: @fixtures_dir)

      loan_context = %{status: :processing, event_type: :complete, goal_descriptions: ["unrelated"]}
      assert Loader.match(loan_context, skills) == []
    end

    test "the real demo pack triggers on a loan awaiting documents with an open document goal" do
      {:ok, real_skills} = Loader.load_all([])
      assert Enum.any?(real_skills, &(&1.id == "0001-demo-document-request"))

      loan_context = %{
        status: :awaiting_documents,
        event_type: :goal_set,
        goal_descriptions: ["obtain income documentation"]
      }

      matched = Loader.match(loan_context, real_skills)
      assert Enum.any?(matched, &(&1.id == "0001-demo-document-request"))
    end

    test "the real demo pack does NOT trigger on an unrelated loan state" do
      {:ok, real_skills} = Loader.load_all([])

      loan_context = %{status: :completed, event_type: :complete, goal_descriptions: []}
      matched = Loader.match(loan_context, real_skills)
      refute Enum.any?(matched, &(&1.id == "0001-demo-document-request"))
    end
  end
end
