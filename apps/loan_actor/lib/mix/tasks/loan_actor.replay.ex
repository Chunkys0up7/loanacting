defmodule Mix.Tasks.LoanActor.Replay do
  @shortdoc "Rebuild a loan's state from its diary and confirm it matches the live actor"

  @moduledoc """
  Rebuilds `LOAN_ID`'s state by folding `LoanActor.State.transition/2`
  over its diary (mirroring `LoanActor.Server.rehydrate/2` exactly — the
  same real-boot reconstruction, not a separate implementation), per
  `quickstart.md`'s "Useful commands":

      mix loan_actor.replay LOAN_ID

  If `LOAN_ID` is currently running, the replayed state is compared
  byte-for-byte (`last_heartbeat_at` excluded — its live value comes from
  a `DateTime.utc_now()` call the diary never stores verbatim, same
  caveat `server_property_test.exs`/`nfr_load_test.exs` already document)
  against the live actor's own in-memory state; a mismatch raises. If not
  running, the replayed state is reported without a live comparison —
  there is nothing to compare against, and this task does not spawn one
  itself (an operator asking to inspect a diary shouldn't have that
  inspection start a new supervised process as a side effect).
  """

  use Mix.Task

  alias LoanActor.State
  alias LoanActor.State.Model

  @impl Mix.Task
  def run(argv) do
    Application.put_env(:loan_actor, :start_http_endpoint, false)
    Mix.Task.run("app.start")

    case OptionParser.parse(argv, strict: []) do
      {[], [loan_id], []} -> do_replay(loan_id)
      _ -> Mix.raise("usage: mix loan_actor.replay LOAN_ID")
    end
  end

  defp do_replay(loan_id) do
    store = configured_store()
    :ok = store.init([])

    case Enum.to_list(store.stream(loan_id, [])) do
      [] -> Mix.raise("no diary found for #{loan_id}")
      entries -> report(loan_id, replay(loan_id, entries), length(entries))
    end
  rescue
    e in LoanActor.IllegalTransitionError ->
      Mix.raise("replay failed for #{loan_id}: #{Exception.message(e)}")
  end

  defp replay(loan_id, entries) do
    event_types = Model.transition_driving_event_types()

    Enum.reduce(entries, State.new(%{loan_id: loan_id}), fn entry, acc ->
      cond do
        MapSet.member?(event_types, entry.type) -> State.transition(acc, entry.type)
        entry.type == :heartbeat -> State.record_heartbeat(acc, entry.timestamp)
        true -> acc
      end
    end)
  end

  defp report(loan_id, replayed, entry_count) do
    case LoanActor.whereis(loan_id) do
      nil ->
        Mix.shell().info(
          "replayed #{entry_count} entries for #{loan_id} -> status: #{replayed.status}, version: #{replayed.version} " <>
            "(no live actor running — nothing to compare against)"
        )

      _pid ->
        {:ok, live} = LoanActor.state(loan_id)

        if same_state?(replayed, live) do
          Mix.shell().info(
            "replay OK for #{loan_id} — byte-equal to the live actor's state (#{entry_count} entries, status: #{replayed.status})"
          )
        else
          Mix.raise("replay MISMATCH for #{loan_id}: replayed=#{inspect(replayed)} live=#{inspect(live)}")
        end
    end
  end

  defp same_state?(replayed, live) do
    %{replayed | last_heartbeat_at: nil} == %{live | last_heartbeat_at: nil}
  end

  defp configured_store, do: Application.get_env(:loan_actor, :diary_store, LoanActor.Diary.Mnesia)
end
