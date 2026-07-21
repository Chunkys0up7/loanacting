defmodule LoanActor.ServerHeartbeatTest do
  @moduledoc """
  FT-018 — `LoanActor.Server` periodic loop (heartbeat).
  Taxonomy: happy / boundary.

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
      tmp_dir = Factory.unique_tmp_dir("loan_actor_heartbeat_skill")
      pack_dir = Path.join(tmp_dir, "0001-set-goal-demo")
      File.mkdir_p!(pack_dir)

      File.write!(Path.join(pack_dir, "SKILL.md"), """
      ---
      name: set-goal-demo
      version: 1.0.0
      description: processing loan needs a periodic reminder goal set automatically.
      tools_required: [set_goal]
      ---

      Body.
      """)

      Application.put_env(:loan_actor, :skills_dir, tmp_dir)

      loan_id = Factory.unique_loan_id()
      {:ok, _pid} = ServerTestSupport.spawn_and_track(loan_id)

      # Drive the loan to :processing so the fixture's trigger (which
      # mentions "processing") keyword-overlaps the loan context.
      {:ok, 1} = LoanActor.send_event(loan_id, Factory.event(%{type: :goal_set}))
      {:ok, 2} = LoanActor.send_event(loan_id, Factory.event(%{type: :document_uploaded}))
      {:ok, 3} = LoanActor.send_event(loan_id, Factory.event(%{type: :goal_satisfied}))

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

  defp empty_skills_dir do
    dir = Factory.unique_tmp_dir("loan_actor_heartbeat_empty_skills")
    File.mkdir_p!(dir)
    dir
  end
end
