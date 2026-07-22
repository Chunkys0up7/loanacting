defmodule LoanActor.Application do
  @moduledoc """
  OTP application supervision tree root (FT-016). Starts the loan registry
  and the per-loan `DynamicSupervisor`, in that order (the supervisor's
  children register themselves into the registry as they start, so the
  registry must already be up), plus `LoanActor.AGUI.Stream` (FT-024) — the
  supervisor for per-client AG-UI subscriber processes.
  """

  use Application

  @impl Application
  def start(_type, _args) do
    children = [
      LoanActor.Registry,
      LoanActor.Supervisor,
      LoanActor.AGUI.Stream
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: LoanActor.RootSupervisor)
  end
end
