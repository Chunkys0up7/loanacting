defmodule LoanActor.Web.OperatorPlug do
  @moduledoc """
  Operator identity stub for HTTP requests (FT-026; clarifications Q7).
  Real auth is a later intent — this plug exists to make that swap
  minimal: the interface (`conn.assigns[:operator_id]`) stays stable.

  Resolution order: the `x-operator-id` request header (preferred), then
  the `OPERATOR_ID` OS environment variable (fallback for local dev). If
  neither is present:

  - `config :loan_actor, :require_operator_id` (default `true`) rejects
    the request with `401` — the production posture;
  - with it set to `false` (tests, local dev), the request proceeds with
    `conn.assigns[:operator_id] == nil`.

  An empty-string header value is treated as absent, not as a valid
  (blank) operator id.
  """

  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case resolve_operator_id(conn) do
      {:ok, operator_id} -> assign(conn, :operator_id, operator_id)
      :error -> handle_missing(conn)
    end
  end

  defp resolve_operator_id(conn) do
    case get_req_header(conn, "x-operator-id") do
      [value | _] when is_binary(value) and value != "" -> {:ok, value}
      _ -> resolve_from_env()
    end
  end

  defp resolve_from_env do
    case System.get_env("OPERATOR_ID") do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> :error
    end
  end

  defp handle_missing(conn) do
    if require_operator_id?() do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(401, Jason.encode!(%{"error" => "missing x-operator-id"}))
      |> halt()
    else
      assign(conn, :operator_id, nil)
    end
  end

  defp require_operator_id?, do: Application.get_env(:loan_actor, :require_operator_id, true)
end
