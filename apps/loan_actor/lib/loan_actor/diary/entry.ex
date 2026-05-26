defmodule LoanActor.Diary.Entry do
  @moduledoc """
  Append-only diary entry record. Identifies a single state-affecting event in
  the life of a loan actor.

  Fields are described in `specs/001-loan-actor-foundation/data-model.md`. This
  module is FT-005 (constitution Principle IV — immutable diary): defines the
  struct and the genesis hash. Chain math lives in `LoanActor.Diary.Chain`.

  The `payload_hash` is a 32-byte BLAKE2b-256 digest of the canonical-JSON
  serialization of a PII-stripped payload. Computing it is the responsibility
  of the diary store implementation (FT-007 file / FT-008 mnesia) using the
  PIIGuard module (FT-014). This struct only stores the digest.
  """

  @hash_size 32
  @genesis_prev_hash <<0::size(@hash_size)-unit(8)>>

  @enforce_keys [
    :loan_id,
    :sequence,
    :timestamp,
    :type,
    :actor,
    :payload_hash,
    :prev_hash
  ]
  defstruct [
    :loan_id,
    :sequence,
    :timestamp,
    :type,
    :actor,
    :payload_hash,
    :payload_ref,
    :prev_hash
  ]

  @type t :: %__MODULE__{
          loan_id: String.t(),
          sequence: non_neg_integer(),
          timestamp: DateTime.t(),
          type: atom(),
          actor: String.t(),
          payload_hash: binary(),
          payload_ref: binary() | nil,
          prev_hash: binary()
        }

  @doc """
  Size of a chain hash in bytes (32 = BLAKE2b-256).
  """
  @spec hash_size() :: pos_integer()
  def hash_size, do: @hash_size

  @doc """
  Genesis `prev_hash` — 32 zero bytes. Used by entry 0 of every loan.
  """
  @spec genesis_prev_hash() :: binary()
  def genesis_prev_hash, do: @genesis_prev_hash

  @doc """
  Build a new entry. Raises `ArgumentError` if any field violates the documented
  invariants (sizes, ranges, non-empty strings). Returns the struct on success.

  This is the **only** sanctioned constructor — directly creating a
  `%__MODULE__{}` outside this function is permitted but bypasses validation
  and is discouraged. The diary store implementations always go through here.
  """
  @spec new(map() | keyword()) :: t()
  def new(attrs) do
    attrs = Map.new(attrs)

    fields = %{
      loan_id: Map.fetch!(attrs, :loan_id) |> validate_loan_id(),
      sequence: Map.fetch!(attrs, :sequence) |> validate_sequence(),
      timestamp: Map.fetch!(attrs, :timestamp) |> validate_timestamp(),
      type: Map.fetch!(attrs, :type) |> validate_type(),
      actor: Map.fetch!(attrs, :actor) |> validate_actor(),
      payload_hash: Map.fetch!(attrs, :payload_hash) |> validate_hash(:payload_hash),
      payload_ref: Map.get(attrs, :payload_ref) |> validate_payload_ref(),
      prev_hash: Map.fetch!(attrs, :prev_hash) |> validate_hash(:prev_hash)
    }

    struct!(__MODULE__, fields)
  end

  @doc """
  Composite primary key `{loan_id, sequence}`. Matches the Mnesia table key
  shape described in `data-model.md`.
  """
  @spec entry_id(t()) :: {String.t(), non_neg_integer()}
  def entry_id(%__MODULE__{loan_id: l, sequence: s}), do: {l, s}

  # ---- validators ----

  defp validate_loan_id(v) when is_binary(v) and byte_size(v) > 0, do: v

  defp validate_loan_id(v),
    do: raise(ArgumentError, "loan_id must be a non-empty binary, got: #{inspect(v)}")

  defp validate_sequence(v) when is_integer(v) and v >= 0, do: v

  defp validate_sequence(v),
    do: raise(ArgumentError, "sequence must be a non-negative integer, got: #{inspect(v)}")

  defp validate_timestamp(%DateTime{} = v), do: v

  defp validate_timestamp(v),
    do: raise(ArgumentError, "timestamp must be a DateTime, got: #{inspect(v)}")

  defp validate_type(v) when is_atom(v) and not is_nil(v), do: v

  defp validate_type(v),
    do: raise(ArgumentError, "type must be an atom, got: #{inspect(v)}")

  defp validate_actor(v) when is_binary(v) and byte_size(v) > 0, do: v

  defp validate_actor(v),
    do: raise(ArgumentError, "actor must be a non-empty binary, got: #{inspect(v)}")

  defp validate_hash(v, _field) when is_binary(v) and byte_size(v) == @hash_size, do: v

  defp validate_hash(v, field),
    do:
      raise(
        ArgumentError,
        "#{field} must be a #{@hash_size}-byte binary, got #{byte_size_or_inspect(v)}"
      )

  defp validate_payload_ref(nil), do: nil
  defp validate_payload_ref(v) when is_binary(v), do: v

  defp validate_payload_ref(v),
    do: raise(ArgumentError, "payload_ref must be nil or a binary, got: #{inspect(v)}")

  defp byte_size_or_inspect(v) when is_binary(v), do: "#{byte_size(v)} bytes"
  defp byte_size_or_inspect(v), do: inspect(v)
end
