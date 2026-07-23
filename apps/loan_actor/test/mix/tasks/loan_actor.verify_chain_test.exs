defmodule Mix.Tasks.LoanActor.VerifyChainTest do
  @moduledoc """
  FT-039 — `mix loan_actor.verify_chain`. Taxonomy: happy / error / security (tamper).
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
    Mix.Task.reenable("loan_actor.verify_chain")
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  describe "happy" do
    test "an untampered chain reports OK" do
      loan_id = Factory.unique_loan_id()
      for entry <- Factory.chain(5, %{loan_id: loan_id}), do: {:ok, _} = FileStore.append(loan_id, entry)

      Mix.Task.run("loan_actor.verify_chain", [loan_id])

      assert_received {:mix_shell, :info, [message]}
      assert message =~ "chain OK for #{loan_id}"
    end
  end

  describe "security — tamper detection" do
    test "a tampered payload_hash raises reporting the offending sequence" do
      loan_id = Factory.unique_loan_id()
      for entry <- Factory.chain(4, %{loan_id: loan_id}), do: {:ok, _} = FileStore.append(loan_id, entry)
      tamper_payload_hash!(loan_id, 1)

      assert_raise Mix.Error, ~r/tamper detected for #{loan_id} at sequence 2/, fn ->
        Mix.Task.run("loan_actor.verify_chain", [loan_id])
      end
    end
  end

  describe "error" do
    test "no loan_id argument raises a usage error" do
      assert_raise Mix.Error, ~r/usage: mix loan_actor\.verify_chain LOAN_ID/, fn ->
        Mix.Task.run("loan_actor.verify_chain", [])
      end
    end
  end

  # Mirrors diary/file_test.exs's own shared-suite tamper hook.
  defp tamper_payload_hash!(loan_id, sequence) do
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
  end
end
