defmodule Mix.Tasks.LoanActor.DumpDiary do
  @shortdoc "Dump a loan's diary to a JSONL file"

  @moduledoc """
  Dumps every diary entry for `LOAN_ID` as one JSON object per line, per
  `quickstart.md`'s "Useful commands":

      mix loan_actor.dump_diary LOAN_ID --to dump.jsonl

  Reads directly from the configured `DiaryStore` — does not require a
  live actor to be running for `LOAN_ID`. The JSON shape is
  `LoanActor.Diary.File.encode!/1`'s own line format (loan_id, sequence,
  timestamp, type, actor, base64 payload_hash/payload_ref/prev_hash) —
  reused here as the dump format regardless of which store backend is
  actually configured, so a dump is portable and diffable either way.
  """

  use Mix.Task

  alias LoanActor.Diary.File, as: FileStore

  @impl Mix.Task
  def run(argv) do
    Application.put_env(:loan_actor, :start_http_endpoint, false)
    Mix.Task.run("app.start")

    case OptionParser.parse(argv, strict: [to: :string]) do
      {[to: path], [loan_id], []} -> do_dump(loan_id, path)
      {[], [_loan_id], []} -> Mix.raise("usage: mix loan_actor.dump_diary LOAN_ID --to FILE")
      _ -> Mix.raise("usage: mix loan_actor.dump_diary LOAN_ID --to FILE")
    end
  end

  defp do_dump(loan_id, path) do
    store = configured_store()
    :ok = store.init([])

    case Enum.to_list(store.stream(loan_id, [])) do
      [] ->
        Mix.raise("no diary found for #{loan_id}")

      entries ->
        contents = Enum.map_join(entries, "", &(FileStore.encode!(&1) <> "\n"))
        File.write!(path, contents)
        Mix.shell().info("dumped #{length(entries)} entries for #{loan_id} to #{path}")
    end
  end

  defp configured_store, do: Application.get_env(:loan_actor, :diary_store, LoanActor.Diary.Mnesia)
end
