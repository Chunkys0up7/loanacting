defmodule LoanActor.Application do
  @moduledoc """
  OTP application supervision tree root (FT-016). Starts the loan registry
  and the per-loan `DynamicSupervisor`, in that order (the supervisor's
  children register themselves into the registry as they start, so the
  registry must already be up), plus `LoanActor.AGUI.Stream` (FT-024) — the
  supervisor for per-client AG-UI subscriber processes — and, unless
  disabled, `LoanActor.Web.Endpoint` (FT-027), the HTTP server.

  `config :loan_actor, :start_http_endpoint` (default `true`) — set to
  `false` by the `Mix.Tasks.LoanActor.*` CLI helpers (FT-039) before
  `Mix.Task.run("app.start")`, found necessary because those are one-shot
  CLI invocations (spawn/replay/verify_chain/dump_diary) that need the
  supervision tree (registry, actors, diary store) but never the HTTP
  listener — without this, every one of them would unconditionally try to
  bind the same port an already-running deployment on the same machine
  has open, and fail with `:eaddrinuse` (confirmed empirically running
  `mix loan_actor.spawn` against a real `mix run --no-halt` instance).
  """

  use Application

  @impl Application
  def start(_type, _args) do
    children =
      [LoanActor.Registry, LoanActor.Supervisor, LoanActor.AGUI.Stream] ++
        if start_http_endpoint?(), do: [LoanActor.Web.Endpoint], else: []

    Supervisor.start_link(children, strategy: :one_for_one, name: LoanActor.RootSupervisor)
  end

  defp start_http_endpoint?, do: Application.get_env(:loan_actor, :start_http_endpoint, true)
end
