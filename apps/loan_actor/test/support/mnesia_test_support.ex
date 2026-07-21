defmodule LoanActor.MnesiaTestSupport do
  @moduledoc """
  Shared Mnesia test directory (FT-015). Mnesia is a single node-wide
  database — every test module that calls `LoanActor.Diary.Mnesia.init/1`
  MUST point at the SAME directory, or whichever call runs second stops and
  restarts Mnesia against a different path, discarding whatever the first
  test module already set up (tables, data). Both `test/diary/mnesia_test.exs`
  (FT-008) and `test/idempotency_test.exs` (FT-015) use this constant.
  """

  @dir Path.join(System.tmp_dir!(), "loan_actor_shared_mnesia_test")

  @spec dir() :: String.t()
  def dir, do: @dir
end
