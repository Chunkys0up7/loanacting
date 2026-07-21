defmodule Mix.Tasks.LoanActor.InitMnesia do
  @shortdoc "Create the Mnesia schema + loan_diary table on this node"

  @moduledoc """
  Initializes the Mnesia diary store (FT-008): creates the on-disk schema and
  the `loan_diary` table on the local node, idempotently.

      mix loan_actor.init_mnesia
      mix loan_actor.init_mnesia --dir path/to/mnesia_data

  Without `--dir`, Mnesia's configured directory (app env `:mnesia, :dir`, or
  its `Mnesia.<node>` default) is used.
  """

  use Mix.Task

  alias LoanActor.Diary.Mnesia

  @impl Mix.Task
  def run(argv) do
    {opts, _rest, _invalid} = OptionParser.parse(argv, strict: [dir: :string])

    init_opts = if dir = opts[:dir], do: [dir: dir], else: []

    case Mnesia.init(init_opts) do
      :ok ->
        Mix.shell().info("mnesia diary store ready (dir: #{:mnesia.system_info(:directory)})")

      {:error, reason} ->
        Mix.raise("mnesia init failed: #{inspect(reason)}")
    end
  end
end
