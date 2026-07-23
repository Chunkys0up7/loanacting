defmodule LoanActor.Tool.Context do
  @moduledoc """
  Invocation context handed to every `LoanActor.Tool.execute/2` (FT-041).

  `invocation_id` doubles as the AG-UI `tool_call_id`, correlating the
  diary pair and the four ToolCall frames of one invocation.

  `state` is the loan's current `%LoanActor.State{}`; typed as `term()` until
  FT-010 lands the struct (the contract in `contracts/tool-behaviour.md` is
  the normative reference).

  `gate` (intent 0003, ADH-004) is an OPTIONAL field, `nil` for every
  foundation tool — populated by the Server ONLY for `evaluate_gate`
  invocations, carrying the already-resolved, per-loan-version-pinned
  `%LoanActor.Gate{}` to evaluate (`contracts/gate-behaviour.md` invariant
  8: "version pinning is a Server-level concern, not this tool's... the
  Server hands it via ctx"). A generic, foundation-level struct gaining one
  optional field for a later feature mirrors how `%LoanActor.State{}`
  itself grew fields over time; every other tool simply never sets or
  reads it.
  """

  @enforce_keys [:loan_id, :state, :loop, :actor, :invocation_id]
  defstruct [:loan_id, :state, :loop, :actor, :invocation_id, :gate]

  @type t :: %__MODULE__{
          loan_id: String.t(),
          state: term(),
          loop: :periodic | :planning,
          actor: String.t(),
          invocation_id: String.t(),
          gate: LoanActor.Gate.t() | nil
        }

  @doc """
  Build a validated context. Raises `ArgumentError` on violations.
  """
  @spec new(map() | keyword()) :: t()
  def new(attrs) do
    attrs = Map.new(attrs)

    fields = %{
      loan_id: attrs |> Map.fetch!(:loan_id) |> validate_binary(:loan_id),
      state: Map.fetch!(attrs, :state),
      loop: attrs |> Map.fetch!(:loop) |> validate_loop(),
      actor: attrs |> Map.fetch!(:actor) |> validate_binary(:actor),
      invocation_id: attrs |> Map.fetch!(:invocation_id) |> validate_binary(:invocation_id),
      gate: Map.get(attrs, :gate)
    }

    struct!(__MODULE__, fields)
  end

  defp validate_binary(v, _field) when is_binary(v) and byte_size(v) > 0, do: v

  defp validate_binary(v, field),
    do: raise(ArgumentError, "#{field} must be a non-empty binary, got: #{inspect(v)}")

  defp validate_loop(v) when v in [:periodic, :planning], do: v

  defp validate_loop(v),
    do: raise(ArgumentError, "loop must be :periodic or :planning, got: #{inspect(v)}")
end
