defmodule LoanActor.Credo.NoLLM do
  @moduledoc """
  Enforces constitution Principle III (deterministic-first, FT-021): the
  foundation codebase contains zero LLM calls. Flags any AST reference,
  anywhere in a scanned file (`apps/loan_actor/lib/` per `.credo.exs`), to:

  - a forbidden top-level module alias (`OpenAI`, `Anthropic`, `Bumblebee`)
    — catches `alias`/`import`/`require`/`use` and bare calls alike, since
    all of them contain an `{:__aliases__, ...}` node somewhere in their AST;
  - a string literal matching a known LLM-provider API host pattern.

  Complemented by the coarse grep test FT-022
  (`test/llm_absence_test.exs`), which scans raw source text independent
  of this AST-based check — two different techniques catching the same
  invariant from different angles.

  Bare string literals carry no line number of their own in the AST; the
  walk threads the most recently seen enclosing node's line down through
  recursion as a best-effort line number for such leaves.
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

  alias Credo.SourceFile

  @forbidden_modules [:OpenAI, :Anthropic, :Bumblebee]
  @forbidden_host_regex ~r/api\.openai\.com|api\.anthropic\.com|generativelanguage\.googleapis\.com|api\.cohere\.ai|api\.mistral\.ai/i

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    ast = SourceFile.ast(source_file)
    walk(ast, issue_meta, nil)
  end

  defp walk({:__aliases__, meta, [first | _] = parts}, issue_meta, _line)
       when first in @forbidden_modules do
    [issue_for(issue_meta, meta[:line], "module reference #{Enum.join(parts, ".")}")]
  end

  defp walk(value, issue_meta, line) when is_binary(value) do
    if Regex.match?(@forbidden_host_regex, value) do
      [issue_for(issue_meta, line, "string literal referencing an LLM provider host")]
    else
      []
    end
  end

  defp walk({form, meta, args}, issue_meta, line) when is_list(args) do
    # `form` matters for remote calls: `Module.function(args)` is AST
    # `{{:., _, [module_alias, :function]}, meta, args}` — the module
    # reference lives INSIDE `form`, not `args`, so it must be walked too
    # (an atom `form`, e.g. `:def`/`:handle_call`, is harmless — it just
    # hits the leaf catch-all below and contributes no issues).
    new_line = meta[:line] || line
    walk(form, issue_meta, new_line) ++ collect(args, issue_meta, new_line)
  end

  defp walk(list, issue_meta, line) when is_list(list) do
    collect(list, issue_meta, line)
  end

  defp walk({a, b}, issue_meta, line) do
    walk(a, issue_meta, line) ++ walk(b, issue_meta, line)
  end

  defp walk(_leaf, _issue_meta, _line), do: []

  defp collect(nodes, issue_meta, line), do: Enum.flat_map(nodes, &walk(&1, issue_meta, line))

  defp issue_for(issue_meta, line_no, trigger) do
    format_issue(issue_meta,
      message:
        "Reference to an LLM provider (#{trigger}) is forbidden — foundation is deterministic-first (SC-009).",
      trigger: trigger,
      line_no: line_no
    )
  end
end
