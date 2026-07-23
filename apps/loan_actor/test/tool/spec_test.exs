defmodule LoanActor.Tool.SpecTest do
  @moduledoc """
  FT-041 — `Tool.Spec` construction cap + `validate_args/2` subset validator.
  Taxonomy: happy / boundary / error / contract. Data via `LoanActor.Factory`
  tool catalogs (test-data-forge).
  """

  use ExUnit.Case, async: true

  alias LoanActor.Factory
  alias LoanActor.Tool
  alias LoanActor.Tool.Context
  alias LoanActor.Tool.Spec

  describe "behaviour surface — contract" do
    test "LoanActor.Tool declares exactly spec/0 and execute/2" do
      assert MapSet.new(Tool.behaviour_info(:callbacks)) == MapSet.new(spec: 0, execute: 2)
    end
  end

  describe "Spec.new/1 — happy" do
    test "builds a spec exercising every allowed schema keyword" do
      spec = Factory.tool_spec()
      assert spec.name == "request_document"
      assert %{"type" => "object"} = spec.parameters
    end

    test "accepts the empty object schema (zero-arg tool)" do
      spec = Factory.tool_spec(%{parameters: %{"type" => "object"}})
      assert :ok = Spec.validate_args(spec, %{})
    end
  end

  describe "Spec.new/1 — error (hard cap)" do
    test "rejects every cap-violating schema in the catalog" do
      for {label, parameters} <- Factory.invalid_tool_schema_variants() do
        assert_raise ArgumentError, ~r/subset|schema must be a map/, fn ->
          Factory.tool_spec(%{parameters: parameters})
        end

        _ = label
      end
    end

    test "rejects empty name and description" do
      assert_raise ArgumentError, fn -> Factory.tool_spec(%{name: ""}) end
      assert_raise ArgumentError, fn -> Factory.tool_spec(%{description: ""}) end
    end
  end

  describe "validate_args/2 — happy" do
    test "minimal args (required only) pass" do
      assert :ok = Spec.validate_args(Factory.tool_spec(), Factory.valid_tool_args(:minimal))
    end

    test "fully populated args pass" do
      assert :ok = Spec.validate_args(Factory.tool_spec(), Factory.valid_tool_args(:full))
    end

    test "keys not covered by properties are permitted (JSON-Schema default)" do
      args = Factory.valid_tool_args(:minimal) |> Map.put("extra", "ignored")
      assert :ok = Spec.validate_args(Factory.tool_spec(), args)
    end
  end

  describe "validate_args/2 — error (parametrized catalog)" do
    test "each invalid variant fails at the documented path" do
      spec = Factory.tool_spec()

      for {label, args, path} <- Factory.invalid_tool_args_variants() do
        assert {:error, {:invalid_args, errors}} = Spec.validate_args(spec, args)

        assert Enum.any?(errors, fn {err_path, _reason} -> err_path == path end),
               "#{label}: expected an error at #{inspect(path)}, got #{inspect(errors)}"
      end
    end

    test "non-map args against an object schema fail at the root" do
      assert {:error, {:invalid_args, [{[], :wrong_type}]}} =
               Spec.validate_args(Factory.tool_spec(), "not a map")
    end

    test "multiple violations are all reported" do
      spec = Factory.tool_spec()
      args = %{"doc_type" => 42, "priority" => "high"}
      assert {:error, {:invalid_args, errors}} = Spec.validate_args(spec, args)
      assert length(errors) >= 2
    end
  end

  describe "Tool.Context — happy + error" do
    defp context_attrs do
      %{
        loan_id: "L-CTX",
        state: %{},
        loop: :planning,
        actor: "system",
        invocation_id: "inv-1"
      }
    end

    test "new/1 builds a validated context" do
      ctx = Context.new(context_attrs())
      assert ctx.loop == :planning
      assert ctx.invocation_id == "inv-1"
    end

    test "rejects the reactive loop — ingestion is not a tool call (clarify Q11)" do
      assert_raise ArgumentError, fn -> Context.new(%{context_attrs() | loop: :reactive}) end
    end

    test "rejects empty identifiers" do
      assert_raise ArgumentError, fn -> Context.new(%{context_attrs() | loan_id: ""}) end
      assert_raise ArgumentError, fn -> Context.new(%{context_attrs() | invocation_id: ""}) end
    end
  end
end
