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
  guard BEFORE validation and execution — tools only ever see the guarded
  form. The guard is `config :loan_actor, :tool_pii_guard, {module, function}`,
  a function of one arg (`args`) matching `LoanActor.PIIGuard.apply/1`'s
  shape EXACTLY: `{:ok, guarded_args, redacted_paths} | {:error,
  :pii_violation, paths}` — `LoanActor.PIIGuard` (FT-014) is a HARD GATE
  (clarifications.md Q12: any match rejects the whole payload, never
  redact-and-continue), so a PII match in tool args rejects the WHOLE
  invocation as `{:error, {:pii_violation, paths}}`, not a silently-cleaned
  args map. Unset guard means identity (`{:ok, args, []}`).

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

  Returns `{:ok, guarded_args}`, `{:error, :unknown_tool}`, or
  `{:error, {:pii_violation, paths}}` if `args` itself contains PII (the
  hard gate rejects before any hashing/emission would occur).
  """
  @spec redacted_args(String.t(), map()) ::
          {:ok, map()} | {:error, :unknown_tool} | {:error, {:pii_violation, [term()]}}
  def redacted_args(name, args) do
    with {:ok, _module} <- fetch(name) do
      case apply_guard(args) do
        {:ok, guarded, _paths} -> {:ok, guarded}
        {:error, :pii_violation, paths} -> {:error, {:pii_violation, paths}}
      end
    end
  end

  @doc """
  Invoke a tool by name: guard → validate → execute (telemetry-wrapped).

  Returns the tool's own result (`{:ok, effects} | {:pending, id} |
  {:error, reason}`), or `{:error, :unknown_tool}`,
  `{:error, {:pii_violation, paths}}` (args rejected by the hard gate before
  the tool ever ran), `{:error, {:invalid_args, details}}`,
  `{:error, {:exception, kind, reason}}` for a crashing tool, or
  `{:error, {:bad_return, term}}` for a tool violating the behaviour's
  return contract.
  """
  @spec invoke(String.t(), map(), Context.t()) ::
          {:ok, map()} | {:pending, String.t()} | {:error, term()}
  def invoke(name, args, %Context{} = ctx) do
    with {:ok, module} <- fetch(name),
         {:ok, guarded, _paths} <- apply_guard(args),
         :ok <- Spec.validate_args(module.spec(), guarded) do
      execute_measured(module, name, guarded, ctx)
    else
      {:error, :pii_violation, paths} -> {:error, {:pii_violation, paths}}
      {:error, other} -> {:error, other}
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
      nil -> {:ok, args, []}
      {module, function} -> apply(module, function, [args])
    end
  end

  defp modules, do: Application.get_env(:loan_actor, :tools, [])
end
