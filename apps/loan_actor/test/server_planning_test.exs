defmodule LoanActor.ServerPlanningTest do
  @moduledoc """
  FT-019 — `LoanActor.Server` planning loop (`:plan` self-message).
  Taxonomy: happy / race.

  Verifies SC-012 (rewritten by 0004): a `:goal_set` reactive transition
  triggers a `:plan` self-message; the planning loop trigger-matches
  skills and invokes `request_document`, producing the diary pair
  (`:tool_invoked`/`:tool_completed`). No live AG-UI stream exists yet
  (FT-024) — that part of SC-012 is proven once it does.
  """

  use ExUnit.Case, async: false

  alias LoanActor.Diary.File, as: FileStore
  alias LoanActor.Diary.Mnesia, as: MnesiaStore
  alias LoanActor.Factory
  alias LoanActor.FileTestSupport
  alias LoanActor.MnesiaTestSupport
  alias LoanActor.Server
  alias LoanActor.ServerTestSupport
  alias LoanActor.State.Model

  @dir FileTestSupport.dir()

  setup_all do
    :ok = FileStore.init(dir: @dir)
    :ok = MnesiaStore.init(dir: MnesiaTestSupport.dir())
    :ok
  end

  setup do
    previous_skills_dir = Application.get_env(:loan_actor, :skills_dir)
    on_exit(fn -> restore(:skills_dir, previous_skills_dir) end)
    :ok
  end

  defp restore(key, nil), do: Application.delete_env(:loan_actor, key)
  defp restore(key, value), do: Application.put_env(:loan_actor, key, value)

  defp entries(loan_id), do: Enum.to_list(FileStore.stream(loan_id, []))
  defp entries_of_type(loan_id, type), do: Enum.filter(entries(loan_id), &(&1.type == type))

  defp eventually(fun, attempts \\ 100) do
    Enum.reduce_while(1..attempts, nil, fn _, _ ->
      case fun.() do
        nil ->
          Process.sleep(10)
          {:cont, nil}

        value ->
          {:halt, value}
      end
    end)
  end

  defp wait_for_entry(loan_id, type) do
    eventually(fn ->
      case entries_of_type(loan_id, type) do
        [] -> nil
        found -> found
      end
    end)
  end

  describe "planning loop — happy (SC-012, diary side)" do
    test "a :goal_set event triggers :plan, which matches the demo pack and runs a clean tool pair" do
      # Honest scope note: diary entries carry only a HASH of a tool's
      # name+args (Principle VIII), and there is no live AG-UI stream yet
      # (FT-024) to observe a ToolCallResult naming "request_document" in
      # the clear — so this test cannot distinguish, from OUTSIDE the
      # Server, "the planning loop's request_document ran" from "the
      # periodic loop's own unconditional verify_diary_chain ran". What
      # IS precisely provable here: (a) maybe_trigger_planning/1 sends
      # :plan only for :goal_set (direct unit test above), (b) the real
      # demo pack's trigger matches this loan's status (:skill_activated
      # present — a signal unconditional verify_diary_chain never
      # produces), (c) whatever ran completed cleanly. Together these are
      # the strongest claim available without inventing stream
      # infrastructure ahead of FT-024/025.
      Application.delete_env(:loan_actor, :skills_dir)

      loan_id = Factory.unique_loan_id()
      {:ok, _pid} = ServerTestSupport.spawn_and_track(loan_id)

      {:ok, 1} = LoanActor.send_event(loan_id, Factory.event(%{type: :goal_set}))

      # The reactive transition's own entry lands synchronously; the
      # planning-loop tool pair arrives asynchronously via :plan.
      wait_for_entry(loan_id, :tool_invoked)
      wait_for_entry(loan_id, :tool_completed)
      wait_for_entry(loan_id, :skill_activated)

      assert entries_of_type(loan_id, :tool_invoked) != []
      assert entries_of_type(loan_id, :tool_completed) != []
      assert entries_of_type(loan_id, :tool_failed) == []
      assert entries_of_type(loan_id, :skill_activated) != []

      {:ok, state} = LoanActor.state(loan_id)
      assert state.status == :awaiting_documents
    end

    test "maybe_trigger_planning/1 only sends :plan for :goal_set (direct unit test)" do
      # Integration-level (diary-count) verification of "does NOT trigger
      # planning" is confounded by the periodic loop's own independent
      # verify_diary_chain invocations (same reasoning as infer_doc_type/1
      # above: the diary can't distinguish which tool a :tool_invoked
      # entry is for). Testing the pure decision directly instead.
      for event_type <- Model.event_types() -- [:goal_set] do
        assert :ok = Server.maybe_trigger_planning(event_type)
        refute_received :plan, "expected no :plan message for event_type #{event_type}"
      end

      assert :ok = Server.maybe_trigger_planning(:goal_set)
      assert_received :plan
    end

    test "an empty skills dir means no skill matches, so no request_document invocation" do
      # NOTE: :tool_invoked entries can't be asserted absent outright here
      # — the periodic loop's own unconditional verify_diary_chain check
      # (FT-018) produces one regardless of skills. :skill_activated is
      # the precise, skill-matching-specific signal instead: with nothing
      # loadable, nothing can match.
      Application.put_env(:loan_actor, :skills_dir, empty_skills_dir())

      loan_id = Factory.unique_loan_id()
      {:ok, _pid} = ServerTestSupport.spawn_and_track(loan_id)

      {:ok, 1} = LoanActor.send_event(loan_id, Factory.event(%{type: :goal_set}))
      Process.sleep(100)

      {:ok, state} = LoanActor.state(loan_id)
      assert state.status == :awaiting_documents
      assert entries_of_type(loan_id, :skill_activated) == []
    end
  end

  describe "infer_doc_type/1 — happy + boundary (direct unit test)" do
    # Diary entries only ever carry a HASH of tool args (constitution
    # Principle VIII, tool-behaviour.md invariant 4), so which doc_type
    # was chosen cannot be recovered by observing the diary from outside
    # — this pure function is tested directly instead.

    test "an open goal mentioning \"identity\" selects identity" do
      goals = [Factory.goal(%{description: "need identity verification", status: :open})]
      assert Server.infer_doc_type(goals) == "identity"
    end

    test "an open goal mentioning \"appraisal\" selects appraisal" do
      goals = [Factory.goal(%{description: "need an appraisal document", status: :open})]
      assert Server.infer_doc_type(goals) == "appraisal"
    end

    test "case-insensitive keyword match" do
      goals = [Factory.goal(%{description: "Need INCOME verification", status: :open})]
      assert Server.infer_doc_type(goals) == "income"
    end

    test "the first matching goal wins when multiple goals are present" do
      goals = [
        Factory.goal(%{description: "generic goal", status: :open}),
        Factory.goal(%{description: "need identity doc", status: :open}),
        Factory.goal(%{description: "need appraisal doc", status: :open})
      ]

      assert Server.infer_doc_type(goals) == "identity"
    end

    test "satisfied/abandoned goals are ignored, even if they mention a keyword" do
      goals = [Factory.goal(%{description: "need appraisal", status: :satisfied})]
      assert Server.infer_doc_type(goals) == "income"
    end

    test "no goals at all defaults to income (boundary: empty list)" do
      assert Server.infer_doc_type([]) == "income"
    end

    test "an open goal with no matching keyword defaults to income" do
      goals = [Factory.goal(%{description: "generic goal, no keyword here", status: :open})]
      assert Server.infer_doc_type(goals) == "income"
    end
  end

  describe "planning vs reactive — race" do
    test "a concurrent reactive event does not corrupt state while :plan is being processed" do
      Application.delete_env(:loan_actor, :skills_dir)

      loan_id = Factory.unique_loan_id()
      {:ok, _pid} = ServerTestSupport.spawn_and_track(loan_id)

      # goal_set (queues :plan) racing against document_uploaded, fired
      # concurrently from a separate process — the Server's single mailbox
      # serializes both regardless of arrival order; this proves no crash,
      # no lost update, and a legal final state either way.
      task =
        Task.async(fn ->
          LoanActor.send_event(loan_id, Factory.event(%{type: :goal_set}))
        end)

      # A tiny stagger lets the :plan self-message plausibly land mid-flight
      # relative to this second call, without making the test depend on
      # exact timing for correctness (only for which interleaving occurs).
      Process.sleep(5)

      result =
        LoanActor.send_event(loan_id, Factory.event(%{type: :document_uploaded}))

      goal_set_result = Task.await(task)

      # Both calls must resolve to a legal outcome (ok or a documented
      # illegal-transition error) — never a crash, never a duplicate.
      assert match?({:ok, _}, goal_set_result) or match?({:error, {:illegal_transition, _, _}}, goal_set_result)
      assert match?({:ok, _}, result) or match?({:error, {:illegal_transition, _, _}}, result)

      {:ok, state} = LoanActor.state(loan_id)
      assert state.status in [:spawned, :awaiting_documents, :documents_under_review]
    end
  end

  defp empty_skills_dir do
    dir = Factory.unique_tmp_dir("loan_actor_planning_empty_skills")
    File.mkdir_p!(dir)
    dir
  end
end
