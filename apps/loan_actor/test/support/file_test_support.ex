defmodule LoanActor.FileTestSupport do
  @moduledoc """
  Shared File-store test directory. `LoanActor.Diary.File`'s configured
  directory is a single global (`Application` env, mirroring how Mnesia's
  directory is tracked) — every test module that calls
  `LoanActor.Diary.File.init/1` with its own `:dir` MUST point at the SAME
  directory, or whichever call runs (or a still-running background
  process outliving its own test module later touches the store)
  silently starts reading/writing the wrong path.

  Found the hard way (FT-018): before periodic-loop heartbeats existed,
  every File-store operation happened synchronously within a bounded test,
  so each test file's own directory was harmless — each finished before
  the next file's `setup_all` repointed the global dir. Heartbeat timers
  are the first thing to run in the background *after* their owning test
  file's execution window ends, exposing the latent collision: a later
  file's `setup_all` repoints `:diary_dir` out from under an earlier
  file's still-heartbeating `LoanActor.Server` process, whose next
  `store.tail/1` call then reads an empty (wrong) directory.

  Used by `test/diary/file_test.exs`, `test/replay_test.exs`,
  `test/server_reactive_test.exs`, `test/server_heartbeat_test.exs`.
  """

  @dir Path.join(System.tmp_dir!(), "loan_actor_shared_file_test")

  @spec dir() :: String.t()
  def dir, do: @dir
end
