defmodule LoanActor.Credo.LoopTagging do
  @moduledoc """
  Enforces constitution Principle II (three-loop harness, FT-020): every
  `handle_call/3`, `handle_cast/2`, and `handle_info/2` clause defined in
  `LoanActor.Server` must be immediately preceded by a `# loop:
  reactive|periodic|planning` comment, tagging which of the three loops
  it belongs to.

  Line-based, not AST-based: Elixir's standard AST discards comments
  entirely during parsing, so `SourceFile.lines/1`'s raw `{line_no, text}`
  pairs are the only way to see them. The tag must appear on the line
  immediately above the `def handle_*` line, or one line further back to
  allow an intervening `@impl ...` line (the established style in this
  codebase — see `server.ex`).

  Scope note: only files defining `LoanActor.Server` are checked — the
  task's literal wording scopes this to that one module, not every
  GenServer in the codebase.
  """

  use Credo.Check,
    base_priority: :high,
    category: :design,
    explanations: [
      check: """
      Every GenServer entrypoint (handle_call/3, handle_cast/2,
      handle_info/2) in LoanActor.Server must be tagged with a
      `# loop: reactive|periodic|planning` comment immediately above it
      (an intervening `@impl ...` line is allowed). Untagged handlers hide
      which loop owns a code path and defeat the three-loop harness audit.
      """
    ]

  alias Credo.SourceFile

  @target_module "LoanActor.Server"
  @handler_regex ~r/^def\s+(handle_call|handle_cast|handle_info)\s*\(/
  @tag_regex ~r/^#\s*loop:\s*(reactive|periodic|planning)\s*$/

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    if relevant_file?(source_file) do
      lines = SourceFile.lines(source_file)
      Enum.flat_map(lines, fn {line_no, text} -> check_line(text, line_no, lines, issue_meta) end)
    else
      []
    end
  end

  defp relevant_file?(source_file) do
    source_file
    |> SourceFile.source()
    |> String.contains?("defmodule #{@target_module}")
  end

  defp check_line(text, line_no, lines, issue_meta) do
    trimmed = String.trim(text)

    if Regex.match?(@handler_regex, trimmed) and not tagged?(line_no, lines) do
      [issue_for(issue_meta, line_no, trimmed)]
    else
      []
    end
  end

  defp tagged?(line_no, lines) do
    Enum.any?(1..2, fn back ->
      case List.keyfind(lines, line_no - back, 0) do
        {_, prev_text} -> Regex.match?(@tag_regex, String.trim(prev_text))
        nil -> false
      end
    end)
  end

  defp issue_for(issue_meta, line_no, trigger) do
    format_issue(issue_meta,
      message:
        "Handler is missing a `# loop: reactive|periodic|planning` tag comment immediately above it.",
      trigger: trigger,
      line_no: line_no
    )
  end
end
