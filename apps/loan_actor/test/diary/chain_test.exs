defmodule LoanActor.Diary.ChainTest do
  use ExUnit.Case, async: true

  alias LoanActor.Diary.Chain
  alias LoanActor.Diary.Entry

  @loan "L-001"
  @ts ~U[2026-05-26 12:00:00Z]

  defp payload_hash(seed) do
    Chain.hash(<<seed::32>>)
  end

  defp build_chain(n) do
    Enum.reduce(0..(n - 1), {[], Entry.genesis_prev_hash()}, fn i, {acc, prev_hash} ->
      payload = payload_hash(i)

      entry =
        Entry.new(%{
          loan_id: @loan,
          sequence: i,
          timestamp: @ts,
          type: :spawned,
          actor: "system",
          payload_hash: payload,
          prev_hash: prev_hash
        })

      {[entry | acc], Chain.next_prev_hash(entry)}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  describe "hash/1 — happy" do
    test "produces a 32-byte digest" do
      assert byte_size(Chain.hash("anything")) == 32
    end

    test "is deterministic" do
      assert Chain.hash("a") == Chain.hash("a")
    end

    test "distinguishes inputs" do
      refute Chain.hash("a") == Chain.hash("b")
    end

    test "accepts iodata" do
      assert Chain.hash(["a", ["b"], "c"]) == Chain.hash("abc")
    end
  end

  describe "next_prev_hash/1 — happy" do
    test "returns 32 bytes" do
      entry = hd(build_chain(1))
      assert byte_size(Chain.next_prev_hash(entry)) == 32
    end

    test "differs for entries with different payload_hash" do
      [e0, e1] = build_chain(2)
      assert Chain.next_prev_hash(e0) != Chain.next_prev_hash(e1)
    end

    test "matches the next entry's prev_hash" do
      [e0, e1] = build_chain(2)
      assert e1.prev_hash == Chain.next_prev_hash(e0)
    end
  end

  describe "verify_pair/2 — happy" do
    test "ok for properly linked consecutive entries" do
      [e0, e1] = build_chain(2)
      assert :ok = Chain.verify_pair(e0, e1)
    end
  end

  describe "verify_pair/2 — error" do
    test "rejects mismatched prev_hash" do
      [e0, e1] = build_chain(2)
      tampered = %{e1 | prev_hash: <<0::256>>}
      assert {:error, :prev_hash_mismatch} = Chain.verify_pair(e0, tampered)
    end

    test "rejects sequence gap" do
      [e0, _, e2] = build_chain(3)
      assert {:error, :sequence_gap} = Chain.verify_pair(e0, e2)
    end

    test "rejects loan_id mismatch" do
      [e0, e1] = build_chain(2)
      other = %{e1 | loan_id: "L-OTHER"}
      assert {:error, :loan_id_mismatch} = Chain.verify_pair(e0, other)
    end
  end

  describe "verify/1 — happy" do
    test "ok for a one-entry chain (genesis only)" do
      assert :ok = Chain.verify(build_chain(1))
    end

    test "ok for a properly built chain of length 5" do
      assert :ok = Chain.verify(build_chain(5))
    end

    test "ok for a properly built chain of length 100" do
      assert :ok = Chain.verify(build_chain(100))
    end

    test "accepts a lazy stream (Enumerable, not just a list)" do
      stream = Stream.into(build_chain(10), [])
      assert :ok = Chain.verify(stream)
    end
  end

  describe "verify/1 — boundary" do
    test "empty chain returns :empty (not :ok)" do
      assert {:error, :empty} = Chain.verify([])
    end

    test "first entry must be sequence 0 with genesis prev_hash" do
      bad =
        Entry.new(%{
          loan_id: @loan,
          sequence: 1,
          timestamp: @ts,
          type: :spawned,
          actor: "system",
          payload_hash: payload_hash(0),
          prev_hash: Entry.genesis_prev_hash()
        })

      assert {:error, {:tamper, 0}} = Chain.verify([bad])
    end

    test "first entry with sequence 0 but non-genesis prev_hash is detected" do
      bad =
        Entry.new(%{
          loan_id: @loan,
          sequence: 0,
          timestamp: @ts,
          type: :spawned,
          actor: "system",
          payload_hash: payload_hash(0),
          prev_hash: <<1::256>>
        })

      assert {:error, {:tamper, 0}} = Chain.verify([bad])
    end
  end

  describe "verify/1 — security (tamper detection)" do
    test "verify alone does NOT detect tampering of the LAST entry's payload_hash" do
      # Documented limitation: verify/1 walks links between consecutive entries.
      # The last entry has no successor whose prev_hash would mismatch, so a
      # payload_hash tamper on the tail is undetectable until the chain is
      # extended. Callers that need eager last-entry verification must either
      # extend the chain (see next test) or persist a tail-pointer hash
      # separately. Foundation does the former on every append.
      entries = build_chain(5)
      [last | rest] = Enum.reverse(entries)
      tampered_chain = Enum.reverse([%{last | payload_hash: <<1::256>>} | rest])
      assert :ok = Chain.verify(tampered_chain)
    end

    test "extending the chain after a payload_hash tamper catches it" do
      entries = build_chain(5)
      [last | rest] = Enum.reverse(entries)
      tampered_last = %{last | payload_hash: <<1::256>>}
      tampered_chain = Enum.reverse([tampered_last | rest])

      # A real sixth entry, whose prev_hash was computed against the
      # ORIGINAL (non-tampered) `last` — i.e., what an honest appender saw.
      sixth =
        Entry.new(%{
          loan_id: @loan,
          sequence: 5,
          timestamp: @ts,
          type: :heartbeat,
          actor: "system",
          payload_hash: payload_hash(99),
          prev_hash: Chain.next_prev_hash(last)
        })

      # Now `verify` walks the chain including the sixth: the link between
      # tampered_last and sixth diverges because sixth.prev_hash was computed
      # over the original payload_hash, not the tampered one.
      assert {:error, {:tamper, 5}} = Chain.verify(tampered_chain ++ [sixth])
    end

    test "detects prev_hash tampering mid-chain" do
      entries = build_chain(5)
      # Tamper with entry at sequence 3
      tampered =
        Enum.map(entries, fn
          %Entry{sequence: 3} = e -> %{e | prev_hash: <<0::256>>}
          other -> other
        end)

      assert {:error, {:tamper, 3}} = Chain.verify(tampered)
    end

    test "detects sequence renumbering" do
      entries = build_chain(5)

      renumbered =
        Enum.map(entries, fn
          %Entry{sequence: 2} = e -> %{e | sequence: 7}
          other -> other
        end)

      assert {:error, {:tamper, _}} = Chain.verify(renumbered)
    end

    test "detects deletion of an entry mid-chain" do
      entries = build_chain(5)
      without_entry_2 = Enum.reject(entries, &(&1.sequence == 2))
      assert {:error, {:tamper, _}} = Chain.verify(without_entry_2)
    end

    test "detects insertion of a forged entry" do
      entries = build_chain(3)

      forged =
        Entry.new(%{
          loan_id: @loan,
          sequence: 1,
          timestamp: @ts,
          type: :spawned,
          actor: "attacker",
          payload_hash: payload_hash(999),
          prev_hash: <<0::256>>
        })

      [e0 | rest] = entries
      assert {:error, {:tamper, _}} = Chain.verify([e0, forged | rest])
    end
  end
end
