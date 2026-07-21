# A parameterized behaviour suite is inherently one long quote block — the
# whole point is injecting the full test set into each implementation module.
# credo:disable-for-this-file Credo.Check.Refactor.LongQuoteBlocks
defmodule LoanActor.Diary.StoreSharedTests do
  @moduledoc """
  Parameterized `DiaryStore` behaviour suite (FT-006). Every implementation
  MUST pass these tests unchanged — they encode the invariants from
  `contracts/diary-store-behaviour.md`.

  Usage (see `test/diary/shared_behaviour_test.exs` for the instantiation map):

      defmodule LoanActor.Diary.FileTest do
        use LoanActor.Diary.StoreSharedTests, store: LoanActor.Diary.File

        # required tamper hook — mutate the PERSISTED entry's payload_hash
        def tamper_payload_hash!(loan_id, sequence), do: ...

        # optional: init opts for the store
        def store_opts, do: [dir: ...]
      end

  Taxonomy covered here: contract / happy / boundary / error / security
  (tamper) / replay (round-trip property). Race tests are implementation-
  specific (FT-008) and live in the concrete test modules.
  """

  defmacro __using__(opts) do
    store = Keyword.fetch!(opts, :store)

    quote location: :keep do
      # Real backing stores (disk / Mnesia) — never mocked, never async.
      use ExUnit.Case, async: false
      use ExUnitProperties

      alias LoanActor.Diary.Entry
      alias LoanActor.Factory

      @store unquote(store)

      def store_opts, do: []
      defoverridable store_opts: 0

      setup_all do
        :ok = @store.init(store_opts())
        :ok
      end

      defp seed_chain(n) do
        loan_id = Factory.unique_loan_id()
        entries = Factory.chain(n, %{loan_id: loan_id})

        for entry <- entries do
          {:ok, _seq} = @store.append(loan_id, entry)
        end

        {loan_id, entries}
      end

      describe "#{inspect(@store)} — contract/happy" do
        test "init/1 is idempotent" do
          assert :ok = @store.init(store_opts())
          assert :ok = @store.init(store_opts())
        end

        test "append/2 returns each entry's sequence, increasing by exactly 1" do
          loan_id = Factory.unique_loan_id()

          seqs =
            Factory.chain(5, %{loan_id: loan_id})
            |> Enum.map(fn entry ->
              {:ok, seq} = @store.append(loan_id, entry)
              seq
            end)

          assert seqs == [0, 1, 2, 3, 4]
        end

        test "tail/1 returns the most recent entry" do
          {loan_id, entries} = seed_chain(4)
          assert {:ok, tail} = @store.tail(loan_id)
          assert tail == List.last(entries)
        end

        test "read_range/3 returns the inclusive ascending range" do
          {loan_id, entries} = seed_chain(6)
          assert {:ok, read} = @store.read_range(loan_id, 1, 3)
          assert read == Enum.slice(entries, 1..3)
        end

        test "stream/2 yields every entry in order and matches read_range" do
          {loan_id, entries} = seed_chain(7)
          assert Enum.to_list(@store.stream(loan_id, [])) == entries
          assert {:ok, ^entries} = @store.read_range(loan_id, 0, 6)
        end

        test "verify_chain/1 passes for an untampered diary" do
          {loan_id, _entries} = seed_chain(5)
          assert :ok = @store.verify_chain(loan_id)
        end
      end

      describe "#{inspect(@store)} — boundary" do
        test "tail/1 is {:ok, nil} for a loan with no entries" do
          assert {:ok, nil} = @store.tail(Factory.unique_loan_id())
        end

        test "read_range/3 on an empty diary is {:ok, []}" do
          assert {:ok, []} = @store.read_range(Factory.unique_loan_id(), 0, 100)
        end

        test "read_range/3 clamps to what exists past the tail" do
          {loan_id, entries} = seed_chain(3)
          assert {:ok, ^entries} = @store.read_range(loan_id, 0, 999)
        end

        test "read_range/3 with from > to is {:ok, []}" do
          {loan_id, _} = seed_chain(3)
          assert {:ok, []} = @store.read_range(loan_id, 2, 1)
        end

        test "a single-entry (genesis-only) diary verifies" do
          {loan_id, _} = seed_chain(1)
          assert :ok = @store.verify_chain(loan_id)
        end
      end

      describe "#{inspect(@store)} — error + atomicity" do
        test "append/2 rejects a genesis entry with non-zero sequence" do
          loan_id = Factory.unique_loan_id()
          entry = Factory.entry(%{loan_id: loan_id, sequence: 3})
          assert {:error, _} = @store.append(loan_id, entry)
          assert {:ok, nil} = @store.tail(loan_id)
        end

        test "append/2 rejects an entry whose prev_hash does not link to the tail" do
          {loan_id, entries} = seed_chain(2)
          tail = List.last(entries)

          forged =
            Factory.entry(%{
              loan_id: loan_id,
              sequence: tail.sequence + 1,
              prev_hash: Entry.genesis_prev_hash()
            })

          assert {:error, _} = @store.append(loan_id, forged)
          # atomicity: the failed append left nothing behind
          assert {:ok, ^tail} = @store.tail(loan_id)
          assert length(Enum.to_list(@store.stream(loan_id, []))) == 2
        end

        test "append/2 rejects a duplicate sequence" do
          {loan_id, entries} = seed_chain(3)
          assert {:error, _} = @store.append(loan_id, List.last(entries))
          assert :ok = @store.verify_chain(loan_id)
        end

        test "append/2 rejects an entry whose loan_id differs from the argument" do
          loan_id = Factory.unique_loan_id()
          entry = Factory.entry(%{loan_id: Factory.unique_loan_id()})
          assert {:error, _} = @store.append(loan_id, entry)
          assert {:ok, nil} = @store.tail(loan_id)
        end
      end

      describe "#{inspect(@store)} — security (tamper detection)" do
        test "mutating a persisted payload_hash mid-chain is detected by verify_chain/1" do
          {loan_id, _entries} = seed_chain(5)
          :ok = tamper_payload_hash!(loan_id, 2)
          assert {:error, {:tamper, 3}} = @store.verify_chain(loan_id)
        end
      end

      describe "#{inspect(@store)} — replay (round-trip property)" do
        property "any factory chain appends, round-trips identically, and verifies" do
          check all(entries <- Factory.chain_gen(15), max_runs: 25) do
            loan_id = hd(entries).loan_id

            for entry <- entries do
              assert {:ok, _} = @store.append(loan_id, entry)
            end

            assert Enum.to_list(@store.stream(loan_id, [])) == entries
            assert :ok = @store.verify_chain(loan_id)
            :ok = @store.wipe(loan_id)
          end
        end
      end

      describe "#{inspect(@store)} — isolation + wipe" do
        test "interleaved appends to two loans keep independent chains" do
          loan_a = Factory.unique_loan_id()
          loan_b = Factory.unique_loan_id()
          chain_a = Factory.chain(3, %{loan_id: loan_a})
          chain_b = Factory.chain(3, %{loan_id: loan_b})

          for {a, b} <- Enum.zip(chain_a, chain_b) do
            assert {:ok, _} = @store.append(loan_a, a)
            assert {:ok, _} = @store.append(loan_b, b)
          end

          assert :ok = @store.verify_chain(loan_a)
          assert :ok = @store.verify_chain(loan_b)
          assert Enum.to_list(@store.stream(loan_a, [])) == chain_a
          assert Enum.to_list(@store.stream(loan_b, [])) == chain_b
        end

        test "wipe/1 empties the loan's diary and allows a fresh genesis" do
          {loan_id, _} = seed_chain(4)
          assert :ok = @store.wipe(loan_id)
          assert {:ok, nil} = @store.tail(loan_id)
          assert {:ok, []} = @store.read_range(loan_id, 0, 10)

          fresh = Factory.entry(%{loan_id: loan_id})
          assert {:ok, 0} = @store.append(loan_id, fresh)
          assert :ok = @store.verify_chain(loan_id)
        end
      end
    end
  end
end
