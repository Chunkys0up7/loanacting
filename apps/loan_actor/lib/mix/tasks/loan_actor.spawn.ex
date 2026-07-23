defmodule Mix.Tasks.LoanActor.Spawn do
  @shortdoc "Spawn a supervised loan actor from the CLI"

  @moduledoc """
  Spawns a loan actor (FT-016/FT-017), per `quickstart.md`'s "Useful
  commands":

      mix loan_actor.spawn LOAN_ID

  Idempotent, same as `LoanActor.spawn/1` itself: an already-running
  `LOAN_ID` is reported without starting a duplicate. Prints the
  resulting state's status and version.
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    Application.put_env(:loan_actor, :start_http_endpoint, false)
    Mix.Task.run("app.start")

    case OptionParser.parse(argv, strict: []) do
      {[], [loan_id], []} -> do_spawn(loan_id)
      _ -> Mix.raise("usage: mix loan_actor.spawn LOAN_ID")
    end
  end

  defp do_spawn(loan_id) do
    case LoanActor.spawn(loan_id) do
      {:ok, _pid} ->
        {:ok, state} = LoanActor.state(loan_id)
        Mix.shell().info("loan #{loan_id} spawned (status: #{state.status}, version: #{state.version})")

      {:error, reason} ->
        Mix.raise("spawn failed for #{loan_id}: #{inspect(reason)}")
    end
  end
end
