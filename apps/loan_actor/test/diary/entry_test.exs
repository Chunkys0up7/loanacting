defmodule LoanActor.Diary.EntryTest do
  use ExUnit.Case, async: true

  alias LoanActor.Diary.Entry

  @hash <<0::size(31)-unit(8), 1>>
  @genesis Entry.genesis_prev_hash()

  describe "new/1 — happy" do
    test "constructs a valid entry from a map" do
      entry =
        Entry.new(%{
          loan_id: "L-001",
          sequence: 0,
          timestamp: ~U[2026-05-26 12:00:00Z],
          type: :spawned,
          actor: "system",
          payload_hash: @hash,
          prev_hash: @genesis
        })

      assert %Entry{loan_id: "L-001", sequence: 0, type: :spawned} = entry
      assert entry.payload_ref == nil
    end

    test "accepts a keyword list" do
      assert %Entry{} =
               Entry.new(
                 loan_id: "L-002",
                 sequence: 7,
                 timestamp: ~U[2026-05-26 12:00:00Z],
                 type: :document_uploaded,
                 actor: "op-1",
                 payload_hash: @hash,
                 prev_hash: @hash
               )
    end

    test "accepts a non-nil payload_ref" do
      ref = "vault://abc"

      entry =
        Entry.new(%{
          loan_id: "L-003",
          sequence: 1,
          timestamp: ~U[2026-05-26 12:00:00Z],
          type: :goal_set,
          actor: "system",
          payload_hash: @hash,
          payload_ref: ref,
          prev_hash: @hash
        })

      assert entry.payload_ref == ref
    end
  end

  describe "new/1 — boundary" do
    test "sequence 0 is permitted (genesis entry)" do
      assert %Entry{sequence: 0} =
               Entry.new(%{
                 loan_id: "L-001",
                 sequence: 0,
                 timestamp: ~U[2026-05-26 12:00:00Z],
                 type: :spawned,
                 actor: "system",
                 payload_hash: @hash,
                 prev_hash: @genesis
               })
    end

    test "very large sequence is permitted" do
      big = 1_000_000_000

      assert %Entry{sequence: ^big} =
               Entry.new(%{
                 loan_id: "L-001",
                 sequence: big,
                 timestamp: ~U[2026-05-26 12:00:00Z],
                 type: :heartbeat,
                 actor: "system",
                 payload_hash: @hash,
                 prev_hash: @hash
               })
    end

    test "genesis_prev_hash is 32 zero bytes" do
      gen = Entry.genesis_prev_hash()
      assert byte_size(gen) == 32
      assert gen == <<0::256>>
    end

    test "hash_size is 32" do
      assert Entry.hash_size() == 32
    end
  end

  describe "new/1 — error" do
    test "rejects negative sequence" do
      assert_raise ArgumentError, ~r/sequence/, fn ->
        Entry.new(%{
          loan_id: "L-001",
          sequence: -1,
          timestamp: ~U[2026-05-26 12:00:00Z],
          type: :spawned,
          actor: "system",
          payload_hash: @hash,
          prev_hash: @genesis
        })
      end
    end

    test "rejects empty loan_id" do
      assert_raise ArgumentError, ~r/loan_id/, fn ->
        Entry.new(%{
          loan_id: "",
          sequence: 0,
          timestamp: ~U[2026-05-26 12:00:00Z],
          type: :spawned,
          actor: "system",
          payload_hash: @hash,
          prev_hash: @genesis
        })
      end
    end

    test "rejects non-binary loan_id" do
      assert_raise ArgumentError, ~r/loan_id/, fn ->
        Entry.new(%{
          loan_id: :not_a_string,
          sequence: 0,
          timestamp: ~U[2026-05-26 12:00:00Z],
          type: :spawned,
          actor: "system",
          payload_hash: @hash,
          prev_hash: @genesis
        })
      end
    end

    test "rejects non-DateTime timestamp" do
      assert_raise ArgumentError, ~r/timestamp/, fn ->
        Entry.new(%{
          loan_id: "L-001",
          sequence: 0,
          timestamp: "2026-05-26",
          type: :spawned,
          actor: "system",
          payload_hash: @hash,
          prev_hash: @genesis
        })
      end
    end

    test "rejects non-atom type" do
      assert_raise ArgumentError, ~r/type/, fn ->
        Entry.new(%{
          loan_id: "L-001",
          sequence: 0,
          timestamp: ~U[2026-05-26 12:00:00Z],
          type: "spawned",
          actor: "system",
          payload_hash: @hash,
          prev_hash: @genesis
        })
      end
    end

    test "rejects empty actor" do
      assert_raise ArgumentError, ~r/actor/, fn ->
        Entry.new(%{
          loan_id: "L-001",
          sequence: 0,
          timestamp: ~U[2026-05-26 12:00:00Z],
          type: :spawned,
          actor: "",
          payload_hash: @hash,
          prev_hash: @genesis
        })
      end
    end

    test "rejects payload_hash of wrong size" do
      bad = <<0, 1, 2>>

      assert_raise ArgumentError, ~r/payload_hash/, fn ->
        Entry.new(%{
          loan_id: "L-001",
          sequence: 0,
          timestamp: ~U[2026-05-26 12:00:00Z],
          type: :spawned,
          actor: "system",
          payload_hash: bad,
          prev_hash: @genesis
        })
      end
    end

    test "rejects prev_hash of wrong size" do
      bad = <<0, 1, 2>>

      assert_raise ArgumentError, ~r/prev_hash/, fn ->
        Entry.new(%{
          loan_id: "L-001",
          sequence: 0,
          timestamp: ~U[2026-05-26 12:00:00Z],
          type: :spawned,
          actor: "system",
          payload_hash: @hash,
          prev_hash: bad
        })
      end
    end

    test "rejects non-binary payload_ref" do
      assert_raise ArgumentError, ~r/payload_ref/, fn ->
        Entry.new(%{
          loan_id: "L-001",
          sequence: 0,
          timestamp: ~U[2026-05-26 12:00:00Z],
          type: :spawned,
          actor: "system",
          payload_hash: @hash,
          payload_ref: 42,
          prev_hash: @genesis
        })
      end
    end

    test "raises KeyError on missing required field" do
      assert_raise KeyError, fn ->
        Entry.new(%{
          # missing loan_id
          sequence: 0,
          timestamp: ~U[2026-05-26 12:00:00Z],
          type: :spawned,
          actor: "system",
          payload_hash: @hash,
          prev_hash: @genesis
        })
      end
    end
  end

  describe "entry_id/1" do
    test "returns the composite {loan_id, sequence} key" do
      entry =
        Entry.new(%{
          loan_id: "L-XYZ",
          sequence: 42,
          timestamp: ~U[2026-05-26 12:00:00Z],
          type: :heartbeat,
          actor: "system",
          payload_hash: @hash,
          prev_hash: @hash
        })

      assert Entry.entry_id(entry) == {"L-XYZ", 42}
    end
  end
end
