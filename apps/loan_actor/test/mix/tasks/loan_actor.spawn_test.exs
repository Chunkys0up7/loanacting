defmodule Mix.Tasks.LoanActor.SpawnTest do
  @moduledoc """
  FT-039 — `mix loan_actor.spawn`. Taxonomy: happy / error.
  """

  use ExUnit.Case, async: false

  alias LoanActor.Factory
  alias LoanActor.Supervisor, as: LoanSupervisor

  setup do
    Mix.shell(Mix.Shell.Process)
    Mix.Task.reenable("loan_actor.spawn")
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  defp track_for_cleanup(loan_id) do
    on_exit(fn ->
      case LoanActor.whereis(loan_id) do
        nil -> :ok
        pid -> DynamicSupervisor.terminate_child(LoanSupervisor, pid)
      end
    end)
  end

  describe "happy" do
    test "spawns a loan and reports its status/version" do
      loan_id = Factory.unique_loan_id()
      track_for_cleanup(loan_id)

      Mix.Task.run("loan_actor.spawn", [loan_id])

      assert_received {:mix_shell, :info, [message]}
      assert message =~ loan_id
      assert message =~ "status: spawned"
      assert message =~ "version: 0"
      assert LoanActor.whereis(loan_id) != nil
    end

    test "is idempotent — spawning an already-running loan reports it without starting a duplicate" do
      loan_id = Factory.unique_loan_id()
      track_for_cleanup(loan_id)

      Mix.Task.run("loan_actor.spawn", [loan_id])
      assert_received {:mix_shell, :info, [_first]}
      pid = LoanActor.whereis(loan_id)

      Mix.Task.reenable("loan_actor.spawn")
      Mix.Task.run("loan_actor.spawn", [loan_id])
      assert_received {:mix_shell, :info, [second]}

      assert second =~ loan_id
      assert LoanActor.whereis(loan_id) == pid
    end
  end

  describe "error" do
    test "no loan_id argument raises a usage error" do
      assert_raise Mix.Error, ~r/usage: mix loan_actor\.spawn LOAN_ID/, fn ->
        Mix.Task.run("loan_actor.spawn", [])
      end
    end

    test "unexpected extra arguments raise a usage error" do
      assert_raise Mix.Error, ~r/usage: mix loan_actor\.spawn LOAN_ID/, fn ->
        Mix.Task.run("loan_actor.spawn", ["L-1", "L-2"])
      end
    end
  end
end
