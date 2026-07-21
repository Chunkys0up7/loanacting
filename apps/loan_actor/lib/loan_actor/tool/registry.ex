defmodule LoanActor.Tool.Registry do
  @moduledoc """
  Config-driven tool registry (FT-042, `contracts/tool-behaviour.md`).

  Tool modules are listed under `config :loan_actor, :tools, [Module, ...]`
  (test env injects fixture tools). The registry:

  - enumerates specs (`list/0`) and resolves names (`fetch/1`);
  - `invoke/3` runs the full invocation path: PII-guard → schema validation →
    telemetry-wrapped `execute/2`, with exceptions converted to `{:error, ...}`
    so a crashing tool never takes the caller down;
  - exposes `redacted_args/2` so the Server can diary-hash and AG-UI-emit the
    exact form the tool received.

  **PII order of operations** (contract invariant 3): args pass the configured
  guard BEFORE validation and execution — tools only ever see the redacted
  form, and the redacted form is what gets hashed and streamed. The guard is
  `config :loan_actor, :tool_pii_guard, {module, function}`; unset means
  identity until `LoanActor.PIIGuard` lands (FT-014 wires it).

  **Zero routing logic** (contract invariant 6): this module knows WHICH tools
  exist, never WHEN to use them — that is skill content (Principle VI/VIII).

  Telemetry: `[:loan_actor, :tool, :start | :stop | :exception]` with
  `%{tool, loan_id, invocation_id}` metadata.
  """

  alias LoanActor.Tool.Context
  alias LoanActor.Tool.Spec

  @spec list() :: [Spec.t()]
  def list, do: Enum.map(modules(), & &1.spec())

  @spec fetch(String.t()) :: {:ok, module()} | {:error, :unknown_tool}
  def fetch(name) do
    case Enum.find(modules(), &(&1.spec().name == name)) do
      nil -> {:error, :unknown_tool}
      module -> {:ok, module}
    end
  end

  @doc """
  The PII-guarded form of `args` for the named tool — the exact map the tool
  would receive from `invoke/3`. Used by the Server for diary hashing and
  `ToolCallArgs` emission.
  """
  @spec redacted_args(String.t(), map()) :: {:ok, map()} | {:error, :unknown_tool}
  def redacted_args(name, args) do
    with {:ok, _module} <- fetch(name) do
      {:ok, apply_guard(args)}
    end
  end

  @doc """
  Invoke a tool by name: guard → validate → execute (telemetry-wrapped).

  Returns the tool's own result (`{:ok, effects} | {:pending, id} |
  {:error, reason}`), or `{:error, :unknown_tool}`,
  `{:error, {:invalid_args, details}}`, `{:error, {:exception, kind, reason}}`
  for a crashing tool, or `{:error, {:bad_return, term}}` for a tool violating
  the behaviour's return contract.
  """
  @spec invoke(String.t(), map(), Context.t()) ::
          {:ok, map()} | {:pending, String.t()} | {:error, term()}
  def invoke(name, args, %Context{} = ctx) do
    with {:ok, module} <- fetch(name),
         redacted = apply_guard(args),
         :ok <- Spec.validate_args(module.spec(), redacted) do
      execute_measured(module, name, redacted, ctx)
    end
  end

  defp execute_measured(module, name, redacted, ctx) do
    metadata = %{tool: name, loan_id: ctx.loan_id, invocation_id: ctx.invocation_id}

    :telemetry.span([:loan_actor, :tool], metadata, fn ->
      result = execute_safely(module, redacted, ctx)
      {result, Map.put(metadata, :status, result_status(result))}
    end)
  end

  defp execute_safely(module, redacted, ctx) do
    case module.execute(redacted, ctx) do
      {:ok, effects} when is_map(effects) -> {:ok, effects}
      {:pending, id} when is_binary(id) -> {:pending, id}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:bad_return, other}}
    end
  rescue
    exception -> {:error, {:exception, exception.__struct__, Exception.message(exception)}}
  end

  defp result_status({:ok, _}), do: :ok
  defp result_status({:pending, _}), do: :pending
  defp result_status({:error, _}), do: :error

  defp apply_guard(args) do
    case Application.get_env(:loan_actor, :tool_pii_guard) do
      nil -> args
      {module, function} -> apply(module, function, [args])
    end
  end

  defp modules, do: Application.get_env(:loan_actor, :tools, [])
end
