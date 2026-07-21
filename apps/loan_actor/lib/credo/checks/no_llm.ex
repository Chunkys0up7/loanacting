defmodule LoanActor.Credo.NoLLM do
  @moduledoc """
  Enforces constitution Principle III (deterministic-first): the foundation
  codebase contains zero LLM calls. Flags any reference to known LLM client
  modules/HTTP hosts (OpenAI, Anthropic, `:httpc`/Req calls to model APIs)
  anywhere under `apps/loan_actor/lib/`.

  FT-003 scaffold — registration + shape only. The reference scan lands in
  FT-021 together with its test suite (`test/credo/no_llm_test.exs`).
  Complemented by the coarse grep test FT-022 (`test/llm_absence_test.exs`).
  """

  use Credo.Check,
    base_priority: :higher,
    category: :warning,
    explanations: [
      check: """
      Foundation ships with zero LLM call sites (SC-009). LLM escalation is a
      later intent (0003) and even then is reachable only through the dedicated
      escalation port. Any direct LLM reference is a constitution violation.
      """
    ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    _issue_meta = IssueMeta.for(source_file, params)

    # FT-021 implements the reference scan. Until then the check reports no issues.
    []
  end
end
