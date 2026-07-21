# A parameterized behaviour suite is inherently one long quote block.
# credo:disable-for-this-file Credo.Check.Refactor.LongQuoteBlocks
defmodule LoanActor.ToolSharedTests do
  @moduledoc """
  Parameterized contract suite every registered tool MUST pass (FT-042,
  `contracts/tool-behaviour.md`). Mirrors the `Diary.StoreSharedTests`
  pattern.

  Usage:

      defmodule LoanActor.Tools.SetGoalTest do
        use LoanActor.ToolSharedTests, tool: LoanActor.Tools.SetGoal

        def example_args, do: %{"description" => "obtain income doc"}
        # optional: def example_ctx, do: Factory.tool_context(%{loop: :periodic})
      end

  The using module MUST define `example_args/0` (schema-valid args) and MAY
  override `example_ctx/0`.
  """

  defmacro __using__(opts) do
    tool = Keyword.fetch!(opts, :tool)

    quote location: :keep do
      use ExUnit.Case, async: true

      alias LoanActor.Factory
      alias LoanActor.Tool.Spec

      @tool unquote(tool)

      def example_ctx, do: Factory.tool_context()
      defoverridable example_ctx: 0

      describe "#{inspect(@tool)} — tool contract" do
        test "spec/0 returns a %Tool.Spec{} that passes the construction cap" do
          spec = @tool.spec()
          assert %Spec{} = spec

          # Re-running new/1 proves the schema stays inside the subset.
          assert %Spec{} =
                   Spec.new(%{
                     name: spec.name,
                     description: spec.description,
                     parameters: spec.parameters
                   })
        end

        test "example_args/0 validate against the tool's own schema" do
          assert :ok = Spec.validate_args(@tool.spec(), example_args())
        end

        test "execute/2 returns a contract-shaped result" do
          assert result_shape_ok?(@tool.execute(example_args(), example_ctx()))
        end

        test "execute/2 is deterministic for identical args + ctx" do
          ctx = example_ctx()
          assert @tool.execute(example_args(), ctx) == @tool.execute(example_args(), ctx)
        end

        defp result_shape_ok?({:ok, effects}), do: is_map(effects)
        defp result_shape_ok?({:pending, id}), do: is_binary(id)
        defp result_shape_ok?({:error, _reason}), do: true
        defp result_shape_ok?(_other), do: false
      end
    end
  end
end
