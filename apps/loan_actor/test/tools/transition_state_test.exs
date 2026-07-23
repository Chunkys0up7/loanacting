defmodule LoanActor.Tools.TransitionStateTest do
  @moduledoc """
  FT-043 — `LoanActor.Tools.TransitionState`. Taxonomy: happy / error / boundary.
  """

  use LoanActor.ToolSharedTests, tool: LoanActor.Tools.TransitionState

  alias LoanActor.Factory
  alias LoanActor.State.Model
  alias LoanActor.Tool.Spec
  alias LoanActor.Tools.TransitionState

  def example_args, do: %{"event_type" => "goal_set"}
  def example_ctx, do: Factory.tool_context(%{state: %{status: :spawned}})

  describe "execute/2 — happy" do
    test "a legal event_type from the current status returns a transition effect" do
      assert {:ok, %{transition: :goal_set}} =
               TransitionState.execute(example_args(), example_ctx())
    end
  end

  describe "execute/2 — error" do
    test "an illegal event_type from the current status is rejected, matching the documented shape" do
      ctx = Factory.tool_context(%{state: %{status: :spawned}})

      assert {:error, {:illegal_transition, :spawned, :complete}} =
               TransitionState.execute(%{"event_type" => "complete"}, ctx)
    end

    test "every documented event_type is a valid enum value (spec/0 accepts it)" do
      spec = TransitionState.spec()

      for event_type <- Model.event_types() do
        assert :ok = Spec.validate_args(spec, %{"event_type" => Atom.to_string(event_type)})
      end
    end
  end

  describe "execute/2 — boundary (every documented edge)" do
    test "each of the seven documented edges is legal from its origin status" do
      for {from, event_type, _to} <- Model.edges() do
        ctx = Factory.tool_context(%{state: %{status: from}})
        args = %{"event_type" => Atom.to_string(event_type)}
        assert {:ok, %{transition: ^event_type}} = TransitionState.execute(args, ctx)
      end
    end
  end
end
