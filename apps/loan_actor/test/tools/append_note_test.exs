defmodule LoanActor.Tools.AppendNoteTest do
  @moduledoc """
  FT-043 — `LoanActor.Tools.AppendNote`. Taxonomy: happy.

  The PII order-of-operations proof (real registry + real PIIGuard,
  requires `async: false` due to global Application-env mutation) lives
  separately in `test/tool/pii_integration_test.exs` — this shared-suite
  instantiation stays `async: true`.
  """

  use LoanActor.ToolSharedTests, tool: LoanActor.Tools.AppendNote

  alias LoanActor.Factory
  alias LoanActor.Tools.AppendNote

  def example_args, do: %{"text" => "document uploaded successfully"}

  describe "execute/2 — happy" do
    test "returns a note effect echoing the text" do
      assert {:ok, %{note: "hello"}} =
               AppendNote.execute(%{"text" => "hello"}, Factory.tool_context())
    end
  end
end
