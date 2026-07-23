# lib/credo/checks/ is excluded from elixirc_paths (Credo, a dev/test-only
# dep, loads custom checks itself via .credo.exs `requires` when `mix credo`
# runs). To unit-test the check directly we require its file explicitly.
Code.require_file("../../lib/credo/checks/no_llm.ex", __DIR__)

# This file's OWN literal string/alias fixtures (real Elixir string values
# and module names, not just ~S""" source-under-test) deliberately contain
# the exact tokens NoLLM looks for — that's what's under test. Same
# precedent as loop_tagging_test.exs's self-referential suppression.
# credo:disable-for-this-file LoanActor.Credo.NoLLM
defmodule LoanActor.Credo.NoLLMTest do
  @moduledoc """
  FT-021 — AST-based check for `LoanActor.Credo.NoLLM`.
  Taxonomy: happy / error / security. Fixtures are literal source strings
  (test-data-forge: deterministic, minimal, each proving one AST shape).
  """

  use ExUnit.Case, async: false

  alias Credo.SourceFile
  alias LoanActor.Credo.NoLLM, as: Check

  setup_all do
    {:ok, _apps} = Application.ensure_all_started(:credo)
    :ok
  end

  defp run(source) do
    source
    |> SourceFile.parse("fixture.ex")
    |> Check.run([])
  end

  describe "happy — no issues" do
    test "ordinary, unrelated code is never flagged" do
      source = ~S"""
      defmodule LoanActor.SomeModule do
        alias LoanActor.Diary.Entry

        def build(loan_id) do
          Entry.new(%{loan_id: loan_id})
        end
      end
      """

      assert run(source) == []
    end

    test "a module merely named similarly (not a forbidden top-level name) is not flagged" do
      source = ~S"""
      defmodule LoanActor.SomeModule do
        alias LoanActor.OpenAIish

        def call, do: OpenAIish.noop()
      end
      """

      assert run(source) == []
    end

    test "an unrelated URL is never flagged" do
      source = ~S"""
      defmodule LoanActor.SomeModule do
        def endpoint, do: "https://example.com/api/v1/loans"
      end
      """

      assert run(source) == []
    end
  end

  describe "error — forbidden module reference (security)" do
    test "an `alias` of a forbidden module is flagged" do
      source = ~S"""
      defmodule LoanActor.SomeModule do
        alias OpenAI
      end
      """

      assert [issue] = run(source)
      assert issue.check == Check
      assert issue.line_no == 2
    end

    test "a namespaced reference under a forbidden top-level module is flagged" do
      source = ~S"""
      defmodule LoanActor.SomeModule do
        def call, do: Anthropic.Messages.create(%{})
      end
      """

      assert [issue] = run(source)
      assert issue.line_no == 2
    end

    test "`use Bumblebee` is flagged (use/import/require all contain an alias node)" do
      source = ~S"""
      defmodule LoanActor.SomeModule do
        use Bumblebee
      end
      """

      assert [issue] = run(source)
      assert issue.line_no == 2
    end

    test "each of the three forbidden modules is independently flagged" do
      for name <- ~w(OpenAI Anthropic Bumblebee) do
        source = "defmodule LoanActor.X do\n  alias #{name}\nend\n"
        assert [issue] = run(source), "expected #{name} to be flagged"
        assert issue.line_no == 2
      end
    end

    test "multiple references in one file are all reported" do
      source = ~S"""
      defmodule LoanActor.SomeModule do
        alias OpenAI
        alias Anthropic
      end
      """

      assert [issue1, issue2] = run(source)
      assert issue1.line_no == 2
      assert issue2.line_no == 3
    end
  end

  describe "error — forbidden host string literal (security)" do
    test "a string literal referencing an LLM provider API host is flagged" do
      source = ~S"""
      defmodule LoanActor.SomeModule do
        def endpoint, do: "https://api.openai.com/v1/chat/completions"
      end
      """

      assert [issue] = run(source)
      assert issue.line_no == 2
    end

    test "each documented provider host pattern is independently flagged" do
      hosts = [
        "https://api.openai.com/v1/chat",
        "https://api.anthropic.com/v1/messages",
        "https://generativelanguage.googleapis.com/v1",
        "https://api.cohere.ai/v1/chat",
        "https://api.mistral.ai/v1/chat"
      ]

      for host <- hosts do
        source = "defmodule LoanActor.X do\n  def url, do: #{inspect(host)}\nend\n"
        assert [_issue] = run(source), "expected #{host} to be flagged"
      end
    end
  end
end
