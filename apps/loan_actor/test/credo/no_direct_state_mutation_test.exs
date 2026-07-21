# `lib/credo/checks/` is excluded from elixirc_paths (Credo, a dev/test-only
# dep, loads custom checks itself via .credo.exs `requires` when `mix credo`
# runs). To unit-test the check directly we require its file explicitly.
Code.require_file("../../lib/credo/checks/no_direct_state_mutation.ex", __DIR__)

defmodule LoanActor.Credo.NoDirectStateMutationTest do
  @moduledoc """
  FT-012 — AST walker for `LoanActor.Credo.NoDirectStateMutation`.
  Taxonomy: happy / error. Fixtures are literal source strings (test-data-forge:
  deterministic, minimal, each proving one specific AST shape) plus the real
  `state.ex` source as a regression pin.
  """

  use ExUnit.Case, async: false

  alias Credo.SourceFile
  alias LoanActor.Credo.NoDirectStateMutation, as: Check

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
    test "transition/2 inside LoanActor.State using %LoanActor.State{...|...} is allowed" do
      source = ~S"""
      defmodule LoanActor.State do
        defstruct [:status, :version]

        def transition(state, event_type) do
          %LoanActor.State{state | status: event_type, version: state.version + 1}
        end
      end
      """

      assert run(source) == []
    end

    test "the bare %{state | ...} form (no struct name) is never flagged, anywhere" do
      source = ~S"""
      defmodule LoanActor.SomeOtherModule do
        def bump(state) do
          %{state | version: state.version + 1}
        end
      end
      """

      assert run(source) == []
    end

    test "plain struct construction/pattern-match (no pipe) is never flagged" do
      source = ~S"""
      defmodule LoanActor.SomeOtherModule do
        def read(%LoanActor.State{status: status} = state) do
          {status, state}
        end

        def build(loan_id) do
          %LoanActor.State{loan_id: loan_id, status: :spawned}
        end
      end
      """

      assert run(source) == []
    end

    test "an unrelated struct's update syntax is never flagged" do
      source = ~S"""
      defmodule LoanActor.SomeOtherModule do
        def bump(goal) do
          %LoanActor.Goal{goal | status: :satisfied}
        end
      end
      """

      assert run(source) == []
    end

    test "the real apps/loan_actor/lib/loan_actor/state.ex has zero issues (regression pin)" do
      source = File.read!(Path.join([__DIR__, "..", "..", "lib", "loan_actor", "state.ex"]))
      assert run(source) == []
    end
  end

  describe "error — direct mutation outside transition/2" do
    test "fully-qualified struct update in an unrelated module is flagged" do
      source = ~S"""
      defmodule LoanActor.SomeOtherModule do
        def bump(state) do
          %LoanActor.State{state | version: state.version + 1}
        end
      end
      """

      assert [issue] = run(source)
      assert issue.check == Check
      assert issue.line_no == 3
    end

    test "a locally-aliased struct update in an unrelated module is flagged" do
      source = ~S"""
      defmodule LoanActor.SomeOtherModule do
        alias LoanActor.State

        def bump(state) do
          %State{state | version: state.version + 1}
        end
      end
      """

      assert [issue] = run(source)
      assert issue.line_no == 5
    end

    test "an aliased-with-`as:` struct update is flagged" do
      source = ~S"""
      defmodule LoanActor.SomeOtherModule do
        alias LoanActor.State, as: LoanState

        def bump(state) do
          %LoanState{state | version: state.version + 1}
        end
      end
      """

      assert [issue] = run(source)
      assert issue.line_no == 5
    end

    test "direct mutation inside LoanActor.State but OUTSIDE transition/2 is still flagged" do
      source = ~S"""
      defmodule LoanActor.State do
        defstruct [:status, :version]

        def sneaky_bump(state) do
          %LoanActor.State{state | version: state.version + 1}
        end

        def transition(state, event_type) do
          %LoanActor.State{state | status: event_type, version: state.version + 1}
        end
      end
      """

      assert [issue] = run(source)
      assert issue.line_no == 5
    end

    test "multiple violations in one file are all reported" do
      source = ~S"""
      defmodule LoanActor.SomeOtherModule do
        def a(state), do: %LoanActor.State{state | version: 1}
        def b(state), do: %LoanActor.State{state | version: 2}
      end
      """

      assert [issue1, issue2] = run(source)
      assert issue1.line_no == 2
      assert issue2.line_no == 3
    end

    test "a same-named struct aliased from a DIFFERENT module is not confused with LoanActor.State" do
      source = ~S"""
      defmodule LoanActor.SomeOtherModule do
        alias LoanActor.Diary.Entry, as: State

        def bump(entry) do
          %State{entry | sequence: entry.sequence + 1}
        end
      end
      """

      assert run(source) == []
    end
  end
end
