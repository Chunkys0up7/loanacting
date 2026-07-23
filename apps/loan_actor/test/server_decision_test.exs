defmodule LoanActor.ServerDecisionTest do
  @moduledoc """
  ADH-007 — `LoanActor.Server`'s gate-outcome application (FR-003).
  Taxonomy: happy / boundary / error / replay.

  Gate packs here check `state.status` directly (not
  `assessment.document_completeness`) — ADH-008's diary-derived
  `state.context` facts don't exist yet, and `state.status` is a real,
  already-driveable field per `contracts/gate-behaviour.md`'s own
  documented `state.*` field-resolution path (mirrors `gate_test.exs`'s
  own "field resolution" test).

  **Error taxonomy note**: `evaluate_gate`'s own `{:error,
  {:gate_not_resolved, gate_id}}` path is unit-tested directly in
  `evaluate_gate_test.exs`, and `Server.pin_gate/2`'s "unknown gate_id
  resolves to nil" boundary case is covered in
  `server_gate_pinning_test.exs`. There is no way to trigger that error
  path through a REAL loop here: `run_skill_gate/2` is only ever called
  with a `gate_id` the loader just proved resolves (`skill.gate.gate_id`,
  from the very match that selected this skill) — reaching the error path
  live would need a pack deleted mid-heartbeat-pass, a race this suite
  has no hook to inject deterministically. `run_skill_gate/2`'s own
  `_other -> gen_state` clause (no entry appended, no crash) is the only
  new code on this path, and it is trivial by inspection.
  """

  use ExUnit.Case, async: false

  alias LoanActor.Diary.File, as: FileStore
  alias LoanActor.Diary.Mnesia, as: MnesiaStore
  alias LoanActor.Factory
  alias LoanActor.FileTestSupport
  alias LoanActor.MnesiaTestSupport
  alias LoanActor.ServerTestSupport

  @dir FileTestSupport.dir()

  setup_all do
    :ok = FileStore.init(dir: @dir)
    :ok = MnesiaStore.init(dir: MnesiaTestSupport.dir())
    :ok
  end

  setup do
    previous_skills_dir = Application.get_env(:loan_actor, :skills_dir)
    on_exit(fn -> restore(previous_skills_dir) end)
    :ok
  end

  defp restore(nil), do: Application.delete_env(:loan_actor, :skills_dir)
  defp restore(dir), do: Application.put_env(:loan_actor, :skills_dir, dir)

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

  defp write_gate_pack(dir, expected_status) do
    Factory.write_skill_pack!(dir, %{
      id: "0099-status-gate",
      name: "status-gate",
      description: "awaiting documents loan needs a gate check.",
      tools_required: ["evaluate_gate"],
      gate_id: "status-gate",
      version: "1.0.0",
      rule: %{
        "combinator" => "all",
        "predicates" => [
          %{"field" => "state.status", "op" => "eq", "value" => Atom.to_string(expected_status)}
        ]
      }
    })
  end

  # A gate check alone never creates a goal to satisfy (the reactive
  # :goal_set EVENT only transitions state.status — real state.goals
  # content comes from the periodic loop's OWN set_goal TOOL dispatch,
  # per server_heartbeat_test.exs's own established "skill-triggered
  # set_goal" pattern). This companion pack supplies that goal.
  defp write_set_goal_pack(dir) do
    Factory.write_skill_pack!(dir, %{
      id: "0001-set-goal-demo",
      name: "set-goal-demo",
      description: "awaiting documents loan needs an income document goal set automatically.",
      tools_required: ["set_goal"]
    })
  end

  describe "gate outcome — happy (pass drives a real goal change)" do
    test "a :pass outcome satisfies every currently open goal and logs :decision" do
      dir = Factory.unique_tmp_dir("loan_actor_decision_pass")
      File.mkdir_p!(dir)
      write_gate_pack(dir, :awaiting_documents)
      write_set_goal_pack(dir)
      Application.put_env(:loan_actor, :skills_dir, dir)

      loan_id = Factory.unique_loan_id()
      {:ok, _pid} = ServerTestSupport.spawn_and_track(loan_id)

      {:ok, _seq} = LoanActor.send_event(loan_id, Factory.event(%{type: :goal_set}))

      eventually(fn ->
        case LoanActor.state(loan_id) do
          {:ok, %{goals: [_ | _]}} = ok -> ok
          _ -> nil
        end
      end)

      [satisfied | _] =
        eventually(fn ->
          case entries_of_type(loan_id, :goal_satisfied) do
            [] -> nil
            found -> found
          end
        end)

      assert satisfied.actor == "system"

      {:ok, state} = LoanActor.state(loan_id)
      assert Enum.all?(state.goals, &(&1.status == :satisfied))

      decisions = entries_of_type(loan_id, :decision)
      assert decisions != []

      gate_evaluated = entries_of_type(loan_id, :gate_evaluated)
      assert gate_evaluated != []
    end
  end

  describe "gate outcome — happy (fail applies no effect)" do
    test "a :fail outcome logs :decision + :gate_evaluated but never :goal_satisfied" do
      dir = Factory.unique_tmp_dir("loan_actor_decision_fail")
      File.mkdir_p!(dir)
      # Checks for :processing while the loan is actually :awaiting_documents.
      write_gate_pack(dir, :processing)
      Application.put_env(:loan_actor, :skills_dir, dir)

      loan_id = Factory.unique_loan_id()
      {:ok, _pid} = ServerTestSupport.spawn_and_track(loan_id)

      {:ok, _seq} = LoanActor.send_event(loan_id, Factory.event(%{type: :goal_set}))

      eventually(fn ->
        case entries_of_type(loan_id, :decision) do
          [] -> nil
          found -> found
        end
      end)

      {:ok, state} = LoanActor.state(loan_id)
      assert Enum.all?(state.goals, &(&1.status == :open))
      assert entries_of_type(loan_id, :goal_satisfied) == []
      assert entries_of_type(loan_id, :gate_evaluated) != []
    end
  end

  describe "gate outcome — boundary (no matching gate pack)" do
    test "a loan whose context matches no gate pack logs zero :gate_evaluated entries" do
      empty_dir = Factory.unique_tmp_dir("loan_actor_decision_empty")
      File.mkdir_p!(empty_dir)
      Application.put_env(:loan_actor, :skills_dir, empty_dir)

      loan_id = Factory.unique_loan_id()
      {:ok, _pid} = ServerTestSupport.spawn_and_track(loan_id)

      eventually(fn ->
        case entries_of_type(loan_id, :heartbeat) do
          [] -> nil
          found -> found
        end
      end)

      Process.sleep(50)
      assert entries_of_type(loan_id, :gate_evaluated) == []
    end
  end

  describe "gate outcome — replay (crash-recovery survives new diary entry types)" do
    test "a loan with :gate_evaluated/:decision/:goal_satisfied entries restarts cleanly after a crash" do
      dir = Factory.unique_tmp_dir("loan_actor_decision_replay")
      File.mkdir_p!(dir)
      write_gate_pack(dir, :awaiting_documents)
      write_set_goal_pack(dir)
      Application.put_env(:loan_actor, :skills_dir, dir)

      loan_id = Factory.unique_loan_id()
      {:ok, pid} = ServerTestSupport.spawn_and_track(loan_id)

      {:ok, _seq} = LoanActor.send_event(loan_id, Factory.event(%{type: :goal_set}))

      eventually(fn ->
        case entries_of_type(loan_id, :goal_satisfied) do
          [] -> nil
          found -> found
        end
      end)

      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 2_000

      new_pid =
        eventually(fn ->
          case LoanActor.whereis(loan_id) do
            nil -> nil
            ^pid -> nil
            other -> other
          end
        end)

      assert is_pid(new_pid), "actor never restarted — crash-looped on rehydrate"
      assert {:ok, %{status: :awaiting_documents}} = LoanActor.state(loan_id)
    end
  end
end
