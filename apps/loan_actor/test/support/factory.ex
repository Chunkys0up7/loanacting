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

  alias LoanActor.Assessment
  alias LoanActor.Diary.Chain
  alias LoanActor.Diary.Entry
  alias LoanActor.Event
  alias LoanActor.Gate
  alias LoanActor.Goal
  alias LoanActor.HITLRequest
  alias LoanActor.HITLResponse
  alias LoanActor.Skill
  alias LoanActor.State
  alias LoanActor.State.Model
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

  @doc """
  A path under `System.tmp_dir!/0` unique WITHIN and ACROSS test runs —
  same run-token rationale as `unique_loan_id/0`, generalized: any test
  writing to the real filesystem (not a store this project tracks its own
  dir for) needs this, or a stale directory from an earlier `mix test`
  invocation can collide with a "fresh" one (`System.tmp_dir!()` is never
  cleaned between runs; a bare `System.unique_integer/1` resets to low
  numbers every fresh BEAM VM and can reproduce an earlier run's exact
  name). Found the hard way: `test/skill/loader_test.exs`'s reload test
  flaked intermittently before switching to this helper.
  """
  @spec unique_tmp_dir(String.t()) :: String.t()
  def unique_tmp_dir(prefix) do
    Path.join(System.tmp_dir!(), "#{prefix}_#{run_token()}_#{System.unique_integer([:positive, :monotonic])}")
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

  # ---- Goal + State factories (FT-010) ----
  #
  # Discovery checklist: schema source of truth is data-model.md `%Goal{}` /
  # `%LoanActor.State{}` tables. Scenario classes: happy (goal_attrs/state_attrs
  # defaults), boundary (state_at/1 exercises every status enum value; goals
  # list empty vs populated), invalid (invalid_goal_variants /
  # invalid_state_variants -- one per validator rule). Deterministic: no
  # randomness; ids come from the shared unique_loan_id/monotonic-counter
  # mechanism already used by the diary factories.

  @doc "Valid attribute map for `LoanActor.Goal.new/1`."
  @spec goal_attrs(map() | keyword()) :: map()
  def goal_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        goal_id: "G-#{System.unique_integer([:positive, :monotonic])}",
        description: "Obtain income documentation",
        status: :open,
        due_at: nil
      },
      Map.new(overrides)
    )
  end

  @doc "Build a validated `%Goal{}` from `goal_attrs/1`."
  @spec goal(map() | keyword()) :: Goal.t()
  def goal(overrides \\ %{}), do: Goal.new(goal_attrs(overrides))

  @doc """
  Catalog of invalid `Goal.new/1` inputs, one per violated field invariant.
  Each element is `{label, attrs}`; every `attrs` raises `ArgumentError`.
  """
  @spec invalid_goal_variants() :: [{atom(), map()}]
  def invalid_goal_variants do
    [
      {:goal_id_empty, goal_attrs(%{goal_id: ""})},
      {:goal_id_not_binary, goal_attrs() |> Map.put(:goal_id, 1)},
      {:description_empty, goal_attrs(%{description: ""})},
      {:status_invalid, goal_attrs() |> Map.put(:status, :bogus)},
      {:due_at_not_datetime, goal_attrs() |> Map.put(:due_at, "2026-01-01")}
    ]
  end

  @doc "Valid attribute map for `LoanActor.State.new/1` — a fresh `:spawned` loan."
  @spec state_attrs(map() | keyword()) :: map()
  def state_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        loan_id: unique_loan_id(),
        status: :spawned,
        goals: [],
        context: %{},
        version: 0,
        last_heartbeat_at: nil
      },
      Map.new(overrides)
    )
  end

  @doc "Build a validated `%LoanActor.State{}` from `state_attrs/1`."
  @spec state(map() | keyword()) :: State.t()
  def state(overrides \\ %{}), do: State.new(state_attrs(overrides))

  @doc """
  A valid state already at `status` — used to exercise every status enum
  value (boundary coverage, FT-010) and to build the "from" side of a
  transition test (FT-011).
  """
  @spec state_at(State.status(), map() | keyword()) :: State.t()
  def state_at(status, overrides \\ %{}) do
    state(Map.merge(%{status: status}, Map.new(overrides)))
  end

  @doc """
  Catalog of invalid `State.new/1` inputs, one per violated field invariant.
  """
  @spec invalid_state_variants() :: [{atom(), map()}]
  def invalid_state_variants do
    [
      {:loan_id_empty, state_attrs(%{loan_id: ""})},
      {:status_invalid, state_attrs() |> Map.put(:status, :bogus)},
      {:goals_not_list, state_attrs() |> Map.put(:goals, "nope")},
      {:goals_wrong_element, state_attrs() |> Map.put(:goals, [%{}])},
      {:context_not_map, state_attrs() |> Map.put(:context, [])},
      {:version_negative, state_attrs() |> Map.put(:version, -1)},
      {:last_heartbeat_at_not_datetime, state_attrs() |> Map.put(:last_heartbeat_at, "now")}
    ]
  end

  # ---- Event factories (FT-013) ----
  #
  # Discovery checklist: schema source of truth is data-model.md `%Event{}` +
  # its source/type enums. Scenario classes: happy (event_attrs/event
  # defaults), boundary (minimal event_id, empty payload map -- both still
  # valid; every source/type enum value), invalid
  # (invalid_event_variants/0 -- one per validate/1 rule, each collapsing to
  # the documented {:error, :invalid_event} shape). Deterministic: fixed
  # timestamp (default_timestamp/0, already used by the diary factories).

  @doc "Valid attribute map for building a `%LoanActor.Event{}` — source defaults to :test."
  @spec event_attrs(map() | keyword()) :: map()
  def event_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        event_id: "EVT-#{System.unique_integer([:positive, :monotonic])}",
        source: :test,
        type: :document_uploaded,
        payload: %{},
        created_at: default_timestamp(),
        received_at: default_timestamp()
      },
      Map.new(overrides)
    )
  end

  @doc "Build an `%Event{}` from `event_attrs/1` (not validated — pair with `Event.validate/1`)."
  @spec event(map() | keyword()) :: Event.t()
  def event(overrides \\ %{}), do: struct!(Event, event_attrs(overrides))

  @doc """
  Catalog of invalid `%Event{}` attribute maps, one per `validate/1` rule.
  Each element is `{label, attrs}`; `Event.validate(struct!(Event, attrs))`
  returns `{:error, :invalid_event}` for every one.
  """
  @spec invalid_event_variants() :: [{atom(), map()}]
  def invalid_event_variants do
    [
      {:event_id_nil, event_attrs() |> Map.put(:event_id, nil)},
      {:event_id_empty, event_attrs(%{event_id: ""})},
      {:event_id_not_binary, event_attrs() |> Map.put(:event_id, 42)},
      {:source_nil, event_attrs() |> Map.put(:source, nil)},
      {:source_invalid, event_attrs() |> Map.put(:source, :borrower)},
      {:type_nil, event_attrs() |> Map.put(:type, nil)},
      {:type_invalid, event_attrs() |> Map.put(:type, :not_a_real_event)},
      {:payload_nil, event_attrs() |> Map.put(:payload, nil)},
      {:payload_not_map, event_attrs() |> Map.put(:payload, "not a map")},
      {:created_at_nil, event_attrs() |> Map.put(:created_at, nil)},
      {:created_at_not_datetime, event_attrs() |> Map.put(:created_at, "2026-01-01")},
      {:received_at_nil, event_attrs() |> Map.put(:received_at, nil)},
      {:received_at_not_datetime, event_attrs() |> Map.put(:received_at, "2026-01-01")}
    ]
  end

  # ---- HITL request/response factories (FT-023 map form; FT-028 real structs) ----
  #
  # Discovery checklist: schema source of truth is data-model.md's
  # %LoanActor.HITLRequest{}/%LoanActor.HITLResponse{} tables. Scenario
  # classes: happy (attrs/struct defaults), invalid
  # (invalid_hitl_request_variants/invalid_hitl_response_variants — one
  # per validator rule). Deterministic: fixed timestamp, unique ids from
  # the shared monotonic-counter mechanism.

  @doc """
  Plain map matching data-model.md's `%HITLRequest{}` fields
  (`request_id`, `loan_id`, `prompt`, `options`, `created_at`) — used by
  `AGUI.Encoder.hitl_request_event/2`, which accepts a plain map rather
  than depending on `LoanActor.HITLRequest` (FT-023's own scope note).
  """
  @spec hitl_request_attrs(map() | keyword()) :: map()
  def hitl_request_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        request_id: "HITL-#{System.unique_integer([:positive, :monotonic])}",
        loan_id: unique_loan_id(),
        prompt: "Approve the ambiguous document?",
        options: ["approve", "reject"],
        created_at: default_timestamp()
      },
      Map.new(overrides)
    )
  end

  @doc "Build a validated `%LoanActor.HITLRequest{}` from `hitl_request_attrs/1`."
  @spec hitl_request(map() | keyword()) :: HITLRequest.t()
  def hitl_request(overrides \\ %{}), do: HITLRequest.new(hitl_request_attrs(overrides))

  @doc """
  Catalog of invalid `HITLRequest.new/1` inputs, one per violated field
  invariant. Each element is `{label, attrs}`; every `attrs` raises `ArgumentError`.
  """
  @spec invalid_hitl_request_variants() :: [{atom(), map()}]
  def invalid_hitl_request_variants do
    [
      {:request_id_empty, hitl_request_attrs(%{request_id: ""})},
      {:loan_id_empty, hitl_request_attrs(%{loan_id: ""})},
      {:prompt_empty, hitl_request_attrs(%{prompt: ""})},
      {:options_empty, hitl_request_attrs() |> Map.put(:options, [])},
      {:options_not_list, hitl_request_attrs() |> Map.put(:options, "approve")},
      {:options_bad_element, hitl_request_attrs() |> Map.put(:options, ["approve", ""])},
      {:created_at_not_datetime, hitl_request_attrs() |> Map.put(:created_at, "2026-01-01")}
    ]
  end

  @doc "Valid attribute map for `LoanActor.HITLResponse.new/1`."
  @spec hitl_response_attrs(map() | keyword()) :: map()
  def hitl_response_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        request_id: "HITL-#{System.unique_integer([:positive, :monotonic])}",
        decision: "approve",
        comment: nil,
        operator_id: "operator-1",
        responded_at: default_timestamp()
      },
      Map.new(overrides)
    )
  end

  @doc "Build a validated `%LoanActor.HITLResponse{}` from `hitl_response_attrs/1`."
  @spec hitl_response(map() | keyword()) :: HITLResponse.t()
  def hitl_response(overrides \\ %{}), do: HITLResponse.new(hitl_response_attrs(overrides))

  @doc """
  Catalog of invalid `HITLResponse.new/1` inputs, one per violated field
  invariant. Each element is `{label, attrs}`; every `attrs` raises `ArgumentError`.
  """
  @spec invalid_hitl_response_variants() :: [{atom(), map()}]
  def invalid_hitl_response_variants do
    [
      {:request_id_empty, hitl_response_attrs(%{request_id: ""})},
      {:decision_empty, hitl_response_attrs(%{decision: ""})},
      {:comment_not_binary, hitl_response_attrs() |> Map.put(:comment, 42)},
      {:operator_id_empty, hitl_response_attrs(%{operator_id: ""})},
      {:responded_at_not_datetime, hitl_response_attrs() |> Map.put(:responded_at, "2026-01-01")}
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

  @doc """
  Valid attribute map for building a `%LoanActor.Skill{}` directly (no
  `LoanActor.Skill.Loader` parsing round-trip). Defaults name a tool
  (`verify_diary_chain`) that is always present in the real
  `Tool.Registry`, so `write_skill_pack!/2`'s on-disk form of these same
  attrs is loader-valid out of the box. `:gate_id`/`:rule` (intent 0003,
  ADH-005) default to `nil` — an ordinary, non-gate pack; set both (never
  just one) plus `tools_required: ["evaluate_gate"]` to build a gate pack.
  `:rule`, when set, is the same nested-map shape `Factory.gate_attrs/1`
  uses (string keys `"combinator"`/`"predicates"`).
  """
  @spec skill_attrs(map() | keyword()) :: map()
  def skill_attrs(overrides \\ %{}) do
    overrides = Map.new(overrides)
    id = Map.get(overrides, :id, "0099-factory-skill")

    Map.merge(
      %{
        id: id,
        name: "factory-skill",
        version: "1.0.0",
        description: "A factory-built skill pack for testing.",
        tools_required: ["verify_diary_chain"],
        body: "Body.",
        files: [],
        path: Path.join("priv/skills", id),
        gate_id: nil,
        rule: nil
      },
      overrides
    )
  end

  @doc """
  Build a `%LoanActor.Skill{}` directly from `skill_attrs/1` — never
  loader-validated (see `write_skill_pack!/2` for that). `skill_attrs/1`'s
  `:gate_id`/`:rule` keys feed `write_skill_pack!/2`'s on-disk rendering
  only — they aren't `%Skill{}` fields (its `:gate` field holds a parsed
  `%LoanActor.Gate{}`, never raw front-matter), so they're dropped here.
  """
  @spec skill(map() | keyword()) :: Skill.t()
  def skill(overrides \\ %{}) do
    struct!(Skill, Map.drop(skill_attrs(overrides), [:gate_id, :rule]))
  end

  @doc """
  Write a real `SKILL.md` pack under `dir` (creating the pack's own
  subdirectory as needed), in the restricted front-matter grammar
  `LoanActor.Skill.Loader` parses — for tests that need `Loader.load_pack/1`
  or `load_all/1` to see a genuine on-disk pack rather than a `%Skill{}`
  built in memory. `overrides` feeds `skill_attrs/1` (`:id` names the pack
  subdirectory; `:name`/`:version`/`:description`/`:tools_required`/`:body`
  become the front-matter + body). Returns `dir` itself (not the pack
  subdirectory), ready to hand straight to `Application.put_env(:loan_actor,
  :skills_dir, dir)` or `Loader.load_all(dir: dir)`.
  """
  @spec write_skill_pack!(Path.t(), map() | keyword()) :: Path.t()
  def write_skill_pack!(dir, overrides \\ %{}) do
    attrs = skill_attrs(overrides)
    pack_dir = Path.join(dir, attrs.id)
    File.mkdir_p!(pack_dir)

    File.write!(Path.join(pack_dir, "SKILL.md"), """
    ---
    name: #{attrs.name}
    version: #{attrs.version}
    description: #{attrs.description}
    tools_required: [#{Enum.join(attrs.tools_required, ", ")}]
    #{gate_front_matter(attrs.gate_id, attrs.rule)}---

    #{attrs.body}
    """)

    dir
  end

  # ---- gate-pack front-matter rendering (contracts/gate-pack-format.md's
  # ONE exception to flat key: value lines — mirrors LoanActor.Gate's own
  # hand-rolled, indentation-tracking parser exactly, in reverse) ----

  defp gate_front_matter(nil, nil), do: ""
  defp gate_front_matter(gate_id, nil), do: "gate_id: #{gate_id}\n"
  defp gate_front_matter(nil, rule), do: "rule:\n#{render_rule_map(rule, 2)}\n"

  defp gate_front_matter(gate_id, rule) do
    "gate_id: #{gate_id}\nrule:\n#{render_rule_map(rule, 2)}\n"
  end

  defp render_rule_map(map, indent) do
    map
    |> Map.to_list()
    |> Enum.map(&render_rule_pair(String.duplicate(" ", indent), &1, indent))
    |> Enum.join("\n")
  end

  defp render_rule_pair(pad, {key, value}, indent) when is_map(value) do
    "#{pad}#{key}:\n" <> render_rule_map(value, indent + 2)
  end

  defp render_rule_pair(pad, {key, value}, indent) when is_list(value) do
    "#{pad}#{key}:\n" <> render_rule_list(value, indent + 2)
  end

  defp render_rule_pair(pad, {key, value}, _indent), do: "#{pad}#{key}: #{value}"

  defp render_rule_list(items, item_indent) do
    items
    |> Enum.map(&render_rule_list_item(&1, item_indent))
    |> Enum.join("\n")
  end

  defp render_rule_list_item(map, item_indent) do
    continuation_indent = item_indent + 2

    map
    |> Map.to_list()
    |> Enum.with_index()
    |> Enum.map(fn {{key, value}, index} ->
      pad =
        if index == 0 do
          String.duplicate(" ", item_indent) <> "- "
        else
          String.duplicate(" ", continuation_indent)
        end

      render_rule_pair(pad, {key, value}, continuation_indent)
    end)
    |> Enum.join("\n")
  end

  @doc """
  A realistic linked `{tool_invoked_entry, tool_completed_or_failed_entry}`
  pair, continuing from `tail` (or the genesis entry when `tail` is
  `nil`) — mirrors exactly what `LoanActor.Server`'s `invoke_tool/4` +
  `append_tool_result_entry/3` write to the diary per real tool
  invocation (`payload_hash` computed from the same `{"tool",
  "invocation_id", ...}` payload shape, JSON-encoded then hashed).
  `overrides` may set `:tool_name` (default `"verify_diary_chain"`),
  `:outcome` (`:completed` | `:failed`, default `:completed`), and
  `:loan_id` (only meaningful when `tail` is `nil`).
  """
  @spec tool_invocation_diary_pair(Entry.t() | nil, map() | keyword()) :: {Entry.t(), Entry.t()}
  def tool_invocation_diary_pair(tail, overrides \\ %{}) do
    overrides = Map.new(overrides)
    tool_name = Map.get(overrides, :tool_name, "verify_diary_chain")
    outcome = Map.get(overrides, :outcome, :completed)
    invocation_id = "inv-#{System.unique_integer([:positive, :monotonic])}"

    invoked_payload = %{"tool" => tool_name, "invocation_id" => invocation_id, "args_hash" => "AA=="}

    invoked =
      next_entry(
        tail,
        overrides
        |> Map.take([:loan_id])
        |> Map.merge(%{type: :tool_invoked, payload_hash: Chain.hash(Jason.encode!(invoked_payload))})
      )

    {result_type, result_payload} =
      case outcome do
        :completed ->
          {:tool_completed, %{"tool" => tool_name, "invocation_id" => invocation_id, "result_hash" => "BB=="}}

        :failed ->
          {:tool_failed, %{"tool" => tool_name, "invocation_id" => invocation_id, "reason" => "simulated_failure"}}
      end

    completed =
      next_entry(invoked, %{type: result_type, payload_hash: Chain.hash(Jason.encode!(result_payload))})

    {invoked, completed}
  end

  # ---- PII corpus generators (FT-014) ----
  #
  # Discovery checklist: schema source of truth is priv/pii_patterns.yml's
  # four categories (ssn, account_number, routing_number, date_of_birth).
  # Scenario classes: happy/clean (letters + spaces only -- provably cannot
  # match any digit/date-shaped pattern), adversarial/dirty (one generator
  # per category, each guaranteed to match). Feeds the 200-run synthetic
  # corpus property test (test-data-forge: a generative corpus, not 200
  # hand-rolled fixtures).

  @doc "A string value guaranteed to never match any configured PII pattern (letters + spaces only)."
  @spec pii_clean_value_gen() :: StreamData.t(String.t())
  def pii_clean_value_gen do
    StreamData.string(?a..?z, min_length: 1, max_length: 8)
    |> StreamData.list_of(min_length: 1, max_length: 4)
    |> StreamData.map(&Enum.join(&1, " "))
  end

  @doc "A string value guaranteed to match one of the four configured PII pattern categories."
  @spec pii_dirty_value_gen() :: StreamData.t(String.t())
  def pii_dirty_value_gen do
    StreamData.one_of([
      pii_ssn_gen(),
      pii_account_number_gen(),
      pii_routing_number_gen(),
      pii_date_of_birth_gen()
    ])
  end

  defp pii_digits(n), do: StreamData.string(?0..?9, length: n)

  defp pii_ssn_gen do
    StreamData.tuple({pii_digits(3), pii_digits(2), pii_digits(4)})
    |> StreamData.map(fn {a, b, c} -> "SSN: #{a}-#{b}-#{c}" end)
  end

  defp pii_account_number_gen do
    StreamData.integer(8..17)
    |> StreamData.bind(&pii_digits/1)
    |> StreamData.map(fn digits -> "account #{digits} on file" end)
  end

  defp pii_routing_number_gen do
    pii_digits(9) |> StreamData.map(fn digits -> "routing #{digits}" end)
  end

  defp pii_date_of_birth_gen do
    StreamData.tuple({
      StreamData.integer(1900..2019),
      StreamData.integer(1..12),
      StreamData.integer(1..28)
    })
    |> StreamData.map(fn {y, m, d} -> "born #{y}-#{pii_pad(m)}-#{pii_pad(d)}" end)
  end

  defp pii_pad(n), do: n |> Integer.to_string() |> String.pad_leading(2, "0")

  # ---- Replay factories (FT-009) ----
  #
  # Discovery checklist: builds diary chains whose entry types follow a
  # given event-type sequence, for tests that fold State.transition/2 over
  # a diary and must reproduce the sequence that produced it. Scenario
  # classes: happy (a full-coverage fixed walk, see replay_test.exs),
  # property (legal_event_walk_gen/2 -- every generated walk is, by
  # construction, a valid path through LoanActor.State.Model's graph).

  @doc """
  A valid diary chain for one loan: genesis entry typed `:spawned`,
  followed by one entry per `event_type` in `event_types` (in order).
  """
  @spec chain_with_event_types([atom()], map() | keyword()) :: [Entry.t()]
  def chain_with_event_types(event_types, overrides \\ %{}) do
    overrides = Map.new(overrides)
    loan_id = Map.get(overrides, :loan_id, unique_loan_id())
    genesis = entry(Map.merge(overrides, %{loan_id: loan_id, type: :spawned}))

    {chain, _tail} =
      Enum.reduce(event_types, {[genesis], genesis}, fn event_type, {acc, tail} ->
        next = next_entry(tail, %{type: event_type})
        {[next | acc], next}
      end)

    Enum.reverse(chain)
  end

  @doc """
  StreamData generator producing a random LEGAL walk through
  `LoanActor.State.Model`'s graph, starting at `:spawned`. Stops at a
  terminal status (no next events, e.g. `:completed`) or after `max_steps`
  transitions, whichever comes first. Built from proper `StreamData.bind`
  combinators (not raw `:rand`), so it participates in the seeded,
  shrinkable random stream like every other generator here.
  """
  @spec legal_event_walk_gen(atom(), pos_integer()) :: StreamData.t([atom()])
  def legal_event_walk_gen(status \\ :spawned, max_steps \\ 10)

  def legal_event_walk_gen(_status, 0), do: StreamData.constant([])

  def legal_event_walk_gen(status, max_steps) do
    case Model.next_events_for(status) do
      [] ->
        StreamData.constant([])

      events ->
        StreamData.bind(StreamData.member_of(events), fn event ->
          {:ok, next_status} = Model.next_status(status, event)

          StreamData.bind(legal_event_walk_gen(next_status, max_steps - 1), fn rest ->
            StreamData.constant([event | rest])
          end)
        end)
    end
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

  # ---- Assessment factories (intent 0003, ADH-002) ----

  @doc """
  Valid attribute map for `LoanActor.Assessment.new/1`. Defaults produce a
  neutral assessment (unknown completeness, no goal ages, n/a SLA) for a
  fresh loan at version 0.
  """
  @spec assessment_attrs(map() | keyword()) :: map()
  def assessment_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        loan_id: unique_loan_id(),
        document_completeness: :unknown,
        goal_ages: %{},
        sla_state: :n_a,
        data_quality_flags: [],
        computed_at_version: 0
      },
      Map.new(overrides)
    )
  end

  @doc "Build a validated `%LoanActor.Assessment{}` from `assessment_attrs/1`."
  @spec assessment(map() | keyword()) :: Assessment.t()
  def assessment(overrides \\ %{}), do: Assessment.new(assessment_attrs(overrides))

  @doc """
  Catalog of invalid `LoanActor.Assessment.new/1` attribute maps —
  `{label, attrs}`. Each raises `ArgumentError`.
  """
  @spec invalid_assessment_variants() :: [{atom(), map()}]
  def invalid_assessment_variants do
    [
      {:bad_document_completeness, assessment_attrs(%{document_completeness: :maybe})},
      {:bad_goal_ages_not_map, assessment_attrs(%{goal_ages: []})},
      {:bad_goal_ages_negative, assessment_attrs(%{goal_ages: %{"G-1" => -1}})},
      {:bad_sla_state, assessment_attrs(%{sla_state: :overdue})},
      {:bad_data_quality_flags, assessment_attrs(%{data_quality_flags: ["not_an_atom"]})},
      {:bad_version_negative, assessment_attrs(%{computed_at_version: -1})}
    ]
  end

  # ---- Gate factories (intent 0003, ADH-003) ----

  @doc """
  Valid attribute map for `LoanActor.Gate.new/1` — front-matter-decoded
  shape (string keys inside `rule`, mirroring how the loader hands
  `LoanActor.Skill.Loader`-parsed content to `Gate.new/1`). Defaults to a
  single `eq` predicate checking `assessment.document_completeness`.
  """
  @spec gate_attrs(map() | keyword()) :: map()
  def gate_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        gate_id: "document-completeness",
        version: "1.0.0",
        pack_id: "0002-demo-gate-pack",
        rule: %{
          "combinator" => "all",
          "predicates" => [
            %{"field" => "assessment.document_completeness", "op" => "eq", "value" => "complete"}
          ]
        }
      },
      Map.new(overrides)
    )
  end

  @doc "Build a validated `%LoanActor.Gate{}` from `gate_attrs/1`. Raises if invalid (test convenience; `Gate.new/1` itself returns `{:ok, _} | {:error, _}`)."
  @spec gate(map() | keyword()) :: Gate.t()
  def gate(overrides \\ %{}) do
    {:ok, gate} = Gate.new(gate_attrs(overrides))
    gate
  end

  @doc """
  Catalog of invalid `LoanActor.Gate.new/1` attribute maps — `{label, attrs}`.
  Each returns `{:error, _}` (never raises; mirrors the loader's own
  reject-with-reason discipline).
  """
  @spec invalid_gate_variants() :: [{atom(), map()}]
  def invalid_gate_variants do
    [
      {:missing_gate_id, gate_attrs(%{gate_id: nil}) |> Map.delete(:gate_id)},
      {:missing_rule, gate_attrs() |> Map.delete(:rule)},
      {:bad_combinator, gate_attrs(%{rule: %{"combinator" => "xor", "predicates" => []}})},
      {:empty_predicates, gate_attrs(%{rule: %{"combinator" => "all", "predicates" => []}})},
      {:bad_op, gate_attrs(%{
         rule: %{
           "combinator" => "all",
           "predicates" => [%{"field" => "assessment.sla_state", "op" => "matches", "value" => "on_track"}]
         }
       })},
      {:missing_value_for_eq,
       gate_attrs(%{
         rule: %{
           "combinator" => "all",
           "predicates" => [%{"field" => "assessment.sla_state", "op" => "eq"}]
         }
       })},
      {:nested_two_levels_deep,
       gate_attrs(%{
         rule: %{
           "combinator" => "all",
           "predicates" => [
             %{
               "combinator" => "any",
               "predicates" => [
                 %{
                   "combinator" => "all",
                   "predicates" => [%{"field" => "assessment.sla_state", "op" => "present"}]
                 }
               ]
             }
           ]
         }
       })}
    ]
  end
end
