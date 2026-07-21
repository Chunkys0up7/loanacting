defmodule LoanActor.Tools.VerifyDiaryChainTest do
  @moduledoc """
  FT-043 — `LoanActor.Tools.VerifyDiaryChain`. Taxonomy: happy.
  """

  use LoanActor.ToolSharedTests, tool: LoanActor.Tools.VerifyDiaryChain

  alias LoanActor.Factory
  alias LoanActor.Tools.VerifyDiaryChain

  def example_args, do: %{}

  describe "execute/2 — happy" do
    test "always returns the verify_chain intent effect, regardless of args" do
      assert {:ok, %{verify_chain: true}} =
               VerifyDiaryChain.execute(%{}, Factory.tool_context())
    end
  end
end
