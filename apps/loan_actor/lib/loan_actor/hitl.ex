defmodule LoanActor.HITLRequest do
  @moduledoc """
  A pending human-in-the-loop question the actor asked an operator
  (FT-028). Fields per `specs/001-loan-actor-foundation/data-model.md`
  `%LoanActor.HITLRequest{}`.

  Emitted by the `request_operator_approval` tool (`{:pending,
  request_id}`, FT-043) — `request_id` doubles as the tool's own
  `invocation_id`/AG-UI `tool_call_id`, since both name the same pending
  question (see `LoanActor.Tools.RequestOperatorApproval`'s moduledoc).
  """

  @enforce_keys [:request_id, :loan_id, :prompt, :options, :created_at]
  defstruct [:request_id, :loan_id, :prompt, :options, :created_at]

  @type t :: %__MODULE__{
          request_id: String.t(),
          loan_id: String.t(),
          prompt: String.t(),
          options: [String.t()],
          created_at: DateTime.t()
        }

  @doc "Build a new HITL request. Raises `ArgumentError` on invariant violations."
  @spec new(map() | keyword()) :: t()
  def new(attrs) do
    attrs = Map.new(attrs)

    fields = %{
      request_id: attrs |> Map.fetch!(:request_id) |> validate_binary(:request_id),
      loan_id: attrs |> Map.fetch!(:loan_id) |> validate_binary(:loan_id),
      prompt: attrs |> Map.fetch!(:prompt) |> validate_binary(:prompt),
      options: attrs |> Map.fetch!(:options) |> validate_options(),
      created_at: attrs |> Map.fetch!(:created_at) |> validate_datetime(:created_at)
    }

    struct!(__MODULE__, fields)
  end

  defp validate_binary(v, _field) when is_binary(v) and byte_size(v) > 0, do: v

  defp validate_binary(v, field),
    do: raise(ArgumentError, "#{field} must be a non-empty binary, got: #{inspect(v)}")

  defp validate_options(v) when is_list(v) and v != [] do
    if Enum.all?(v, &(is_binary(&1) and byte_size(&1) > 0)) do
      v
    else
      raise(ArgumentError, "options must be a list of non-empty binaries, got: #{inspect(v)}")
    end
  end

  defp validate_options(v),
    do: raise(ArgumentError, "options must be a non-empty list, got: #{inspect(v)}")

  defp validate_datetime(%DateTime{} = v, _field), do: v

  defp validate_datetime(v, field),
    do: raise(ArgumentError, "#{field} must be a DateTime, got: #{inspect(v)}")
end

defmodule LoanActor.HITLResponse do
  @moduledoc """
  An operator's answer to a `%LoanActor.HITLRequest{}` (FT-028). Fields
  per `specs/001-loan-actor-foundation/data-model.md` `%LoanActor.HITLResponse{}`.

  Built by the caller (HTTP layer or a direct API user) and passed to
  `LoanActor.respond_hitl/3`. Validation here covers only this struct's
  own shape invariants — whether `decision` is actually one of the
  originating request's `options` is not checked (foundation's
  `respond_hitl/3` scope is completing the deferred `ToolCallResult` and
  recording the response; no task asks for cross-struct decision
  validation).
  """

  @enforce_keys [:request_id, :decision, :operator_id, :responded_at]
  defstruct [:request_id, :decision, :comment, :operator_id, :responded_at]

  @type t :: %__MODULE__{
          request_id: String.t(),
          decision: String.t(),
          comment: String.t() | nil,
          operator_id: String.t(),
          responded_at: DateTime.t()
        }

  @doc "Build a new HITL response. Raises `ArgumentError` on invariant violations."
  @spec new(map() | keyword()) :: t()
  def new(attrs) do
    attrs = Map.new(attrs)

    fields = %{
      request_id: attrs |> Map.fetch!(:request_id) |> validate_binary(:request_id),
      decision: attrs |> Map.fetch!(:decision) |> validate_binary(:decision),
      comment: attrs |> Map.get(:comment) |> validate_comment(),
      operator_id: attrs |> Map.fetch!(:operator_id) |> validate_binary(:operator_id),
      responded_at: attrs |> Map.fetch!(:responded_at) |> validate_datetime(:responded_at)
    }

    struct!(__MODULE__, fields)
  end

  defp validate_binary(v, _field) when is_binary(v) and byte_size(v) > 0, do: v

  defp validate_binary(v, field),
    do: raise(ArgumentError, "#{field} must be a non-empty binary, got: #{inspect(v)}")

  defp validate_comment(nil), do: nil
  defp validate_comment(v) when is_binary(v), do: v

  defp validate_comment(v),
    do: raise(ArgumentError, "comment must be nil or a binary, got: #{inspect(v)}")

  defp validate_datetime(%DateTime{} = v, _field), do: v

  defp validate_datetime(v, field),
    do: raise(ArgumentError, "#{field} must be a DateTime, got: #{inspect(v)}")
end
