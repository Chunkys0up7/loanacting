defmodule LoanActor.Factory do
  @moduledoc """
  Test-data factory (test-data-forge discipline; seeded by FT-006, extended by
  FT-037 with `%Event{}` / `%State{}` / `%Goal{}` / `%HITLRequest{}` factories
  once those entities land).

  ## Discovery checklist (what this factory covers and why)

  - **Schema source of truth**: `%LoanActor.Diary.Entry{}` as defined in
    `specs/001-loan-actor-foundation/data-model.md`. No invented fields.
  - **Determinism**: every default is a pure function of `(loan_id, sequence)`;
    the default timestamp is a fixed instant. Same inputs → byte-identical
    entries. Randomness is opt-in via the StreamData generators only.
  - **Isolation**: nothing here touches disk, Mnesia, or the network. Unique
    loan ids come from `unique_loan_id/0` so parallel tests never collide.
  - **Scenario classes** (coverage taxonomy):
    - happy — `entry/1`, `chain/2`, `next_entry/2`
    - boundary — genesis entry (sequence 0), single-entry chains
    - invalid — `invalid_entry_variants/0` catalog for parametrized negative tests
    - property — `chain_gen/1` StreamData generator derived from the chain rules
    - adversarial/tamper — built by tests mutating factory output (see
      `chain_test.exs` and the shared store suite); the factory itself only
      produces valid data.

  Skipped classes, with reasons: temporal/stateful ordering beyond the chain
  itself is exercised at the store level (FT-007/FT-008), and PII-shaped
  payloads belong to the `PIIGuard` corpus (FT-014) — payloads never reach this
  struct, only their hashes do.
  """

  alias LoanActor.Diary.Chain
  alias LoanActor.Diary.Entry
  alias LoanActor.Tool.Context, as: ToolContext
  alias LoanActor.Tool.Spec, as: ToolSpec

  @default_timestamp ~U[2026-07-21 00:00:00Z]

  @doc "Fixed deterministic timestamp used by all factory defaults."
  @spec default_timestamp() :: DateTime.t()
  def default_timestamp, do: @default_timestamp

  @doc """
  Loan id unique within AND across test runs (`"L-<run>-<n>"`). The per-run
  token matters because both diary stores persist to real disk locations that
  outlive the BEAM: a bare monotonic counter restarts every run and would
  collide with leftover data.
  """
  @spec unique_loan_id() :: String.t()
  def unique_loan_id do
    "L-#{run_token()}-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp run_token do
    key = {__MODULE__, :run_token}

    case :persistent_term.get(key, nil) do
      nil ->
        token = Base.hex_encode32(:crypto.strong_rand_bytes(5), case: :lower)
        :persistent_term.put(key, token)
        token

      token ->
        token
    end
  end

  @doc """
  Deterministic payload hash for `(loan_id, sequence)` — 32 bytes, distinct per
  input pair.
  """
  @spec payload_hash(String.t(), non_neg_integer()) :: binary()
  def payload_hash(loan_id, sequence) do
    Chain.hash([loan_id, ":", Integer.to_string(sequence)])
  end

  @doc """
  Valid attribute map for `LoanActor.Diary.Entry.new/1`. Defaults produce the
  genesis entry (sequence 0) of loan `"L-FACTORY"`. Override any field.

  Note: overriding `sequence` alone yields a *self-consistent single entry*
  whose `prev_hash` is still genesis — use `chain/2` or `next_entry/2` when the
  entry must link to a predecessor.
  """
  @spec entry_attrs(map() | keyword()) :: map()
  def entry_attrs(overrides \\ %{}) do
    overrides = Map.new(overrides)
    loan_id = Map.get(overrides, :loan_id, "L-FACTORY")
    sequence = Map.get(overrides, :sequence, 0)

    Map.merge(
      %{
        loan_id: loan_id,
        sequence: sequence,
        timestamp: @default_timestamp,
        type: :spawned,
        actor: "system",
        payload_hash: payload_hash(loan_id, sequence),
        prev_hash: Entry.genesis_prev_hash()
      },
      overrides
    )
  end

  @doc "Build a validated `%Entry{}` from `entry_attrs/1`."
  @spec entry(map() | keyword()) :: Entry.t()
  def entry(overrides \\ %{}), do: Entry.new(entry_attrs(overrides))

  @doc """
  Build the entry that legally follows `tail` (or the genesis entry when `tail`
  is `nil`), inheriting the tail's `loan_id`. `overrides` may not break the
  linkage fields (`sequence`/`prev_hash` are derived).
  """
  @spec next_entry(Entry.t() | nil, map() | keyword()) :: Entry.t()
  def next_entry(tail, overrides \\ %{})

  def next_entry(nil, overrides), do: entry(overrides)

  def next_entry(%Entry{} = tail, overrides) do
    overrides = Map.new(overrides)
    sequence = tail.sequence + 1
    loan_id = tail.loan_id

    overrides
    |> Map.drop([:sequence, :prev_hash, :loan_id])
    |> Map.put_new(:type, :heartbeat)
    |> Map.put_new(:payload_hash, payload_hash(loan_id, sequence))
    |> Map.merge(%{
      loan_id: loan_id,
      sequence: sequence,
      prev_hash: Chain.next_prev_hash(tail)
    })
    |> entry()
  end

  @doc """
  A valid chain of `n` linked entries (sequences `0..n-1`) for one loan.
  Deterministic for a given `(loan_id, n)`.
  """
  @spec chain(pos_integer(), map() | keyword()) :: [Entry.t()]
  def chain(n, overrides \\ %{}) when is_integer(n) and n > 0 do
    overrides = Map.new(overrides)
    genesis = entry(Map.put_new(overrides, :loan_id, "L-FACTORY"))

    1..(n - 1)//1
    |> Enum.reduce([genesis], fn _seq, [tail | _] = acc ->
      [next_entry(tail, Map.delete(overrides, :loan_id)) | acc]
    end)
    |> Enum.reverse()
  end

  @doc """
  Catalog of invalid `Entry.new/1` inputs, one per violated field invariant.
  Consumed by parametrized negative tests (`entry_test.exs`, shared store
  suite). Each element is `{label, attrs}`; every `attrs` raises
  `ArgumentError` in `Entry.new/1`.
  """
  @spec invalid_entry_variants() :: [{atom(), map()}]
  def invalid_entry_variants do
    [
      {:loan_id_empty, entry_attrs(%{loan_id: ""})},
      {:loan_id_not_binary, entry_attrs() |> Map.put(:loan_id, 42)},
      {:sequence_negative, entry_attrs() |> Map.put(:sequence, -1)},
      {:sequence_not_integer, entry_attrs() |> Map.put(:sequence, "0")},
      {:timestamp_not_datetime, entry_attrs() |> Map.put(:timestamp, "2026-07-21")},
      {:type_not_atom, entry_attrs() |> Map.put(:type, "spawned")},
      {:actor_empty, entry_attrs(%{actor: ""})},
      {:payload_hash_short, entry_attrs() |> Map.put(:payload_hash, <<1::size(31)-unit(8)>>)},
      {:payload_hash_long, entry_attrs() |> Map.put(:payload_hash, <<1::size(33)-unit(8)>>)},
      {:payload_hash_not_binary, entry_attrs() |> Map.put(:payload_hash, :hash)},
      {:prev_hash_short, entry_attrs() |> Map.put(:prev_hash, <<0::size(16)-unit(8)>>)},
      {:payload_ref_not_binary, entry_attrs() |> Map.put(:payload_ref, 123)}
    ]
  end

  # ---- Tool factories (FT-041; extended by FT-037) ----
  #
  # Discovery checklist: schema source of truth is contracts/tool-behaviour.md
  # (JSON-schema SUBSET: type/properties/required/enum, string keys). Scenario
  # classes: happy (tool_spec_attrs defaults + valid_tool_args), invalid
  # (invalid_tool_args_variants — one per validator rule; invalid_tool_schema_variants
  # — one per cap violation). Deterministic throughout; no randomness.

  @doc """
  Valid attribute map for `LoanActor.Tool.Spec.new/1`. Defaults describe a
  demo `request_document` tool exercising every allowed schema keyword
  (object/properties/required/enum + string/integer/boolean/array leaves).
  """
  @spec tool_spec_attrs(map() | keyword()) :: map()
  def tool_spec_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        name: "request_document",
        description: "Request a document from the operator.",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "doc_type" => %{"type" => "string", "enum" => ["income", "identity", "appraisal"]},
            "priority" => %{"type" => "integer"},
            "blocking" => %{"type" => "boolean"},
            "tags" => %{"type" => "array"},
            "meta" => %{
              "type" => "object",
              "properties" => %{"note" => %{"type" => "string"}},
              "required" => ["note"]
            }
          },
          "required" => ["doc_type"]
        }
      },
      Map.new(overrides)
    )
  end

  @doc "Build a validated `%Tool.Spec{}` from `tool_spec_attrs/1`."
  @spec tool_spec(map() | keyword()) :: ToolSpec.t()
  def tool_spec(overrides \\ %{}), do: ToolSpec.new(tool_spec_attrs(overrides))

  @doc "Args satisfying the default `tool_spec/1` schema (minimal + full variants)."
  @spec valid_tool_args(:minimal | :full) :: map()
  def valid_tool_args(:minimal), do: %{"doc_type" => "income"}

  def valid_tool_args(:full) do
    %{
      "doc_type" => "identity",
      "priority" => 2,
      "blocking" => true,
      "tags" => ["kyc", "urgent"],
      "meta" => %{"note" => "second request"}
    }
  end

  @doc """
  Catalog of invalid args against the default `tool_spec/1` schema — one per
  validator rule. Each element is `{label, args, expected_error_path}`.
  """
  @spec invalid_tool_args_variants() :: [{atom(), map(), [String.t()]}]
  def invalid_tool_args_variants do
    [
      {:missing_required, %{"priority" => 1}, ["doc_type"]},
      {:wrong_type_string, %{"doc_type" => 42}, ["doc_type"]},
      {:not_in_enum, %{"doc_type" => "selfie"}, ["doc_type"]},
      {:wrong_type_integer, valid_tool_args(:minimal) |> Map.put("priority", "high"), ["priority"]},
      {:wrong_type_boolean, valid_tool_args(:minimal) |> Map.put("blocking", "yes"), ["blocking"]},
      {:wrong_type_array, valid_tool_args(:minimal) |> Map.put("tags", "kyc"), ["tags"]},
      {:nested_missing_required, valid_tool_args(:minimal) |> Map.put("meta", %{}), ["meta", "note"]},
      {:nested_wrong_type, valid_tool_args(:minimal) |> Map.put("meta", %{"note" => 1}), ["meta", "note"]}
    ]
  end

  @doc """
  Valid `%Tool.Context{}` for tool tests: planning loop, unique loan and
  invocation ids, empty state (State struct lands in FT-010).
  """
  @spec tool_context(map() | keyword()) :: ToolContext.t()
  def tool_context(overrides \\ %{}) do
    %{
      loan_id: unique_loan_id(),
      state: %{},
      loop: :planning,
      actor: "system",
      invocation_id: "inv-#{System.unique_integer([:positive, :monotonic])}"
    }
    |> Map.merge(Map.new(overrides))
    |> ToolContext.new()
  end

  @doc """
  Catalog of schema maps violating the FT-041 hard cap — `Tool.Spec.new/1`
  raises for each. `{label, parameters}`.
  """
  @spec invalid_tool_schema_variants() :: [{atom(), term()}]
  def invalid_tool_schema_variants do
    [
      {:forbidden_keyword, %{"type" => "object", "additionalProperties" => false}},
      {:forbidden_format, %{"type" => "string", "format" => "uuid"}},
      {:unknown_type, %{"type" => "number"}},
      {:bad_required, %{"type" => "object", "required" => [:doc_type]}},
      {:empty_enum, %{"type" => "string", "enum" => []}},
      {:nested_violation, %{"type" => "object", "properties" => %{"x" => %{"minLength" => 3}}}},
      {:not_a_map, "string schema"}
    ]
  end

  # ---- StreamData generators (opt-in randomness for property tests) ----

  @doc "Generator for diary entry types drawn from the data-model enum."
  @spec entry_type_gen() :: StreamData.t(atom())
  def entry_type_gen do
    StreamData.member_of([
      :spawned,
      :document_uploaded,
      :document_review_requested,
      :operator_approval_required,
      :operator_approval_granted,
      :operator_approval_denied,
      :heartbeat,
      :goal_set,
      :goal_satisfied,
      :goal_abandoned,
      :complete,
      :abort,
      :state_transition,
      :duplicate_rejected,
      :approval_conflict
    ])
  end

  @doc """
  Generator for valid chains: `1..max_len` linked entries for a fresh loan,
  with types drawn from `entry_type_gen/0`. Shrinks toward short chains.
  """
  @spec chain_gen(pos_integer()) :: StreamData.t([Entry.t()])
  def chain_gen(max_len \\ 25) do
    StreamData.bind(StreamData.integer(1..max_len), fn len ->
      StreamData.bind(StreamData.list_of(entry_type_gen(), length: len), fn types ->
        loan_id = unique_loan_id()

        entries =
          types
          |> Enum.with_index()
          |> Enum.reduce([], fn
            {type, 0}, [] ->
              [entry(%{loan_id: loan_id, type: type})]

            {type, _i}, [tail | _] = acc ->
              [next_entry(tail, %{type: type}) | acc]
          end)
          |> Enum.reverse()

        StreamData.constant(entries)
      end)
    end)
  end
end
