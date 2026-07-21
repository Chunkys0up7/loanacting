defmodule LoanActor.Tool.RegistryTest do
  @moduledoc """
  FT-042 — config-driven registry: resolution, invocation path (guard →
  validate → execute), telemetry, crash-rescue, PII order-of-operations.
  Taxonomy: happy / error / contract / security. Fixture tools from
  `LoanActor.TestTools` (test-data-forge).
  """

  # App-env mutation (tools list, pii guard) is global — never async.
  use ExUnit.Case, async: false

  alias LoanActor.Factory
  alias LoanActor.TestTools
  alias LoanActor.Tool.Registry

  setup do
    previous_tools = Application.get_env(:loan_actor, :tools)
    previous_guard = Application.get_env(:loan_actor, :tool_pii_guard)
    Application.put_env(:loan_actor, :tools, TestTools.all())

    on_exit(fn ->
      restore_env(:tools, previous_tools)
      restore_env(:tool_pii_guard, previous_guard)
    end)

    :ok
  end

  defp restore_env(key, nil), do: Application.delete_env(:loan_actor, key)
  defp restore_env(key, value), do: Application.put_env(:loan_actor, key, value)

  describe "list/0 + fetch/1 — happy" do
    test "lists one spec per configured module" do
      names = Registry.list() |> Enum.map(& &1.name)
      assert names == ["echo_note", "always_fails", "raises", "pending_tool", "bad_return"]
    end

    test "fetch resolves a name to its module" do
      assert {:ok, TestTools.Echo} = Registry.fetch("echo_note")
    end
  end

  describe "fetch/1 + invoke/3 — error" do
    test "unknown tool" do
      assert {:error, :unknown_tool} = Registry.fetch("nope")
      assert {:error, :unknown_tool} = Registry.invoke("nope", %{}, Factory.tool_context())
    end

    test "schema-invalid args are rejected before execution" do
      assert {:error, {:invalid_args, errors}} =
               Registry.invoke("echo_note", %{}, Factory.tool_context())

      assert [{["text"], :missing_required}] = errors
    end

    test "a tool's own error passes through" do
      assert {:error, :always_fails} =
               Registry.invoke("always_fails", %{}, Factory.tool_context())
    end

    test "a raising tool is rescued into an error, not a crash" do
      assert {:error, {:exception, RuntimeError, "boom"}} =
               Registry.invoke("raises", %{}, Factory.tool_context())
    end

    test "a behaviour-violating return is flagged" do
      assert {:error, {:bad_return, :oops}} =
               Registry.invoke("bad_return", %{}, Factory.tool_context())
    end
  end

  describe "invoke/3 — happy" do
    test "executes with validated args and returns the tool result" do
      ctx = Factory.tool_context(%{loop: :planning})

      assert {:ok, %{"echoed" => "hello", "level" => "info", "loop" => "planning"}} =
               Registry.invoke("echo_note", %{"text" => "hello"}, ctx)
    end

    test "pending tools return their correlation id" do
      assert {:pending, "req-9"} =
               Registry.invoke("pending_tool", %{"id" => "req-9"}, Factory.tool_context())
    end
  end

  describe "telemetry — contract" do
    test "invoke emits start and stop with status metadata" do
      handler_id = "reg-test-#{System.unique_integer([:positive])}"
      parent = self()

      :ok =
        :telemetry.attach_many(
          handler_id,
          [[:loan_actor, :tool, :start], [:loan_actor, :tool, :stop]],
          fn event, _measurements, metadata, _cfg -> send(parent, {:telemetry, event, metadata}) end,
          nil
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      ctx = Factory.tool_context()
      {:ok, _} = Registry.invoke("echo_note", %{"text" => "t"}, ctx)

      assert_received {:telemetry, [:loan_actor, :tool, :start], %{tool: "echo_note"}}
      assert_received {:telemetry, [:loan_actor, :tool, :stop], %{tool: "echo_note", status: :ok}}

      {:error, _} = Registry.invoke("raises", %{}, ctx)
      assert_received {:telemetry, [:loan_actor, :tool, :stop], %{tool: "raises", status: :error}}
    end
  end

  describe "PII guard — security (order of operations)" do
    setup do
      Application.put_env(
        :loan_actor,
        :tool_pii_guard,
        {TestTools.RedactingGuard, :redact}
      )

      :ok
    end

    test "the tool receives the REDACTED form, never the cleartext" do
      assert {:ok, %{"echoed" => "[guarded]raw"}} =
               Registry.invoke("echo_note", %{"text" => "raw"}, Factory.tool_context())
    end

    test "redacted_args/2 returns exactly what the tool would receive" do
      args = %{"text" => "raw", "ssn" => "123-45-6789"}

      assert {:ok, %{"text" => "[guarded]raw", "ssn" => "<redacted>"}} =
               Registry.redacted_args("echo_note", args)

      assert {:error, :unknown_tool} = Registry.redacted_args("nope", args)
    end

    test "synthetic PII in undeclared keys is redacted before execution" do
      # "ssn" is not in echo's schema (extras permitted) — the guard still
      # strips it before the tool sees the args.
      {:ok, _} =
        Registry.invoke(
          "echo_note",
          %{"text" => "x", "ssn" => "123-45-6789"},
          Factory.tool_context()
        )

      assert {:ok, %{"ssn" => "<redacted>"}} =
               Registry.redacted_args("echo_note", %{"text" => "x", "ssn" => "123-45-6789"})
    end

    test "a hard-gate rejection from the guard rejects the WHOLE invocation, not just the flagged value" do
      assert {:error, {:pii_violation, [["reject_me"]]}} =
               Registry.invoke(
                 "echo_note",
                 %{"text" => "x", "reject_me" => "anything"},
                 Factory.tool_context()
               )

      assert {:error, {:pii_violation, [["reject_me"]]}} =
               Registry.redacted_args("echo_note", %{"text" => "x", "reject_me" => "anything"})
    end
  end
end
