defmodule LoanActor.Tools.RequestOperatorApprovalTest do
  @moduledoc """
  FT-043 — `LoanActor.Tools.RequestOperatorApproval`. Taxonomy: happy / boundary.
  """

  use LoanActor.ToolSharedTests, tool: LoanActor.Tools.RequestOperatorApproval

  alias LoanActor.Factory
  alias LoanActor.Tools.RequestOperatorApproval

  def example_args, do: %{"prompt" => "Approve the exception?", "options" => ["approve", "reject"]}

  describe "execute/2 — happy" do
    test "returns {:pending, ctx.invocation_id} — the ToolCallResult is deferred to respond_hitl" do
      ctx = Factory.tool_context(%{invocation_id: "inv-hitl-1"})
      assert {:pending, "inv-hitl-1"} = RequestOperatorApproval.execute(example_args(), ctx)
    end
  end

  describe "execute/2 — boundary" do
    test "a single-option list is accepted (schema places no minimum length)" do
      args = %{"prompt" => "Acknowledge?", "options" => ["ok"]}
      assert {:pending, _id} = RequestOperatorApproval.execute(args, Factory.tool_context())
    end
  end
end
