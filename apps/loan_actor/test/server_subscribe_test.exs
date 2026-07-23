defmodule LoanActor.ServerSubscribeTest do
  @moduledoc """
  FT-025 — `LoanActor.Server.subscribe/2`. Taxonomy: happy / race.

  Every diary append broadcasts a `CustomEvent diary_entry`
  (`append_entry/4` is the single centralized call site); a successful
  reactive transition additionally broadcasts a `StateDelta` (whole-state
  replace, per the encoder — see `server.ex` moduledoc scope note). A
  subscriber's own bounded-queue/resync mechanics are FT-024's own concern
  (`subscriber_test.exs`); this file proves the Server-side wiring:
  subscribe/2's contract, broadcast fan-out, and subscriber cleanup on
  owner death.
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
    empty_dir = Factory.unique_tmp_dir("loan_actor_server_subscribe_empty_skills")
    File.mkdir_p!(empty_dir)
    previous = Application.get_env(:loan_actor, :skills_dir)
    Application.put_env(:loan_actor, :skills_dir, empty_dir)

    on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:loan_actor, :skills_dir)
        value -> Application.put_env(:loan_actor, :skills_dir, value)
      end
    end)

    :ok
  end

  defp eventually(fun, attempts \\ 100) do
    Enum.reduce_while(1..attempts, nil, fn _, _ ->
      case fun.() do
        nil ->
          Process.sleep(5)
          {:cont, nil}

        value ->
          {:halt, value}
      end
    end)
  end

  describe "subscribe/2 — happy" do
    test "returns {:ok, ref}" do
      loan_id = Factory.unique_loan_id()
      {:ok, _pid} = ServerTestSupport.spawn_and_track(loan_id)

      assert {:ok, ref} = LoanActor.subscribe(loan_id)
      assert is_reference(ref)
    end

    test "an unknown loan_id is :not_running" do
      assert {:error, :not_running} = LoanActor.subscribe(Factory.unique_loan_id())
    end

    test "subscribing to a loan already running receives subsequent diary_entry events" do
      loan_id = Factory.unique_loan_id()
      {:ok, _pid} = ServerTestSupport.spawn_and_track(loan_id)

      {:ok, ref} = LoanActor.subscribe(loan_id)

      {:ok, _seq} = LoanActor.send_event(loan_id, Factory.event(%{type: :goal_set}))

      assert_receive {:ag_ui_event, ^ref,
                       %{"type" => "CustomEvent", "name" => "diary_entry", "loan_id" => ^loan_id}}
    end

    test "a successful reactive transition also broadcasts a StateDelta, after the diary_entry" do
      loan_id = Factory.unique_loan_id()
      {:ok, _pid} = ServerTestSupport.spawn_and_track(loan_id)
      {:ok, ref} = LoanActor.subscribe(loan_id)

      {:ok, _seq} = LoanActor.send_event(loan_id, Factory.event(%{type: :goal_set}))

      assert_receive {:ag_ui_event, ^ref, %{"type" => "CustomEvent", "name" => "diary_entry"}}
      assert_receive {:ag_ui_event, ^ref, %{"type" => "StateDelta", "loan_id" => ^loan_id, "patch" => patch}}
      assert [%{"op" => "replace", "path" => "", "value" => %{"status" => "awaiting_documents"}}] = patch
    end

    test "an illegal transition broadcasts only a diary_entry, no StateDelta" do
      loan_id = Factory.unique_loan_id()
      {:ok, _pid} = ServerTestSupport.spawn_and_track(loan_id)
      {:ok, ref} = LoanActor.subscribe(loan_id)

      # :spawned has no :complete edge (LoanActor.State.Model)
      {:error, {:illegal_transition, :spawned, :complete}} =
        LoanActor.send_event(loan_id, Factory.event(%{type: :complete}))

      assert_receive {:ag_ui_event, ^ref,
                       %{"type" => "CustomEvent", "name" => "diary_entry", "entry" => %{"type" => "illegal_transition_attempted"}}}

      refute_receive {:ag_ui_event, ^ref, %{"type" => "StateDelta"}}, 100
    end

    test "multiple subscribers to the same loan each receive the broadcast" do
      loan_id = Factory.unique_loan_id()
      {:ok, _pid} = ServerTestSupport.spawn_and_track(loan_id)

      parent = self()

      task_a =
        Task.async(fn ->
          {:ok, ref} = LoanActor.subscribe(loan_id)
          send(parent, {:subscribed, :a})

          receive do
            {:ag_ui_event, ^ref, %{"type" => "CustomEvent", "name" => "diary_entry"}} -> :ok
          after
            2_000 -> :timeout
          end
        end)

      task_b =
        Task.async(fn ->
          {:ok, ref} = LoanActor.subscribe(loan_id)
          send(parent, {:subscribed, :b})

          receive do
            {:ag_ui_event, ^ref, %{"type" => "CustomEvent", "name" => "diary_entry"}} -> :ok
          after
            2_000 -> :timeout
          end
        end)

      assert_receive {:subscribed, :a}
      assert_receive {:subscribed, :b}

      {:ok, _seq} = LoanActor.send_event(loan_id, Factory.event(%{type: :goal_set}))

      assert Task.await(task_a) == :ok
      assert Task.await(task_b) == :ok
    end
  end

  describe "subscribe/2 — subscriber cleanup on owner death (boundary)" do
    test "a dead subscribing process is removed from gen_state.subscribers" do
      loan_id = Factory.unique_loan_id()
      {:ok, pid} = ServerTestSupport.spawn_and_track(loan_id)

      owner = spawn(fn -> Process.sleep(:infinity) end)
      {:ok, _ref} = GenServer.call(pid, {:subscribe, owner, []})

      assert %{subscribers: [_one]} = :sys.get_state(pid)

      Process.exit(owner, :kill)

      eventually(fn ->
        case :sys.get_state(pid) do
          %{subscribers: []} -> true
          _still_present -> nil
        end
      end)

      assert %{subscribers: []} = :sys.get_state(pid)
    end
  end

  describe "subscribe/2 — race" do
    test "many concurrent subscribe/2 calls all succeed and all receive the broadcast" do
      loan_id = Factory.unique_loan_id()
      {:ok, _pid} = ServerTestSupport.spawn_and_track(loan_id)

      parent = self()

      tasks =
        Enum.map(1..20, fn i ->
          Task.async(fn ->
            {:ok, ref} = LoanActor.subscribe(loan_id)
            send(parent, {:ready, i})

            receive do
              {:ag_ui_event, ^ref, %{"type" => "CustomEvent", "name" => "diary_entry"}} -> :ok
            after
              2_000 -> :timeout
            end
          end)
        end)

      for i <- 1..20, do: assert_receive {:ready, ^i}

      {:ok, _seq} = LoanActor.send_event(loan_id, Factory.event(%{type: :goal_set}))

      results = Enum.map(tasks, &Task.await/1)
      assert Enum.all?(results, &(&1 == :ok))
    end
  end
end
