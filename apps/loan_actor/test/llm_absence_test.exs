defmodule LoanActor.LLMAbsenceTest do
  @moduledoc """
  FT-022 — coarse grep test complementing FT-021's AST-based
  `LoanActor.Credo.NoLLM` check (two different techniques, same
  invariant). Verifies SC-009: zero references to LLM/OpenAI/Anthropic/
  completion in production code paths.

  Scans `lib/loan_actor/` and `lib/mix/` only — `lib/credo/` is
  deliberately excluded: that code IS the enforcement mechanism and
  legitimately lists these tokens as its own negative list (the same
  reason a profanity filter's source code containing the words it filters
  is not itself a violation).
  """

  use ExUnit.Case, async: true

  @scan_dirs [
    Path.join([__DIR__, "..", "lib", "loan_actor"]),
    Path.join([__DIR__, "..", "lib", "mix"])
  ]

  @forbidden_tokens ~w(llm openai anthropic completion)

  test "production code paths contain zero LLM/OpenAI/Anthropic/completion references (SC-009)" do
    violations =
      @scan_dirs
      |> Enum.flat_map(&Path.wildcard(Path.join(&1, "**/*.ex")))
      |> Enum.flat_map(&scan_file/1)

    assert violations == [], "forbidden token(s) found: #{inspect(violations)}"
  end

  test "the scan itself is not vacuous — it actually walks real files" do
    files =
      @scan_dirs
      |> Enum.flat_map(&Path.wildcard(Path.join(&1, "**/*.ex")))

    assert length(files) > 5
  end

  test "a synthetic forbidden token IS detected (proves the scan logic works)" do
    tmp = Path.join(System.tmp_dir!(), "llm_absence_fixture_#{System.unique_integer([:positive])}.ex")
    File.write!(tmp, "# this file mentions openai on purpose\n")

    on_exit(fn -> File.rm(tmp) end)

    violations = scan_file(tmp)
    assert [{^tmp, 1, "openai"}] = violations
  end

  defp scan_file(path) do
    path
    |> File.read!()
    |> String.split(~r/\r?\n/)
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} -> scan_line(path, line, line_no) end)
  end

  defp scan_line(path, line, line_no) do
    Enum.flat_map(@forbidden_tokens, fn token -> matches(path, line, line_no, token) end)
  end

  defp matches(path, line, line_no, token) do
    if Regex.match?(~r/\b#{token}\b/i, line) do
      [{path, line_no, token}]
    else
      []
    end
  end
end
