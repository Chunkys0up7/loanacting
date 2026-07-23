defmodule Mix.Tasks.LoanActor.VerifyChain do
  @shortdoc "Tamper-detection scan of a loan's diary chain"

  @moduledoc """
  Verifies `LOAN_ID`'s diary hash chain (FT-007/FT-008's `verify_chain/1`),
  per `quickstart.md`'s "Useful commands":

      mix loan_actor.verify_chain LOAN_ID

  Reads directly from the configured `DiaryStore` — does not require a
  live actor to be running for `LOAN_ID`.
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    Application.put_env(:loan_actor, :start_http_endpoint, false)
    Mix.Task.run("app.start")

    case OptionParser.parse(argv, strict: []) do
      {[], [loan_id], []} -> do_verify(loan_id)
      _ -> Mix.raise("usage: mix loan_actor.verify_chain LOAN_ID")
    end
  end

  defp do_verify(loan_id) do
    store = configured_store()
    :ok = store.init([])

    case store.verify_chain(loan_id) do
      :ok ->
        Mix.shell().info("chain OK for #{loan_id}")

      {:error, {:tamper, sequence}} ->
        Mix.raise("tamper detected for #{loan_id} at sequence #{sequence}")

      {:error, reason} ->
        Mix.raise("verify_chain failed for #{loan_id}: #{inspect(reason)}")
    end
  end

  defp configured_store, do: Application.get_env(:loan_actor, :diary_store, LoanActor.Diary.Mnesia)
end
