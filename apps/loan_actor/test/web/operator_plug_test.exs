defmodule LoanActor.Web.OperatorPlugTest do
  @moduledoc """
  FT-026 — `LoanActor.Web.OperatorPlug`.
  Taxonomy: happy / error / security. Data via `Plug.Test.conn/3` (real
  `Plug.Conn` structs, no hand-rolled fixtures).
  """

  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias LoanActor.Web.OperatorPlug

  setup do
    previous_require = Application.get_env(:loan_actor, :require_operator_id)
    previous_env = System.get_env("OPERATOR_ID")
    System.delete_env("OPERATOR_ID")

    on_exit(fn ->
      restore(:require_operator_id, previous_require)
      restore_env(previous_env)
    end)

    :ok
  end

  defp restore(key, nil), do: Application.delete_env(:loan_actor, key)
  defp restore(key, value), do: Application.put_env(:loan_actor, key, value)

  defp restore_env(nil), do: System.delete_env("OPERATOR_ID")
  defp restore_env(value), do: System.put_env("OPERATOR_ID", value)

  defp call(conn), do: OperatorPlug.call(conn, OperatorPlug.init([]))

  describe "call/2 — happy" do
    test "the x-operator-id header is assigned as operator_id" do
      conn =
        :get
        |> conn("/")
        |> put_req_header("x-operator-id", "alice")
        |> call()

      refute conn.halted
      assert conn.assigns.operator_id == "alice"
    end

    test "falls back to the OPERATOR_ID env var when the header is absent" do
      System.put_env("OPERATOR_ID", "bob")

      conn = :get |> conn("/") |> call()

      refute conn.halted
      assert conn.assigns.operator_id == "bob"
    end

    test "the header takes precedence over the env var when both are present (security)" do
      System.put_env("OPERATOR_ID", "bob")

      conn =
        :get
        |> conn("/")
        |> put_req_header("x-operator-id", "alice")
        |> call()

      assert conn.assigns.operator_id == "alice"
    end

    test "require_operator_id: false with neither source present proceeds with operator_id: nil" do
      Application.put_env(:loan_actor, :require_operator_id, false)

      conn = :get |> conn("/") |> call()

      refute conn.halted
      assert conn.assigns.operator_id == nil
    end
  end

  describe "call/2 — boundary" do
    test "an empty-string header is treated as absent, not a blank operator id" do
      Application.put_env(:loan_actor, :require_operator_id, false)

      conn =
        :get
        |> conn("/")
        |> put_req_header("x-operator-id", "")
        |> call()

      assert conn.assigns.operator_id == nil
    end

    test "an empty-string OPERATOR_ID env var is treated as absent" do
      Application.put_env(:loan_actor, :require_operator_id, false)
      System.put_env("OPERATOR_ID", "")

      conn = :get |> conn("/") |> call()

      assert conn.assigns.operator_id == nil
    end
  end

  describe "call/2 — error (production posture, security)" do
    test "missing operator id with require_operator_id: true is a 401" do
      # config/test.exs sets require_operator_id: false globally (so other
      # tests don't need the header) — set it explicitly here to exercise
      # the production posture this plug exists to enforce.
      Application.put_env(:loan_actor, :require_operator_id, true)

      conn = :get |> conn("/") |> call()

      assert conn.halted
      assert conn.status == 401
      assert Jason.decode!(conn.resp_body) == %{"error" => "missing x-operator-id"}
    end

    test "the default (no explicit config) is require_operator_id: true" do
      Application.delete_env(:loan_actor, :require_operator_id)

      conn = :get |> conn("/") |> call()

      assert conn.halted
      assert conn.status == 401
    end
  end
end
