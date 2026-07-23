# lib/credo/checks/ is excluded from elixirc_paths (Credo, a dev/test-only
# dep, loads custom checks itself via .credo.exs `requires` when `mix credo`
# runs). To unit-test the check directly we require its file explicitly.
Code.require_file("../../lib/credo/checks/loop_tagging.ex", __DIR__)

# LoopTagging scans RAW TEXT lines (comments aren't in the AST at all), so
# it can't distinguish this file's literal ~S""" fixture strings — which
# deliberately contain "defmodule LoanActor.Server" and handler-shaped
# lines, since that's exactly what's under test — from real code. Same
# precedent as diary_store_shared.ex's LongQuoteBlocks suppression: a test
# file legitimately triggering the pattern its own tests exercise.
# credo:disable-for-this-file LoanActor.Credo.LoopTagging
defmodule LoanActor.Credo.LoopTaggingTest do
  @moduledoc """
  FT-020 — line-based check for `LoanActor.Credo.LoopTagging`.
  Taxonomy: happy / error. Fixtures are literal source strings
  (test-data-forge: deterministic, minimal, each proving one AST/line shape).
  """

  use ExUnit.Case, async: false

  alias Credo.SourceFile
  alias LoanActor.Credo.LoopTagging, as: Check

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
    test "a tagged handle_call is allowed" do
      source = ~S"""
      defmodule LoanActor.Server do
        # loop: reactive
        @impl GenServer
        def handle_call(:foo, _from, state), do: {:reply, :ok, state}
      end
      """

      assert run(source) == []
    end

    test "a tag with no intervening @impl line is also allowed (one line back)" do
      source = ~S"""
      defmodule LoanActor.Server do
        # loop: periodic
        def handle_info(:heartbeat, state), do: {:noreply, state}
      end
      """

      assert run(source) == []
    end

    test "handle_cast is also covered and correctly allowed when tagged" do
      source = ~S"""
      defmodule LoanActor.Server do
        # loop: planning
        @impl GenServer
        def handle_cast(:plan, state), do: {:noreply, state}
      end
      """

      assert run(source) == []
    end

    test "handlers in an UNRELATED module are never checked, tagged or not" do
      source = ~S"""
      defmodule LoanActor.SomeOtherServer do
        def handle_call(:foo, _from, state), do: {:reply, :ok, state}
        def handle_info(:bar, state), do: {:noreply, state}
      end
      """

      assert run(source) == []
    end

    test "the real apps/loan_actor/lib/loan_actor/server.ex has zero issues (regression pin)" do
      source = File.read!(Path.join([__DIR__, "..", "..", "lib", "loan_actor", "server.ex"]))
      assert run(source) == []
    end
  end

  describe "error — untagged handler in LoanActor.Server" do
    test "an untagged handle_call is flagged" do
      source = ~S"""
      defmodule LoanActor.Server do
        @impl GenServer
        def handle_call(:foo, _from, state), do: {:reply, :ok, state}
      end
      """

      assert [issue] = run(source)
      assert issue.check == Check
      assert issue.line_no == 3
    end

    test "an untagged handle_info is flagged" do
      source = ~S"""
      defmodule LoanActor.Server do
        def handle_info(:heartbeat, state), do: {:noreply, state}
      end
      """

      assert [issue] = run(source)
      assert issue.line_no == 2
    end

    test "an untagged handle_cast is flagged" do
      source = ~S"""
      defmodule LoanActor.Server do
        def handle_cast(:plan, state), do: {:noreply, state}
      end
      """

      assert [issue] = run(source)
      assert issue.line_no == 2
    end

    test "a tag more than two lines above does not count" do
      source = ~S"""
      defmodule LoanActor.Server do
        # loop: reactive
        # an unrelated comment line in between
        @impl GenServer
        def handle_call(:foo, _from, state), do: {:reply, :ok, state}
      end
      """

      assert [issue] = run(source)
      assert issue.line_no == 5
    end

    test "multiple untagged handlers are all reported" do
      source = ~S"""
      defmodule LoanActor.Server do
        def handle_call(:a, _from, state), do: {:reply, :ok, state}
        def handle_call(:b, _from, state), do: {:reply, :ok, state}
      end
      """

      assert [issue1, issue2] = run(source)
      assert issue1.line_no == 2
      assert issue2.line_no == 3
    end

    test "an invalid tag value (not one of the three loops) does not satisfy the check" do
      source = ~S"""
      defmodule LoanActor.Server do
        # loop: something_else
        def handle_call(:foo, _from, state), do: {:reply, :ok, state}
      end
      """

      assert [issue] = run(source)
      assert issue.line_no == 3
    end
  end
end
