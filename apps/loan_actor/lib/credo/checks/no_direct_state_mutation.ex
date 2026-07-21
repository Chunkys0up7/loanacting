defmodule LoanActor.Credo.NoDirectStateMutation do
  @moduledoc """
  Enforces the data-model rule that `LoanActor.State.transition/2` is the only
  legal mutation entrypoint for `%LoanActor.State{}`: flags struct-update
  syntax (`%State{state | ...}`) and `struct/2`/`Map.put/3` writes against the
  state struct outside `LoanActor.State` itself.

  FT-003 scaffold — registration + shape only. The AST walk lands in FT-012
  together with its test suite (`test/credo/no_direct_state_mutation_test.exs`).
  """

  use Credo.Check,
    base_priority: :high,
    category: :design,
    explanations: [
      check: """
      Mutating %LoanActor.State{} anywhere except State.transition/2 bypasses
      the state machine, the diary append, and the version increment. All
      mutations must flow through transition/2.
      """
    ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    _issue_meta = IssueMeta.for(source_file, params)

    # FT-012 implements the AST walk. Until then the check reports no issues.
    []
  end
end
