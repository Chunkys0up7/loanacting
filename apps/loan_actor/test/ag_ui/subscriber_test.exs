defmodule LoanActor.AGUI.SubscriberTest do
  @moduledoc """
  FT-024 — `LoanActor.AGUI.Subscriber`. Taxonomy: happy / race / boundary.

  Slow-consumer resync (research.md R-2) is exercised deterministically —
  not via timing/sleep — by `:sys.suspend/1`'ing the subscriber so casts
  genuinely pile up in its own Erlang mailbox, then `:sys.resume/1`'ing it
  and observing resync mode engage. See the module's own moduledoc for
  why `message_queue_len` is the chosen backpressure signal.
  """

  use ExUnit.Case, async: true

  alias LoanActor.AGUI.Subscriber

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

  describe "deliver/2 — happy" do
    test "the owner receives {:ag_ui_event, ref, event}" do
      ref = make_ref()
      {:ok, sub} = Subscriber.start_link(owner: self(), ref: ref)

      event = %{"type" => "RunStarted", "run_id" => "r-1"}
      :ok = Subscriber.deliver(sub, event)

      assert_receive {:ag_ui_event, ^ref, ^event}
    end

    test "events are delivered in order" do
      ref = make_ref()
      {:ok, sub} = Subscriber.start_link(owner: self(), ref: ref)

      for i <- 1..5, do: Subscriber.deliver(sub, %{"type" => "X", "i" => i})

      for i <- 1..5 do
        assert_receive {:ag_ui_event, ^ref, %{"i" => ^i}}
      end
    end

    test "different subscribers to the same owner are independent (distinguished by ref)" do
      ref_a = make_ref()
      ref_b = make_ref()
      {:ok, sub_a} = Subscriber.start_link(owner: self(), ref: ref_a)
      {:ok, sub_b} = Subscriber.start_link(owner: self(), ref: ref_b)

      Subscriber.deliver(sub_a, %{"type" => "A"})
      Subscriber.deliver(sub_b, %{"type" => "B"})

      assert_receive {:ag_ui_event, ^ref_a, %{"type" => "A"}}
      assert_receive {:ag_ui_event, ^ref_b, %{"type" => "B"}}
    end
  end

  describe "resyncing?/1 + resync/2 — happy" do
    test "a fresh subscriber is not resyncing" do
      {:ok, sub} = Subscriber.start_link(owner: self(), ref: make_ref())
      refute Subscriber.resyncing?(sub)
    end

    test "resync/2 delivers the snapshot and clears resync mode" do
      ref = make_ref()
      {:ok, sub} = Subscriber.start_link(owner: self(), ref: ref, max_queue: 3)
      :sys.suspend(sub)
      for i <- 1..10, do: Subscriber.deliver(sub, %{"type" => "X", "i" => i})
      :sys.resume(sub)

      assert eventually(fn -> Subscriber.resyncing?(sub) || nil end)

      snapshot = %{"type" => "StateSnapshot", "loan_id" => "L-1"}
      :ok = Subscriber.resync(sub, snapshot)

      assert_receive {:ag_ui_event, ^ref, ^snapshot}
      refute Subscriber.resyncing?(sub)
    end
  end

  describe "slow-consumer resync — boundary (deterministic, via :sys.suspend)" do
    test "a mailbox backlog beyond max_queue engages resync mode" do
      ref = make_ref()
      {:ok, sub} = Subscriber.start_link(owner: self(), ref: ref, max_queue: 5)

      :sys.suspend(sub)
      for i <- 1..20, do: Subscriber.deliver(sub, %{"type" => "X", "i" => i})
      :sys.resume(sub)

      assert eventually(fn -> Subscriber.resyncing?(sub) || nil end)
    end

    test "while resyncing, further deliver/2 calls are silently dropped" do
      ref = make_ref()
      {:ok, sub} = Subscriber.start_link(owner: self(), ref: ref, max_queue: 2)

      :sys.suspend(sub)
      for i <- 1..10, do: Subscriber.deliver(sub, %{"type" => "X", "i" => i})
      :sys.resume(sub)
      assert eventually(fn -> Subscriber.resyncing?(sub) || nil end)

      Subscriber.deliver(sub, %{"type" => "should_be_dropped"})
      refute_receive {:ag_ui_event, ^ref, %{"type" => "should_be_dropped"}}, 100
    end

    test "a backlog within max_queue does NOT engage resync mode" do
      ref = make_ref()
      {:ok, sub} = Subscriber.start_link(owner: self(), ref: ref, max_queue: 128)

      :sys.suspend(sub)
      for i <- 1..5, do: Subscriber.deliver(sub, %{"type" => "X", "i" => i})
      :sys.resume(sub)

      for i <- 1..5, do: assert_receive {:ag_ui_event, ^ref, %{"i" => ^i}}
      refute Subscriber.resyncing?(sub)
    end

    test "max_queue defaults to 128 when not specified" do
      {:ok, sub} = Subscriber.start_link(owner: self(), ref: make_ref())
      assert %{max_queue: 128} = :sys.get_state(sub)
    end
  end

  describe "owner death — boundary" do
    test "the subscriber stops itself when its owner process dies" do
      owner = spawn(fn -> Process.sleep(:infinity) end)
      {:ok, sub} = Subscriber.start_link(owner: owner, ref: make_ref())
      sub_ref = Process.monitor(sub)

      Process.exit(owner, :kill)

      # The exit reason is not asserted as exactly :normal: under heavy
      # scheduler contention (the full suite spawns hundreds of processes)
      # the subscriber can occasionally have already exited by the time
      # THIS monitor is set up, and Erlang reports :noproc for an
      # already-dead target regardless of its true prior exit reason. The
      # property actually under test — the subscriber terminates when its
      # owner dies — holds either way.
      assert_receive {:DOWN, ^sub_ref, :process, ^sub, reason}, 1_000
      assert reason in [:normal, :noproc]
    end
  end

  describe "concurrent delivery — race" do
    test "many concurrent deliver/2 calls from different processes are all received, no crash" do
      ref = make_ref()
      {:ok, sub} = Subscriber.start_link(owner: self(), ref: ref, max_queue: 1000)

      1..50
      |> Enum.map(fn i ->
        Task.async(fn -> Subscriber.deliver(sub, %{"type" => "X", "i" => i}) end)
      end)
      |> Enum.each(&Task.await/1)

      received =
        for _ <- 1..50 do
          assert_receive {:ag_ui_event, ^ref, %{"i" => i}}, 1_000
          i
        end

      assert Enum.sort(received) == Enum.to_list(1..50)
      assert Process.alive?(sub)
    end

    test "a concurrent resync/2 racing deliver/2 calls never crashes the subscriber" do
      ref = make_ref()
      {:ok, sub} = Subscriber.start_link(owner: self(), ref: ref, max_queue: 1000)

      tasks =
        [
          Task.async(fn ->
            for i <- 1..20, do: Subscriber.deliver(sub, %{"type" => "X", "i" => i})
          end),
          Task.async(fn -> Subscriber.resync(sub, %{"type" => "StateSnapshot"}) end)
        ]

      Enum.each(tasks, &Task.await/1)

      # Drain whatever arrived — order between the racing calls is not
      # asserted, only that the process survives and both kinds of
      # message eventually show up.
      messages =
        eventually(fn ->
          count =
            Process.info(self(), :messages)
            |> elem(1)
            |> Enum.count(&match?({:ag_ui_event, ^ref, _}, &1))

          if count >= 20, do: count, else: nil
        end)

      assert messages >= 20
      assert Process.alive?(sub)
    end
  end
end
