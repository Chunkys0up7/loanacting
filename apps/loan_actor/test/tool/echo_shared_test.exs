defmodule LoanActor.Tool.EchoSharedTest do
  @moduledoc """
  FT-042 — instantiates the shared tool contract suite against the Echo and
  Pending fixtures, proving the suite runs before real tools land (FT-043
  instantiates it per foundation tool).
  """

  use LoanActor.ToolSharedTests, tool: LoanActor.TestTools.Echo

  def example_args, do: %{"text" => "shared-suite", "level" => "warn"}
end

defmodule LoanActor.Tool.PendingSharedTest do
  @moduledoc false

  use LoanActor.ToolSharedTests, tool: LoanActor.TestTools.Pending

  def example_args, do: %{"id" => "req-shared"}
end
