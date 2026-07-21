defmodule LoanActor.Tools.RequestDocumentTest do
  @moduledoc """
  FT-043 — `LoanActor.Tools.RequestDocument`. Taxonomy: happy / error.
  """

  use LoanActor.ToolSharedTests, tool: LoanActor.Tools.RequestDocument

  alias LoanActor.Factory
  alias LoanActor.Tool.Spec
  alias LoanActor.Tools.RequestDocument

  def example_args, do: %{"doc_type" => "income"}

  describe "execute/2 — happy" do
    test "returns a request effect echoing the doc_type" do
      assert {:ok, %{request: %{"doc_type" => "income"}}} =
               RequestDocument.execute(example_args(), Factory.tool_context())
    end

    test "every documented doc_type is accepted" do
      for doc_type <- ["income", "identity", "appraisal"] do
        assert {:ok, %{request: %{"doc_type" => ^doc_type}}} =
                 RequestDocument.execute(%{"doc_type" => doc_type}, Factory.tool_context())
      end
    end
  end

  describe "spec/0 — error (schema enum enforcement)" do
    test "an undocumented doc_type fails args validation" do
      spec = RequestDocument.spec()
      assert {:error, {:invalid_args, _}} = Spec.validate_args(spec, %{"doc_type" => "selfie"})
    end
  end
end
