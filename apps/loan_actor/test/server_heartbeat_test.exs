defmodule LoanActor.ServerHeartbeatTest do
  @moduledoc """
  FT-018 — `LoanActor.Server` periodic loop (heartbeat).
  Taxonomy: happy / boundary / replay.

  Verifies SC-011 cadence, scaled to `config/test.exs`'s `heartbeat_ms: 100`
  (SC-011 itself: 1s interval, 10s window, 9..11 entries — the same ratio
  applied here at 100ms/~1s/9..11 for a fast test run).

  The cadence assertion genuinely needs real wall-clock time to pass (it is
  a timing property, not a logical state transition) — `Process.sleep`
  there is the thing under test, not a synchronization crutch; everywhere
  else uses a bounded poll helper.
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

  describe "heartbeat cadence — happy (SC-011, scaled)" do
    test "over ~2.5 seconds at a 100ms interval, 22..28 :heartbeat diary entries are observed" do
      # A 1-second/10-tick window (SC-011's own ratio, scaled to test
      # config's 100ms interval) proved genuinely flaky under full-suite
      # scheduler contention: a single BEAM message-delivery delay is 10%
      # of a 10-tick sample, easily enough to land outside a tight 9..11
      # band. Observing 2.5x longer (~25 ticks) at the same ~10% tolerance
      # dampens any one-off jitter's relative weight without weakening
      # what's actually being proven (steady periodic cadence).
      loan_id = Factory.unique_loan_id()
      {:ok, _pid} = ServerTestSupport.spawn_and_track(loan_id)

      # Genuinely waiting for real time to pass — this IS the cadence
      # under test, not a synchronization guess.
      Process.sleep(2_550)

      count = length(entries_of_type(loan_id, :heartbeat))
      assert count >= 22 and count <= 28, "expected 22..28 heartbeats, got #{count}"
    end
  end

  describe "heartbeat — happy (state hash + last_heartbeat_at)" do
    test "each :heartbeat entry carries a state_hash and last_heartbeat_at advances" do
      loan_id = Factory.unique_loan_id()
      {:ok, _pid} = ServerTestSupport.spawn_and_track(loan_id)

      {:ok, state_before} = LoanActor.state(loan_id)
      assert state_before.last_heartbeat_at == nil

      [first | _] = wait_for_entry(loan_id, :heartbeat)
      # payload_hash is stored on the entry, not the raw payload — proves
      # the entry exists with the documented type; the hash content itself
      # is exercised structurally (Entry already validates it's 32 bytes).
      assert byte_size(first.payload_hash) == 32

      {:ok, state_after} = LoanActor.state(loan_id)
      assert %DateTime{} = state_after.last_heartbeat_at
    end
  end

  describe "heartbeat — happy (verify_diary_chain runs unconditionally)" do
    test "every heartbeat pass invokes verify_diary_chain and logs the real result" do
      loan_id = Factory.unique_loan_id()
      {:ok, _pid} = ServerTestSupport.spawn_and_track(loan_id)

      wait_for_entry(loan_id, :diary_chain_verified)

      [invoked | _] = wait_for_entry(loan_id, :tool_invoked)
      assert byte_size(invoked.payload_hash) == 32

      [verified | _] = entries_of_type(loan_id, :diary_chain_verified)
      assert verified.actor == "system"

      completed = entries_of_type(loan_id, :tool_completed)
      assert completed != []
    end
  end

  describe "heartbeat — boundary (no matching skill)" do
    test "a loan whose context matches no skill logs zero :skill_activated entries" do
      Application.put_env(:loan_actor, :skills_dir, empty_skills_dir())

      loan_id = Factory.unique_loan_id()
      {:ok, _pid} = ServerTestSupport.spawn_and_track(loan_id)

      wait_for_entry(loan_id, :heartbeat)
      Process.sleep(50)

      assert entries_of_type(loan_id, :skill_activated) == []
    end
  end

  describe "heartbeat — happy (real demo pack activates on a matching loan)" do
    test "a loan awaiting documents with an open document goal activates the demo pack" do
      Application.delete_env(:loan_actor, :skills_dir)

      loan_id = Factory.unique_loan_id()
      {:ok, _pid} = ServerTestSupport.spawn_and_track(loan_id)

      {:ok, 1} = LoanActor.send_event(loan_id, Factory.event(%{type: :goal_set}))

      [activated | _] = wait_for_entry(loan_id, :skill_activated)
      assert activated.actor == "system"
      assert byte_size(activated.payload_hash) == 32
    end
  end

  describe "heartbeat — happy (skill-triggered set_goal, custom fixture pack)" do
    test "a matched skill naming set_goal causes a new goal with the skill's description" do
      tmp_dir =
        Factory.write_skill_pack!(Factory.unique_tmp_dir("loan_actor_heartbeat_skill"), %{
          id: "0001-set-goal-demo",
          name: "set-goal-demo",
          description: "processing loan needs a periodic reminder goal set automatically.",
          tools_required: ["set_goal"]
        })

      Application.put_env(:loan_actor, :skills_dir, tmp_dir)

      loan_id = Factory.unique_loan_id()
      {:ok, _pid} = ServerTestSupport.spawn_and_track(loan_id)

      # Drive the loan to :processing so the fixture's trigger (which
      # mentions "processing") keyword-overlaps the loan context.
      # NOTE: sequence numbers are NOT asserted literally — FT-019 made
      # :goal_set queue a :plan self-message, which (per the Server's
      # single-mailbox FIFO ordering) is guaranteed to be processed before
      # this test's OWN next send_event call can possibly arrive, since
      # that call cannot even be issued until the first one returns. Its
      # tool_invoked/tool_completed pair lands at whatever sequence the
      # diary is at by then.
      {:ok, _seq1} = LoanActor.send_event(loan_id, Factory.event(%{type: :goal_set}))
      {:ok, _seq2} = LoanActor.send_event(loan_id, Factory.event(%{type: :document_uploaded}))
      {:ok, _seq3} = LoanActor.send_event(loan_id, Factory.event(%{type: :goal_satisfied}))

      # NOTE: the reactive :goal_set EVENT above already produces a diary
      # entry of type :goal_set (the diary type mirrors the event type) —
      # that is NOT the signal we want here. We're waiting specifically
      # for the periodic loop's set_goal TOOL to actually populate
      # state.goals, which only the heartbeat path does.
      eventually(fn ->
        case LoanActor.state(loan_id) do
          {:ok, %{goals: [_ | _]}} = ok -> ok
          _ -> nil
        end
      end)

      {:ok, state} = LoanActor.state(loan_id)

      assert Enum.any?(
               state.goals,
               &(&1.description == "processing loan needs a periodic reminder goal set automatically.")
             )

      assert entries_of_type(loan_id, :skill_activated) != []
      assert entries_of_type(loan_id, :goal_set) != []
    end
  end

  describe "heartbeat — replay (crash-recovery survives a non-spawned :goal_set diary entry)" do
    test "a loan whose set_goal tool fired at :processing restarts cleanly after a crash" do
      # Regression test for a real bug found auditing intent 0001's
      # closeout: rehydrate/2 used to replay any diary entry whose TYPE
      # was a member of Model.transition_driving_event_types/0, rather
      # than checking legality against the replay's OWN current
      # position. :goal_set is both a reactive event type (legal only
      # from :spawned) AND the diary type this test's own fixture skill's
      # set_goal tool logs at :processing (same scenario as the test
      # above) — feeding that second :goal_set entry back through
      # State.transition/2 during rehydrate always raised
      # IllegalTransitionError (no edge for :processing + :goal_set),
      # crash-looping the actor forever on every subsequent restart. Same
      # defect shape FT-034 already found and fixed for :heartbeat.
      tmp_dir =
        Factory.write_skill_pack!(Factory.unique_tmp_dir("loan_actor_heartbeat_replay_skill"), %{
          id: "0001-set-goal-demo",
          name: "set-goal-demo",
          description: "processing loan needs a periodic reminder goal set automatically.",
          tools_required: ["set_goal"]
        })

      Application.put_env(:loan_actor, :skills_dir, tmp_dir)

      loan_id = Factory.unique_loan_id()
      {:ok, pid} = ServerTestSupport.spawn_and_track(loan_id)

      {:ok, _seq1} = LoanActor.send_event(loan_id, Factory.event(%{type: :goal_set}))
      {:ok, _seq2} = LoanActor.send_event(loan_id, Factory.event(%{type: :document_uploaded}))
      {:ok, _seq3} = LoanActor.send_event(loan_id, Factory.event(%{type: :goal_satisfied}))

      eventually(fn ->
        case LoanActor.state(loan_id) do
          {:ok, %{goals: [_ | _], status: :processing}} = ok -> ok
          _ -> nil
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
      assert {:ok, %{status: :processing}} = LoanActor.state(loan_id)
    end
  end

  defp empty_skills_dir do
    dir = Factory.unique_tmp_dir("loan_actor_heartbeat_empty_skills")
    File.mkdir_p!(dir)
    dir
  end
end
