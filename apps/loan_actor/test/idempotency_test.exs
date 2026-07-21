defmodule LoanActor.IdempotencyTest do
  @moduledoc """
  FT-015 — `LoanActor.Idempotency.check_and_record/3`.
  Taxonomy: happy / race / replay.

  Mnesia is a single node-wide database: this suite shares its directory
  with `test/diary/mnesia_test.exs` via `LoanActor.MnesiaTestSupport` so
  neither file's `init/1` call stops+restarts Mnesia against a different
  path mid-run (which would discard the other file's tables/data).
  """

  use ExUnit.Case, async: false

  alias LoanActor.Diary.Mnesia, as: MnesiaStore
  alias LoanActor.Factory
  alias LoanActor.Idempotency
  alias LoanActor.MnesiaTestSupport

  setup_all do
    :ok = MnesiaStore.init(dir: MnesiaTestSupport.dir())
    :ok
  end

  defp unique_event_id, do: "EVT-#{System.unique_integer([:positive, :monotonic])}"

  describe "check_and_record/3 — happy" do
    test "a never-before-seen key is :fresh" do
      assert :fresh = Idempotency.check_and_record(Factory.unique_loan_id(), unique_event_id(), :test)
    end

    test "the same key seen again is :duplicate" do
      loan_id = Factory.unique_loan_id()
      event_id = unique_event_id()
      assert :fresh = Idempotency.check_and_record(loan_id, event_id, :test)
      assert :duplicate = Idempotency.check_and_record(loan_id, event_id, :test)
    end

    test "the same event_id from a DIFFERENT source is a distinct key (clarifications Q6)" do
      loan_id = Factory.unique_loan_id()
      event_id = unique_event_id()
      assert :fresh = Idempotency.check_and_record(loan_id, event_id, :operator)
      assert :fresh = Idempotency.check_and_record(loan_id, event_id, :system)
    end

    test "the same event_id for a DIFFERENT loan is a distinct key" do
      event_id = unique_event_id()
      assert :fresh = Idempotency.check_and_record(Factory.unique_loan_id(), event_id, :test)
      assert :fresh = Idempotency.check_and_record(Factory.unique_loan_id(), event_id, :test)
    end
  end

  describe "check_and_record/3 — race" do
    test "10 concurrent callers racing the same key: exactly one wins :fresh" do
      loan_id = Factory.unique_loan_id()
      event_id = unique_event_id()

      results =
        1..10
        |> Task.async_stream(fn _ -> Idempotency.check_and_record(loan_id, event_id, :test) end,
          max_concurrency: 10
        )
        |> Enum.map(fn {:ok, result} -> result end)

      assert Enum.count(results, &(&1 == :fresh)) == 1
      assert Enum.count(results, &(&1 == :duplicate)) == 9
    end
  end

  describe "check_and_record/3 — replay (durability across a Mnesia restart)" do
    test "a recorded key still reports :duplicate after Mnesia stops and restarts" do
      loan_id = Factory.unique_loan_id()
      event_id = unique_event_id()
      assert :fresh = Idempotency.check_and_record(loan_id, event_id, :test)

      :stopped = :mnesia.stop()
      :ok = :mnesia.start()
      :ok = :mnesia.wait_for_tables([:loan_idem], 10_000)

      assert :duplicate = Idempotency.check_and_record(loan_id, event_id, :test)
    end
  end
end
