defmodule LoanActor.IdempotencyTest do
  @moduledoc """
  FT-015 — `LoanActor.Idempotency.check_and_record/3` + `record_sequence/4`
  (shape extended per clarifications.md Q13, discovered while building
  FT-017: `{:duplicate, sequence}` requires the idem record to carry it).
  Now consumed only by `LoanActor.Diary.File.append_with_dedup/4` (0005) —
  `Server` no longer calls these directly.

  Also covers `txn_check/3` + `txn_record/4` (FT-046, 0005) — the
  transaction-scoped siblings `LoanActor.Diary.Mnesia.append_with_dedup/4`
  uses inside its own combined transaction. These are unit/happy/atomicity
  tests only; the concurrent-duplicate-delivery race property that used to
  be tested standalone here is now proven at the `DiaryStore` behaviour
  level instead (`test/support/diary_store_shared.ex`'s
  `append_with_dedup/4` describe block, parameterized across both
  implementations) — not duplicated here, since `txn_check/3`/`txn_record/4`
  only ever run inside an already-open transaction and can't race standalone.

  Taxonomy: happy / replay / regression.

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

    test "the same key seen again is {:duplicate, sequence} with the original sequence" do
      loan_id = Factory.unique_loan_id()
      event_id = unique_event_id()
      assert :fresh = Idempotency.check_and_record(loan_id, event_id, :test)
      :ok = Idempotency.record_sequence(loan_id, event_id, :test, 7)
      assert {:duplicate, 7} = Idempotency.check_and_record(loan_id, event_id, :test)
    end

    test "a key re-checked before record_sequence/4 reports {:duplicate, nil} (reserved, unfilled)" do
      loan_id = Factory.unique_loan_id()
      event_id = unique_event_id()
      assert :fresh = Idempotency.check_and_record(loan_id, event_id, :test)
      assert {:duplicate, nil} = Idempotency.check_and_record(loan_id, event_id, :test)
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

  describe "record_sequence/4 — error" do
    test "raises if the key was never reserved" do
      assert_raise MatchError, fn ->
        Idempotency.record_sequence(Factory.unique_loan_id(), unique_event_id(), :test, 1)
      end
    end

    test "raises if called a second time (already filled)" do
      loan_id = Factory.unique_loan_id()
      event_id = unique_event_id()
      :fresh = Idempotency.check_and_record(loan_id, event_id, :test)
      :ok = Idempotency.record_sequence(loan_id, event_id, :test, 3)

      assert_raise MatchError, fn ->
        Idempotency.record_sequence(loan_id, event_id, :test, 4)
      end
    end
  end

  describe "txn_check/3 + txn_record/4 (0005) — happy, transaction-scoped" do
    test "a never-before-seen key is :fresh; txn_record/4 fills the sequence for a later txn_check/3" do
      loan_id = Factory.unique_loan_id()
      event_id = unique_event_id()

      {:atomic, result} =
        :mnesia.transaction(fn ->
          fresh = Idempotency.txn_check(loan_id, event_id, :test)
          :ok = Idempotency.txn_record(loan_id, event_id, :test, 5)
          fresh
        end)

      assert result == :fresh

      assert {:atomic, {:duplicate, 5}} =
               :mnesia.transaction(fn -> Idempotency.txn_check(loan_id, event_id, :test) end)
    end

    test "a key already recorded is {:duplicate, sequence} within the same transaction call" do
      loan_id = Factory.unique_loan_id()
      event_id = unique_event_id()

      {:atomic, :ok} =
        :mnesia.transaction(fn ->
          :fresh = Idempotency.txn_check(loan_id, event_id, :test)
          Idempotency.txn_record(loan_id, event_id, :test, 3)
        end)

      assert {:atomic, {:duplicate, 3}} =
               :mnesia.transaction(fn -> Idempotency.txn_check(loan_id, event_id, :test) end)
    end

    test "an aborted transaction leaves neither a fresh reservation nor a recorded sequence" do
      loan_id = Factory.unique_loan_id()
      event_id = unique_event_id()

      {:aborted, :simulated_failure} =
        :mnesia.transaction(fn ->
          :fresh = Idempotency.txn_check(loan_id, event_id, :test)
          :mnesia.abort(:simulated_failure)
        end)

      assert {:atomic, :fresh} = :mnesia.transaction(fn -> Idempotency.txn_check(loan_id, event_id, :test) end)
    end
  end

  describe "check_and_record/3 — replay (durability across a Mnesia restart)" do
    test "a recorded key still reports the same {:duplicate, sequence} after Mnesia stops and restarts" do
      loan_id = Factory.unique_loan_id()
      event_id = unique_event_id()
      assert :fresh = Idempotency.check_and_record(loan_id, event_id, :test)
      :ok = Idempotency.record_sequence(loan_id, event_id, :test, 12)

      :stopped = :mnesia.stop()
      :ok = :mnesia.start()
      :ok = :mnesia.wait_for_tables([:loan_idem], 10_000)

      assert {:duplicate, 12} = Idempotency.check_and_record(loan_id, event_id, :test)
    end
  end
end
