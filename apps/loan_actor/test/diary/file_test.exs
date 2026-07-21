defmodule LoanActor.Diary.FileTest do
  @moduledoc """
  FT-007 — `LoanActor.Diary.File` against the shared `DiaryStore` suite
  (contract/happy/boundary/error/tamper/replay/isolation) plus file-specific
  cases: torn-write repair (error), codec round-trip (replay), path safety
  (security), and the large-diary load test (boundary, tagged `:load`).

  Backing store: real files under the OS tmp dir — never the repo's
  `priv/diary_files`, never anything production-shaped (test-data-forge
  isolation rules).
  """

  use LoanActor.Diary.StoreSharedTests, store: LoanActor.Diary.File

  alias LoanActor.Diary.File, as: FileStore

  @dir Path.join(System.tmp_dir!(), "loan_actor_diary_file_test")

  def store_opts, do: [dir: @dir]

  # Shared-suite tamper hook: rewrite the persisted line's payload_hash.
  def tamper_payload_hash!(loan_id, sequence) do
    path = Path.join(@dir, "#{loan_id}.jsonl")

    tampered =
      path
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map_join("", fn line ->
        map = Jason.decode!(line)

        line =
          if map["sequence"] == sequence do
            Jason.encode!(%{map | "payload_hash" => Base.encode64(<<1::256>>)})
          else
            line
          end

        line <> "\n"
      end)

    File.write!(path, tampered)
    :ok
  end

  describe "torn-write repair — error/atomicity" do
    test "a partial trailing line (crash mid-append) is truncated, not surfaced" do
      loan_id = Factory.unique_loan_id()
      entries = Factory.chain(3, %{loan_id: loan_id})
      for entry <- entries, do: {:ok, _} = FileStore.append(loan_id, entry)

      # Simulate a crash mid-write: garbage with no trailing newline.
      path = Path.join(@dir, "#{loan_id}.jsonl")
      File.write!(path, ~s({"loan_id":"#{loan_id}","sequence":3,"trunc), [:append])

      tail = List.last(entries)
      assert {:ok, ^tail} = FileStore.tail(loan_id)

      next = Factory.next_entry(tail)
      assert {:ok, 3} = FileStore.append(loan_id, next)
      assert :ok = FileStore.verify_chain(loan_id)
      assert length(Enum.to_list(FileStore.stream(loan_id, []))) == 4
    end
  end

  describe "codec — replay" do
    test "encode!/decode! round-trips every field including payload_ref and microseconds" do
      entry =
        Factory.entry(%{
          loan_id: "L-CODEC",
          timestamp: ~U[2026-07-21 13:37:42.123456Z],
          type: :operator_approval_granted,
          actor: "op-77",
          payload_ref: <<7, 8, 9>>
        })

      assert entry |> FileStore.encode!() |> FileStore.decode!() == entry
    end

    test "decode!/1 refuses unknown entry types instead of minting atoms" do
      line =
        Factory.entry()
        |> FileStore.encode!()
        |> Jason.decode!()
        |> Map.put("type", "definitely_not_an_existing_atom_xyzzy")
        |> Jason.encode!()

      assert_raise ArgumentError, fn -> FileStore.decode!(line) end
    end
  end

  describe "path safety — security" do
    test "loan ids containing path separators are rejected" do
      for bad <- ["../escape", "a/b", "a\\b", ".."] do
        entry = Factory.entry(%{loan_id: bad})
        assert_raise ArgumentError, fn -> FileStore.append(bad, entry) end
      end
    end
  end

  describe "large diary — boundary (load)" do
    # Size is spec-pinned at 100k (tasks.md FT-007); override locally with
    # LOAN_DIARY_LOAD_SIZE for a quicker sanity run.
    @tag :load
    @tag timeout: :infinity
    test "a 100k-entry diary appends, streams, and verifies" do
      size = String.to_integer(System.get_env("LOAN_DIARY_LOAD_SIZE", "100000"))
      loan_id = Factory.unique_loan_id()

      final_tail =
        Enum.reduce(1..size, nil, fn _i, tail ->
          entry = Factory.next_entry(tail, if(tail, do: %{}, else: %{loan_id: loan_id}))
          {:ok, _} = FileStore.append(loan_id, entry)
          entry
        end)

      assert {:ok, ^final_tail} = FileStore.tail(loan_id)
      assert Enum.count(FileStore.stream(loan_id, [])) == size
      assert :ok = FileStore.verify_chain(loan_id)
      :ok = FileStore.wipe(loan_id)
    end
  end
end
