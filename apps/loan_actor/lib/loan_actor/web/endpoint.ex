defmodule LoanActor.Web.Endpoint do
  @moduledoc """
  Bandit HTTP server hosting `LoanActor.Web.Router` (FT-027,
  `contracts/http-endpoints.md`). Port is `config :loan_actor, :http_port`
  (dev/prod default 4000; test env uses a distinct port to avoid
  clashing with a developer's own `mix run` on the same machine).
  """

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(_opts) do
    Bandit.child_spec(plug: LoanActor.Web.Router, port: port(), scheme: :http)
  end

  defp port, do: Application.get_env(:loan_actor, :http_port, 4000)
end
