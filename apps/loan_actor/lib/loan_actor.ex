defmodule LoanActor do
  @moduledoc """
  Public API for the loan actor (FT-016 supervision + FT-017 reactive
  loop). This module **is** the surface documented in
  `contracts/loan-actor-api.md`. `respond_hitl/3` (FT-028) is added by its
  own later task.
  """

  alias LoanActor.Event
  alias LoanActor.Registry
  alias LoanActor.Server
  alias LoanActor.State
  alias LoanActor.Supervisor

  @doc """
  Spawn a supervised loan actor for `loan_id`. Idempotent: if already
  running, returns `{:ok, existing_pid}` without starting a duplicate —
  including under a race, where the registry's own `:unique` key
  enforcement surfaces as `{:error, {:already_started, pid}}` from
  `start_child/1`, which this function converts to `{:ok, pid}`.
  """
  @spec spawn(String.t()) :: {:ok, pid()} | {:error, term()}
  def spawn(loan_id) do
    case Registry.whereis(loan_id) do
      nil ->
        case Supervisor.start_child({Server, loan_id}) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          {:error, reason} -> {:error, reason}
        end

      pid ->
        {:ok, pid}
    end
  end

  @doc "The pid of the supervised actor for `loan_id`, or `nil` if not running."
  @spec whereis(String.t()) :: pid() | nil
  def whereis(loan_id), do: Registry.whereis(loan_id)

  @doc "Send `loan_id` a typed event. See `contracts/loan-actor-api.md`."
  @spec send_event(String.t(), Event.t()) ::
          {:ok, non_neg_integer()}
          | {:duplicate, non_neg_integer()}
          | {:error, term()}
  def send_event(loan_id, %Event{} = event) do
    case Registry.whereis(loan_id) do
      nil -> {:error, :not_running}
      pid -> Server.send_event(pid, event)
    end
  end

  @doc "The loan's current in-memory state."
  @spec state(String.t()) :: {:ok, State.t()} | {:error, :not_running}
  def state(loan_id) do
    case Registry.whereis(loan_id) do
      nil -> {:error, :not_running}
      pid -> {:ok, Server.state(pid)}
    end
  end

  @doc "Subscribe to `loan_id`'s AG-UI event stream. See `contracts/loan-actor-api.md`."
  @spec subscribe(String.t(), keyword()) :: {:ok, reference()} | {:error, term()}
  def subscribe(loan_id, opts \\ []) do
    case Registry.whereis(loan_id) do
      nil -> {:error, :not_running}
      pid -> Server.subscribe(pid, opts)
    end
  end
end
