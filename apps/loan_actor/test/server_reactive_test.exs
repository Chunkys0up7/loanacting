defmodule LoanActor.ServerReactiveTest do
  @moduledoc """
  FT-017 — `LoanActor.Server` reactive loop via the public `LoanActor` API.
  Taxonomy: happy / error / boundary. Each pipeline step (validate →
  PIIGuard → idempotency → transition → diary append) is tested in
  isolation, plus a full integration path (spawn → events → crash → replay).

  Every test forces `:skills_dir` to a guaranteed-empty directory: FT-019
  made `:goal_set` events trigger the planning loop (`maybe_trigger_planning/1`
  in the shared `apply_event/3` path this file's tests exercise), and
  without this, whichever real demo skill pack happens to be configured
  could match and append extra diary entries these tests' exact-shape
  assertions (written before FT-019 existed) don't expect. Planning-loop
  behavior itself is FT-019's own concern — `test/server_planning_test.exs`.
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
    # LoanActor.Idempotency's loan_idem table is always Mnesia (data-model.md),
    # independent of which DiaryStore backs the actual entries.
    :ok = MnesiaStore.init(dir: MnesiaTestSupport.dir())
    :ok
  end

  setup do
    previous_skills_dir = Application.get_env(:loan_actor, :skills_dir)
    empty_dir = Factory.unique_tmp_dir("loan_actor_server_reactive_empty_skills")
    File.mkdir_p!(empty_dir)
    Application.put_env(:loan_actor, :skills_dir, empty_dir)

    on_exit(fn ->
      case previous_skills_dir do
        nil -> Application.delete_env(:loan_actor, :skills_dir)
        value -> Application.put_env(:loan_actor, :skills_dir, value)
      end
    end)

    :ok
  end

  defp entries(loan_id), do: Enum.to_list(FileStore.stream(loan_id, []))

  defp eventually(fun, attempts \\ 50) do
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

  describe "LoanActor.spawn/1 — happy" do
    test "spawns a supervised actor with a genesis diary entry" do
      loan_id = Factory.unique_loan_id()
      assert {:ok, pid} = ServerTestSupport.spawn_and_track(loan_id)
      assert Process.alive?(pid)

      assert {:ok, state} = LoanActor.state(loan_id)
      assert state.status == :spawned
      assert state.loan_id == loan_id
      assert state.version == 0

      assert [%{type: :spawned, sequence: 0, actor: "system"}] = entries(loan_id)
    end

    test "spawning the same loan_id twice is idempotent" do
      loan_id = Factory.unique_loan_id()
      assert {:ok, pid1} = ServerTestSupport.spawn_and_track(loan_id)
      assert {:ok, pid2} = ServerTestSupport.spawn_and_track(loan_id)
      assert pid1 == pid2
    end
  end

  describe "send_event — boundary" do
    test "an unknown loan_id (never spawned) is :not_running" do
      assert {:error, :not_running} =
               LoanActor.send_event(Factory.unique_loan_id(), Factory.event(%{type: :goal_set}))
    end
  end

  describe "send_event — error (validate step, in isolation)" do
    test "an invalid event is rejected before touching PIIGuard/idempotency/diary" do
      loan_id = Factory.unique_loan_id()
      {:ok, _pid} = ServerTestSupport.spawn_and_track(loan_id)

      assert {:error, :invalid_event} = LoanActor.send_event(loan_id, %LoanActor.Event{})
      assert length(entries(loan_id)) == 1
    end
  end

  describe "send_event — error (PIIGuard step, in isolation)" do
    test "a PII-shaped payload is rejected before touching idempotency/diary" do
      loan_id = Factory.unique_loan_id()
      {:ok, _pid} = ServerTestSupport.spawn_and_track(loan_id)

      event = Factory.event(%{type: :goal_set, payload: %{"ssn" => "123-45-6789"}})
      assert {:error, {:pii_violation, [["ssn"]]}} = LoanActor.send_event(loan_id, event)
      assert length(entries(loan_id)) == 1
    end
  end

  describe "send_event — happy (transition + diary append)" do
    test "a legal event transitions state and appends a diary entry" do
      loan_id = Factory.unique_loan_id()
      {:ok, _pid} = ServerTestSupport.spawn_and_track(loan_id)

      event = Factory.event(%{type: :goal_set, payload: %{"note" => "income doc needed"}})
      assert {:ok, 1} = LoanActor.send_event(loan_id, event)

      assert {:ok, state} = LoanActor.state(loan_id)
      assert state.status == :awaiting_documents
      assert state.version == 1

      assert [%{type: :spawned}, %{type: :goal_set, sequence: 1}] = entries(loan_id)
    end
  end

  describe "send_event — error (idempotency step, in isolation)" do
    test "re-delivering the SAME event_id reports {:duplicate, original_sequence}, no second diary entry" do
      loan_id = Factory.unique_loan_id()
      {:ok, _pid} = ServerTestSupport.spawn_and_track(loan_id)

      event = Factory.event(%{type: :goal_set})
      assert {:ok, 1} = LoanActor.send_event(loan_id, event)
      assert {:duplicate, 1} = LoanActor.send_event(loan_id, event)
      assert {:duplicate, 1} = LoanActor.send_event(loan_id, event)

      assert length(entries(loan_id)) == 2
    end
  end

  describe "send_event — error (illegal transition)" do
    test "an event with no legal edge from the current status is rejected and diary-logged" do
      loan_id = Factory.unique_loan_id()
      {:ok, _pid} = ServerTestSupport.spawn_and_track(loan_id)

      # :spawned has no :complete edge (LoanActor.State.Model)
      event = Factory.event(%{type: :complete})
      assert {:error, {:illegal_transition, :spawned, :complete}} = LoanActor.send_event(loan_id, event)

      assert {:ok, state} = LoanActor.state(loan_id)
      assert state.status == :spawned
      assert state.version == 0

      assert [%{type: :spawned}, %{type: :illegal_transition_attempted, sequence: 1}] = entries(loan_id)
    end

    test "re-delivering the SAME event_id after an illegal transition also reports the recorded sequence" do
      loan_id = Factory.unique_loan_id()
      {:ok, _pid} = ServerTestSupport.spawn_and_track(loan_id)
      event = Factory.event(%{type: :complete})

      assert {:error, {:illegal_transition, :spawned, :complete}} = LoanActor.send_event(loan_id, event)
      assert {:duplicate, 1} = LoanActor.send_event(loan_id, event)
      assert length(entries(loan_id)) == 2
    end
  end

  describe "integration — full pipeline + crash-recovery rehydration" do
    test "several events land in sequence, then killing and respawning replays to the same state" do
      loan_id = Factory.unique_loan_id()
      {:ok, pid} = ServerTestSupport.spawn_and_track(loan_id)

      assert {:ok, 1} = LoanActor.send_event(loan_id, Factory.event(%{type: :goal_set}))
      assert {:ok, 2} = LoanActor.send_event(loan_id, Factory.event(%{type: :document_uploaded}))
      assert {:ok, 3} = LoanActor.send_event(loan_id, Factory.event(%{type: :goal_satisfied}))

      {:ok, pre_crash_state} = LoanActor.state(loan_id)
      assert pre_crash_state.status == :processing
      assert pre_crash_state.version == 3

      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 1_000

      new_pid =
        eventually(fn ->
          case LoanActor.whereis(loan_id) do
            nil -> nil
            ^pid -> nil
            other -> other
          end
        end)

      assert is_pid(new_pid)
      assert {:ok, rehydrated_state} = LoanActor.state(loan_id)

      # last_heartbeat_at is excluded: its live value comes from a
      # DateTime.utc_now() call at heartbeat time, never stored verbatim
      # in the diary (only a hash of the state it was set on) — a real
      # heartbeat tick between the pre-crash snapshot above and the crash
      # a few lines later lands on a genuinely different timestamp on
      # each side. Same reasoning (and same fix shape) as
      # server_property_test.exs/nfr_load_test.exs/smoke_test.exs; this
      # test predates all three and never got it, which is exactly why a
      # real CI run (config/test.exs's heartbeat_ms: 100 makes this race
      # far more likely on a loaded/shared runner than on a quiet local
      # machine) caught it here first.
      assert %{rehydrated_state | last_heartbeat_at: nil} == %{pre_crash_state | last_heartbeat_at: nil}
    end
  end
end
