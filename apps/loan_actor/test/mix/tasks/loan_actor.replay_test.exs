defmodule Mix.Tasks.LoanActor.ReplayTest do
  @moduledoc """
  FT-039 — `mix loan_actor.replay`. Taxonomy: happy / error.
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
    # independent of which DiaryStore backs the actual entries — needed
    # here since the "live actor" test sends a real reactive event.
    :ok = MnesiaStore.init(dir: MnesiaTestSupport.dir())
    :ok
  end

  setup do
    Mix.shell(Mix.Shell.Process)
    Mix.Task.reenable("loan_actor.replay")
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  describe "happy — no live actor running" do
    test "reports the replayed status/version without a live comparison" do
      loan_id = Factory.unique_loan_id()
      entries = Factory.chain_with_event_types([:goal_set, :document_uploaded], %{loan_id: loan_id})
      for entry <- entries, do: {:ok, _} = FileStore.append(loan_id, entry)

      Mix.Task.run("loan_actor.replay", [loan_id])

      assert_received {:mix_shell, :info, [message]}
      assert message =~ "replayed 3 entries for #{loan_id}"
      assert message =~ "status: documents_under_review"
      assert message =~ "no live actor running"
    end
  end

  describe "happy — live actor running" do
    test "reports byte-equal when the replay matches the live actor's state" do
      loan_id = Factory.unique_loan_id()
      {:ok, _pid} = ServerTestSupport.spawn_and_track(loan_id)
      {:ok, _seq} = LoanActor.send_event(loan_id, Factory.event(%{type: :goal_set}))

      Mix.Task.run("loan_actor.replay", [loan_id])

      assert_received {:mix_shell, :info, [message]}
      assert message =~ "replay OK for #{loan_id}"
      assert message =~ "byte-equal to the live actor's state"
    end
  end

  describe "error" do
    test "no loan_id argument raises a usage error" do
      assert_raise Mix.Error, ~r/usage: mix loan_actor\.replay LOAN_ID/, fn ->
        Mix.Task.run("loan_actor.replay", [])
      end
    end

    test "a loan with no diary raises" do
      assert_raise Mix.Error, ~r/no diary found for/, fn ->
        Mix.Task.run("loan_actor.replay", [Factory.unique_loan_id()])
      end
    end

    test "a diary containing an illegal transition raises a clean replay-failed error, not a raw stack trace" do
      loan_id = Factory.unique_loan_id()
      genesis = Factory.entry(%{loan_id: loan_id})
      {:ok, _} = FileStore.append(loan_id, genesis)
      # :complete has no edge from :spawned (Model's only edge for it is
      # {:processing, :complete}) — deliberately malformed for this test.
      illegal = Factory.next_entry(genesis, %{type: :complete})
      {:ok, _} = FileStore.append(loan_id, illegal)

      assert_raise Mix.Error, ~r/replay failed for #{loan_id}/, fn ->
        Mix.Task.run("loan_actor.replay", [loan_id])
      end
    end
  end
end
