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
  alias LoanActor.MnesiaTestSupport

  @dir MnesiaTestSupport.dir()

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

  describe "init/1 — error recovery (extra_applications auto-start scenario)" do
    test "recovers when Mnesia is running without a disc schema for the current dir" do
      # Reproduces the exact precondition of a real (non-test) boot bug:
      # `:mnesia` is listed in mix.exs `extra_applications`, so OTP starts
      # it automatically before LoanActor.Application ever runs — in its
      # bare RAM-only default mode, no disc-based schema for this node.
      # `LoanActor.Server.init/1` calls `store.init([])` with NO :dir, so
      # nothing was forcing a stop+recreate cycle before this fix; every
      # OTHER test in this file passes only because it explicitly calls
      # init(dir: @dir), which happens to trigger that cycle anyway.
      #
      # Uses an ISOLATED, never-before-initialized directory (not the
      # shared @dir every other test in this file depends on): once a
      # node's disc schema is created for a given directory, it persists
      # across stop/start within the same test run, so the bug's
      # precondition can only be reproduced against a genuinely fresh dir.
      isolated_dir = Factory.unique_tmp_dir("loan_actor_mnesia_recovery")

      :stopped = :mnesia.stop()
      :ok = :application.set_env(:mnesia, :dir, String.to_charlist(Path.expand(isolated_dir)))
      :ok = :mnesia.start()
      assert :mnesia.system_info(:is_running) == :yes
      refute node() in :mnesia.table_info(:schema, :disc_copies)

      assert :ok = MnesiaStore.init(dir: isolated_dir)
      assert node() in :mnesia.table_info(:schema, :disc_copies)

      # And the store is genuinely usable afterward, not just "started".
      loan_id = Factory.unique_loan_id()
      assert {:ok, 0} = MnesiaStore.append(loan_id, Factory.entry(%{loan_id: loan_id}))
      assert :ok = MnesiaStore.verify_chain(loan_id)

      # Restore the shared dir (init/1 itself waits for tables) so every
      # other test in this file/suite is unaffected.
      assert :ok = MnesiaStore.init(dir: @dir)
    end
  end

  describe "init/1 — mnesia_dir config fallback (happy)" do
    test "init([]) with no :dir falls back to config :loan_actor, :mnesia_dir" do
      # config.exs/dev.exs declare :mnesia_dir but nothing read it until
      # this fix — the Server's own boot path (`store.init([])`) always
      # omits :dir, so this fallback is what makes real (non-test) runs
      # honor that config at all.
      previous = Application.get_env(:loan_actor, :mnesia_dir)
      Application.put_env(:loan_actor, :mnesia_dir, @dir)
      on_exit(fn -> restore_mnesia_dir(previous) end)

      assert :ok = MnesiaStore.init([])
      assert :mnesia.system_info(:directory) == String.to_charlist(Path.expand(@dir))
    end
  end

  defp restore_mnesia_dir(nil), do: Application.delete_env(:loan_actor, :mnesia_dir)
  defp restore_mnesia_dir(value), do: Application.put_env(:loan_actor, :mnesia_dir, value)

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
