defmodule LoanActor.Credo.LoopTagging do
  @moduledoc """
  Enforces constitution Principle II (three-loop harness): every `handle_call/3`,
  `handle_cast/2`, and `handle_info/2` clause in `LoanActor.Server` must carry a
  `@loop :reactive | :periodic | :planning` tag so each entrypoint is explicitly
  assigned to one of the three loops.

  FT-003 scaffold — registration + shape only. The AST walk lands in FT-020
  together with its test suite (`test/credo/loop_tagging_test.exs`).
  """

  use Credo.Check,
    base_priority: :high,
    category: :design,
    explanations: [
      check: """
      Every GenServer entrypoint in LoanActor.Server must be tagged with the loop
      it belongs to (`@loop :reactive`, `@loop :periodic`, or `@loop :planning`).
      Untagged handlers hide which loop owns a code path and defeat the
      three-loop harness audit.
      """
    ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    _issue_meta = IssueMeta.for(source_file, params)

    # FT-020 implements the AST walk. Until then the check reports no issues.
    []
  end
end
