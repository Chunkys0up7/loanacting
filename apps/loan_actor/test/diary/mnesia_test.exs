defmodule LoanActor.Diary.MnesiaTest do
  @moduledoc """
  FT-008 — `LoanActor.Diary.Mnesia` against the shared `DiaryStore` suite
  plus Mnesia-specific cases: concurrent-append race (race), durability across
  a Mnesia restart (replay), and the `mix loan_actor.init_mnesia` task (happy).

  Backing store: a REAL Mnesia node with disc_copies under the OS tmp dir —
  no mocks at the storage boundary, and nothing production-shaped
  (test-data-forge isolation rules).
  """

  use LoanActor.Diary.StoreSharedTests, store: LoanActor.Diary.Mnesia

  alias LoanActor.Diary.Mnesia, as: MnesiaStore

  @dir Path.join(System.tmp_dir!(), "loan_actor_diary_mnesia_test")

  def store_opts, do: [dir: @dir]

  # Shared-suite tamper hook: rewrite the persisted record's payload_hash.
  def tamper_payload_hash!(loan_id, sequence) do
    [{:loan_diary, key, binary}] = :mnesia.dirty_read(:loan_diary, {loan_id, sequence})
    entry = :erlang.binary_to_term(binary)
    tampered = %{entry | payload_hash: <<1::256>>}
    :ok = :mnesia.dirty_write({:loan_diary, key, :erlang.term_to_binary(tampered)})
    :ok
  end

  describe "concurrent appends — race" do
    test "one winner per sequence: identical competing appends serialize" do
      loan_id = Factory.unique_loan_id()
      genesis = Factory.entry(%{loan_id: loan_id})
      {:ok, 0} = MnesiaStore.append(loan_id, genesis)

      contender = Factory.next_entry(genesis)

      results =
        1..10
        |> Task.async_stream(fn _ -> MnesiaStore.append(loan_id, contender) end,
          max_concurrency: 10
        )
        |> Enum.map(fn {:ok, res} -> res end)

      assert Enum.count(results, &match?({:ok, 1}, &1)) == 1
      assert Enum.count(results, &match?({:error, _}, &1)) == 9
      assert :ok = MnesiaStore.verify_chain(loan_id)
      assert length(Enum.to_list(MnesiaStore.stream(loan_id, []))) == 2
    end

    test "retrying appenders all land; chain stays gap-free and verified" do
      loan_id = Factory.unique_loan_id()
      {:ok, 0} = MnesiaStore.append(loan_id, Factory.entry(%{loan_id: loan_id}))

      append_with_retry = fn ->
        Enum.each(1..5, fn _ ->
          Stream.repeatedly(fn ->
            {:ok, tail} = MnesiaStore.tail(loan_id)
            MnesiaStore.append(loan_id, Factory.next_entry(tail))
          end)
          |> Enum.find(&match?({:ok, _}, &1))
        end)
      end

      1..8
      |> Task.async_stream(fn _ -> append_with_retry.() end,
        max_concurrency: 8,
        timeout: 30_000
      )
      |> Stream.run()

      entries = Enum.to_list(MnesiaStore.stream(loan_id, []))
      assert length(entries) == 41
      assert Enum.map(entries, & &1.sequence) == Enum.to_list(0..40)
      assert :ok = MnesiaStore.verify_chain(loan_id)
    end
  end

  describe "durability — replay" do
    test "entries survive a full Mnesia stop/start cycle (disc_copies)" do
      loan_id = Factory.unique_loan_id()
      entries = Factory.chain(5, %{loan_id: loan_id})
      for entry <- entries, do: {:ok, _} = MnesiaStore.append(loan_id, entry)

      :stopped = :mnesia.stop()
      :ok = :mnesia.start()
      :ok = :mnesia.wait_for_tables([:loan_diary], 10_000)

      assert Enum.to_list(MnesiaStore.stream(loan_id, [])) == entries
      assert :ok = MnesiaStore.verify_chain(loan_id)
    end
  end

  describe "mix loan_actor.init_mnesia — happy" do
    test "task initializes the store idempotently against the test dir" do
      Mix.shell(Mix.Shell.Process)
      on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

      assert :ok = Mix.Task.rerun("loan_actor.init_mnesia", ["--dir", @dir])
      assert_received {:mix_shell, :info, ["mnesia diary store ready" <> _]}
      assert :loan_diary in :mnesia.system_info(:tables)

      # still usable afterwards
      loan_id = Factory.unique_loan_id()
      assert {:ok, 0} = MnesiaStore.append(loan_id, Factory.entry(%{loan_id: loan_id}))
      assert :ok = MnesiaStore.verify_chain(loan_id)
    end
  end
end
