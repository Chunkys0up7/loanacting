defmodule LoanActor.Tool.PIIIntegrationTest do
  @moduledoc """
  FT-043 — PII order-of-operations proved through the REAL
  `Tool.Registry` + REAL `LoanActor.PIIGuard` (not the FT-042 fixture
  guard), using `append_note` as the vehicle. Taxonomy: security.

  `async: false`: mutates global `Application` env for `:tools` /
  `:tool_pii_guard`.
  """

  use ExUnit.Case, async: false

  alias LoanActor.Factory
  alias LoanActor.Tool.Registry

  setup do
    previous_tools = Application.get_env(:loan_actor, :tools)
    previous_guard = Application.get_env(:loan_actor, :tool_pii_guard)
    Application.put_env(:loan_actor, :tools, [LoanActor.Tools.AppendNote])
    Application.put_env(:loan_actor, :tool_pii_guard, {LoanActor.PIIGuard, :apply})

    on_exit(fn ->
      restore(:tools, previous_tools)
      restore(:tool_pii_guard, previous_guard)
    end)

    :ok
  end

  defp restore(key, nil), do: Application.delete_env(:loan_actor, key)
  defp restore(key, value), do: Application.put_env(:loan_actor, key, value)

  test "a PII-shaped arg is hard-rejected before the tool ever executes" do
    assert {:error, {:pii_violation, [["text"]]}} =
             Registry.invoke("append_note", %{"text" => "my ssn is 123-45-6789"}, Factory.tool_context())
  end

  test "a clean arg reaches the tool and executes normally" do
    assert {:ok, %{note: "all clear"}} =
             Registry.invoke("append_note", %{"text" => "all clear"}, Factory.tool_context())
  end

  test "redacted_args/2 surfaces the same hard-gate rejection for the Server's would-be diary/emission path" do
    assert {:error, {:pii_violation, [["text"]]}} =
             Registry.redacted_args("append_note", %{"text" => "ssn 123-45-6789"})
  end
end
