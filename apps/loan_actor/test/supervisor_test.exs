defmodule LoanActor.SupervisorTest do
  @moduledoc """
  FT-016 — `LoanActor.Supervisor` (DynamicSupervisor) + `LoanActor.Registry`.
  Taxonomy: happy / error.

  `LoanActor.Application` starts both under `mix test`'s normal app-boot
  step (no manual setup needed here). Uses the `LoanActor.DummyActor`
  fixture GenServer to stand in for the not-yet-built `LoanActor.Server`
  (FT-017), testing the supervision/registry MECHANICS in isolation.
  """

  use ExUnit.Case, async: false

  alias LoanActor.DummyActor
  alias LoanActor.Factory
  alias LoanActor.Registry, as: LoanRegistry
  alias LoanActor.Supervisor, as: LoanSupervisor

  # Bounded polling helper (never a bare Process.sleep as a sync primitive —
  # forbidden per checklists/test-coverage.md).
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

  describe "start_child + Registry.whereis — happy" do
    test "starting a child registers it, and lookup finds the same pid" do
      loan_id = Factory.unique_loan_id()
      assert {:ok, pid} = LoanSupervisor.start_child({DummyActor, loan_id})
      assert LoanRegistry.whereis(loan_id) == pid
      assert Process.alive?(pid)
    end

    test "whereis/1 returns nil for a loan_id nothing has registered" do
      assert LoanRegistry.whereis(Factory.unique_loan_id()) == nil
    end

    test "via/1 produces a name usable as a GenServer :name option" do
      loan_id = Factory.unique_loan_id()
      {:ok, pid} = GenServer.start_link(DummyActor, loan_id, name: LoanRegistry.via(loan_id))
      assert LoanRegistry.whereis(loan_id) == pid
    end
  end

  describe "crash + restart — happy" do
    test "a crashed child is restarted (one_for_one) and re-registers under the same loan_id" do
      loan_id = Factory.unique_loan_id()
      {:ok, pid} = LoanSupervisor.start_child({DummyActor, loan_id})
      ref = Process.monitor(pid)

      DummyActor.crash(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000

      # Poll for a pid DIFFERENT from the crashed one — the registry's own
      # cleanup-on-death and the supervisor's restart are two independent
      # monitors on the same process, with no ordering guarantee relative
      # to each other or to our own monitor's :DOWN message, so `whereis`
      # can still report the (already-dead) old pid for a brief window.
      new_pid =
        eventually(fn ->
          case LoanRegistry.whereis(loan_id) do
            nil -> nil
            ^pid -> nil
            other -> other
          end
        end)

      assert is_pid(new_pid)
      assert new_pid != pid
      assert Process.alive?(new_pid)
    end

    test "a crash of one loan does not affect a sibling loan (one_for_one isolation)" do
      loan_a = Factory.unique_loan_id()
      loan_b = Factory.unique_loan_id()
      {:ok, pid_a} = LoanSupervisor.start_child({DummyActor, loan_a})
      {:ok, pid_b} = LoanSupervisor.start_child({DummyActor, loan_b})

      DummyActor.crash(pid_a)
      eventually(fn -> if LoanRegistry.whereis(loan_a) != pid_a, do: true end)

      assert LoanRegistry.whereis(loan_b) == pid_b
      assert Process.alive?(pid_b)
    end
  end

  describe "start_child — error" do
    test "starting two children under the SAME registry name conflicts" do
      loan_id = Factory.unique_loan_id()
      assert {:ok, _pid} = LoanSupervisor.start_child({DummyActor, loan_id})
      assert {:error, {:already_started, _pid}} = LoanSupervisor.start_child({DummyActor, loan_id})
    end
  end
end
