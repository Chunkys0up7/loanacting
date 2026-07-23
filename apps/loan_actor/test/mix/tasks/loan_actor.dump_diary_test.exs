defmodule Mix.Tasks.LoanActor.DumpDiaryTest do
  @moduledoc """
  FT-039 — `mix loan_actor.dump_diary`. Taxonomy: happy / error.
  """

  use ExUnit.Case, async: false

  alias LoanActor.Diary.File, as: FileStore
  alias LoanActor.Factory
  alias LoanActor.FileTestSupport

  @dir FileTestSupport.dir()

  setup_all do
    :ok = FileStore.init(dir: @dir)
    :ok
  end

  setup do
    Mix.shell(Mix.Shell.Process)
    Mix.Task.reenable("loan_actor.dump_diary")
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  defp tmp_out_path(name), do: Path.join(System.tmp_dir!(), name)

  describe "happy" do
    test "dumps every entry as one JSON line, matching Diary.File's own encode!/1 shape" do
      loan_id = Factory.unique_loan_id()
      entries = Factory.chain(3, %{loan_id: loan_id})
      for entry <- entries, do: {:ok, _} = FileStore.append(loan_id, entry)

      out_path = tmp_out_path("loan_actor_dump_diary_test_#{Factory.unique_loan_id()}.jsonl")
      on_exit(fn -> File.rm(out_path) end)

      Mix.Task.run("loan_actor.dump_diary", [loan_id, "--to", out_path])

      assert_received {:mix_shell, :info, [message]}
      assert message =~ "dumped 3 entries for #{loan_id} to #{out_path}"

      lines = out_path |> File.read!() |> String.split("\n", trim: true)
      assert length(lines) == 3

      decoded = Enum.map(lines, &Jason.decode!/1)
      assert Enum.map(decoded, & &1["sequence"]) == [0, 1, 2]
      assert Enum.all?(decoded, &(&1["loan_id"] == loan_id))

      # Same wire shape Diary.File.encode!/1 itself produces.
      [first_entry | _] = entries
      assert Jason.decode!(FileStore.encode!(first_entry)) == hd(decoded)
    end
  end

  describe "error" do
    test "no loan_id argument raises a usage error" do
      assert_raise Mix.Error, ~r/usage: mix loan_actor\.dump_diary LOAN_ID --to FILE/, fn ->
        Mix.Task.run("loan_actor.dump_diary", ["--to", tmp_out_path("unused.jsonl")])
      end
    end

    test "missing --to raises a usage error" do
      assert_raise Mix.Error, ~r/usage: mix loan_actor\.dump_diary LOAN_ID --to FILE/, fn ->
        Mix.Task.run("loan_actor.dump_diary", [Factory.unique_loan_id()])
      end
    end

    test "a loan with no diary raises" do
      assert_raise Mix.Error, ~r/no diary found for/, fn ->
        Mix.Task.run("loan_actor.dump_diary", [Factory.unique_loan_id(), "--to", tmp_out_path("unused2.jsonl")])
      end
    end
  end
end
