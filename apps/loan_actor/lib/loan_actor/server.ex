defmodule LoanActor.Server do
  @moduledoc """
  The loan actor's reactive loop (FT-017): `handle_call({:send_event, _},
  ...)`. Pipeline order per the task's literal deliverable text — PIIGuard
  → idempotency → transition → diary append. Runs as a single GenServer
  per `loan_id` (`LoanActor.Registry`'s `:unique` keys enforce this), so
  every step below is effectively atomic with respect to OTHER events for
  the SAME loan: no other `:send_event` call for this loan can interleave
  (a GenServer serializes its own mailbox).

  The diary store is configurable via `config :loan_actor, :diary_store`
  (Mnesia in prod/dev, File in test — `config/*.exs`); `init/1` calls the
  configured store's own `init/1` (idempotent per its behaviour contract),
  so a fresh boot is self-sufficient regardless of who spawns first.

  On boot: an empty diary means a brand-new loan (append the `:spawned`
  genesis entry); a non-empty diary means rehydration — replay every entry
  whose `type` is a real event type (per `LoanActor.State.Model`) through
  `State.transition/2`, skipping diary-only administrative entries
  (`:spawned`, `:illegal_transition_attempted`, …) that never represent a
  legal graph edge.

  ## Periodic loop (FT-018)

  `handle_info(:heartbeat, _)` fires on a fixed-origin `:timer.send_interval/2`
  clock (started once in `init/1`), every `config :loan_actor, :heartbeat_ms`
  (default 60_000; test env overrides to 100 for fast cadence tests,
  SC-011). A fixed external timer — rather than a `Process.send_after`
  self-reschedule from when each handler finishes — keeps cadence
  accurate regardless of how long any single heartbeat's processing takes
  (diary I/O, tool invocation, skill loading from disk); a
  self-rescheduling design would accumulate drift proportional to that
  per-tick work, undercounting ticks over a fixed window (caught by
  SC-011's own cadence test during development). Each firing:

  1. Appends a `:heartbeat` diary entry carrying a hash of the current
     `%State{}` and records `last_heartbeat_at` (`State.record_heartbeat/2`).
  2. Unconditionally invokes the `verify_diary_chain` tool as a periodic
     self-check (not skill-gated — a housekeeping health check the actor
     always performs on itself), applying its effect by actually calling
     the diary store's `verify_chain/1` and logging the real result as
     `:diary_chain_verified`.
  3. Trigger-matches skills (`LoanActor.Skill.Loader.match/2`) against the
     current loan context; each match is diary-logged `:skill_activated`.
     For a matched skill naming `set_goal` in `tools_required`, the tool
     is invoked with `%{"description" => skill.description}` — the
     skill's own trigger text becomes the new goal's content, since no
     document specifies any other source of arguments for a
     skill-triggered tool (confirmed 2026-07-21; no per-tool argument
     binding mechanism exists in `contracts/skill-format.md`).

  Every tool invocation (constitution Principle VIII) appends
  `:tool_invoked` before execution and `:tool_completed`/`:tool_failed`
  after — payload carries the tool name, invocation id, and a hash of the
  (PII-guarded) args / result, never the raw values (`contracts/tool-behaviour.md`
  invariant 4). No AG-UI streaming yet — the encoder exists (FT-023) but the
  SSE stream (FT-024) does not, so tool invocations here are diary-proven
  only; live event delivery lands once FT-024/025 wire a real subscriber.

  ## Planning loop (FT-019)

  `handle_info(:plan, _)` fires as a **self-message sent from the reactive
  pipeline** — not a timer — specifically after a successful `:goal_set`
  transition (a narrower, literal reading of the task's "when goals are
  set", not "any state change re-plans"; see `maybe_trigger_planning/1`).
  Each firing trigger-matches skills against the current loan context
  (`event_type: :plan`); for a matched skill naming `request_document` in
  `tools_required`, the tool is invoked with a `doc_type` keyword-matched
  from open goals' descriptions (one of `"income"`/`"identity"`/
  `"appraisal"`), defaulting to `"income"` if none mention one — confirmed
  2026-07-21, since neither the `Goal` struct nor the skill-format contract
  carries a structured `doc_type` field. Unlike the periodic loop's
  `set_goal`, `request_document`'s effect is purely informational (an
  outbound request, not a state mutation) — SC-012 asks only for the
  tool's own diary pair and AG-UI sequence, no extra effect-application
  diary entry.

  ## Subscribe (FT-025)

  `subscribe/2` starts a supervised `LoanActor.AGUI.Subscriber`
  (`LoanActor.AGUI.Stream`, FT-024) delivering to the calling process, and
  registers it in `gen_state.subscribers` (a `{monitor_ref, subscriber_pid}`
  list). The loan actor **broadcasts on every diary append** — `append_entry/4`
  is the single, centralized call site every code path in this module
  already funnels through, so every diary entry (reactive, heartbeat, tool
  invocation, planning) automatically reaches every current subscriber as a
  `CustomEvent diary_entry`, with no risk of a call site forgetting to
  broadcast. A successful reactive `State.transition/2` additionally
  broadcasts a `StateDelta` — per the AG-UI ordering guarantee, always
  immediately after that transition's own `CustomEvent diary_entry`.

  **StateDelta scope note**: the patch is a single whole-state `"replace"`
  operation at the root path, not a computed incremental diff. This is a
  valid RFC 6902 JSON Patch array (the contract does not mandate minimal
  patches) and avoids building a full diffing algorithm not asked for by
  this task; a real diff is a defensible later refinement, not a breaking
  change (consumers already handle arbitrary patch arrays per RFC 6902).

  If a subscribing process dies, `handle_info({:DOWN, ref, :process, _pid,
  _reason}, _)` removes it from `gen_state.subscribers` — a dead
  subscriber is never broadcast to again.

  ## Tool-call streaming (FT-028; closes a gap left open by FT-018/019's
  own moduledoc notes, which predate FT-024/025's subscriber wiring)

  `invoke_tool/4` streams `ToolCallStart → ToolCallArgs → ToolCallEnd` for
  every invocation immediately after the `:tool_invoked` diary entry, per
  `contracts/ag-ui-events.md`'s tool-call semantics. `ToolCallResult`
  follows immediately for a synchronous result (`{:ok, effects}` or
  `{:error, reason}` — a tool failure still completes the sequence, per
  the contract, with `content` carrying the error shape). The one
  foundation exception is `request_operator_approval`'s `{:pending, id}`
  result: `ToolCallResult` is deferred until `respond_hitl/3` delivers the
  operator's decision (or observes a conflict) — `ToolCallEnd` through
  `ToolCallResult` is the only gap a strict client must tolerate other
  events interleaving into.

  ## HITL (FT-028)

  `request_operator_approval`'s `{:pending, request_id}` result parks a
  `%LoanActor.HITLRequest{}` in `gen_state.hitl_requests` (keyed by
  `request_id`, which doubles as the tool's `invocation_id`/AG-UI
  `tool_call_id`) and broadcasts the already-specified `CustomEvent
  name="hitl_request"`. `respond_hitl/3` completes the deferred
  `ToolCallResult` for the first response; a later response for an
  already-answered `request_id` is a conflict — it does NOT get a second
  `ToolCallResult` for the same `tool_call_id` (AG-UI's contract has
  exactly one Result per invocation), it gets the already-specified
  `CustomEvent name="hitl_conflict"` plus an `:approval_conflict` diary
  entry. Scope note: `respond_hitl/3` does not itself call
  `State.transition/2` — FT-028's literal deliverable text describes only
  the diary entry and delivering the deferred `ToolCallResult`; the
  `operator_approval_granted`/`operator_approval_denied` state edges
  remain reachable through the normal `send_event/2` reactive path, unchanged.

  Known limitation (not asked for by any task): a supervisor restart loses
  `gen_state.hitl_requests` (rebuilt empty on `init/1`) — a diary entry
  carries only a hash of tool args, not enough to reconstruct a pending
  request's prompt/options, and no task asks for cross-restart HITL
  correlation.
  """

  use GenServer

  alias LoanActor.AGUI.Encoder
  alias LoanActor.AGUI.Stream, as: AGUIStream
  alias LoanActor.AGUI.Subscriber
  alias LoanActor.Diary.Chain
  alias LoanActor.Diary.Entry
  alias LoanActor.Event
  alias LoanActor.HITLRequest
  alias LoanActor.Idempotency
  alias LoanActor.IllegalTransitionError
  alias LoanActor.PIIGuard
  alias LoanActor.Registry
  alias LoanActor.Skill.Loader, as: SkillLoader
  alias LoanActor.State
  alias LoanActor.State.Model
  alias LoanActor.Tool.Context
  alias LoanActor.Tool.Registry, as: ToolRegistry

  @periodic_skill_tools ~w(set_goal)

  @spec start_link(String.t()) :: GenServer.on_start()
  def start_link(loan_id) do
    GenServer.start_link(__MODULE__, loan_id, name: Registry.via(loan_id))
  end

  @doc "Send `event` to the loan actor at `pid`. See `contracts/loan-actor-api.md`."
  @spec send_event(pid(), Event.t()) ::
          {:ok, non_neg_integer()}
          | {:duplicate, non_neg_integer()}
          | {:error, term()}
  def send_event(pid, %Event{} = event) do
    GenServer.call(pid, {:send_event, event})
  end

  @doc "The loan actor's current in-memory state."
  @spec state(pid()) :: State.t()
  def state(pid), do: GenServer.call(pid, :state)

  @doc """
  Subscribe the calling process to `pid`'s AG-UI event stream. See
  `contracts/loan-actor-api.md`: returns a monitor ref; the caller
  receives `{:ag_ui_event, ref, event}` messages.
  """
  @spec subscribe(pid(), keyword()) :: {:ok, reference()} | {:error, term()}
  def subscribe(pid, opts \\ []) do
    GenServer.call(pid, {:subscribe, self(), opts})
  end

  @doc """
  Deliver the operator's decision for a pending HITL request. See
  `contracts/loan-actor-api.md`. First response wins (`:ok`); a later
  response for an already-answered `request_id` is `{:conflict,
  existing_response}`; an unknown `request_id` is `{:error, :not_found}`.
  """
  @spec respond_hitl(pid(), String.t(), LoanActor.HITLResponse.t()) ::
          :ok | {:conflict, LoanActor.HITLResponse.t()} | {:error, :not_found}
  def respond_hitl(pid, request_id, %LoanActor.HITLResponse{} = response) do
    GenServer.call(pid, {:respond_hitl, request_id, response})
  end

  # ---- GenServer callbacks ----

  @impl GenServer
  def init(loan_id) do
    store = diary_store()
    :ok = store.init([])

    case store.tail(loan_id) do
      {:ok, nil} -> start_with_heartbeat(spawn_fresh(loan_id, store))
      {:ok, _tail} -> start_with_heartbeat(rehydrate(loan_id, store))
      {:error, reason} -> {:stop, reason}
    end
  end

  defp start_with_heartbeat(gen_state) do
    {:ok, _tref} = :timer.send_interval(heartbeat_ms(), :heartbeat)
    {:ok, gen_state}
  end

  # loop: reactive
  @impl GenServer
  def handle_call({:send_event, %Event{} = event}, _from, gen_state) do
    case Event.validate(event) do
      {:error, :invalid_event} = error -> {:reply, error, gen_state}
      :ok -> handle_valid_event(event, gen_state)
    end
  end

  # loop: reactive
  @impl GenServer
  def handle_call(:state, _from, gen_state), do: {:reply, gen_state.state, gen_state}

  # External HITL answer (FT-028) — not a loop the actor drives itself,
  # but handle_call/3 still requires a tag; reactive fits best since this
  # is externally-triggered like send_event/subscribe.
  # loop: reactive
  @impl GenServer
  def handle_call({:respond_hitl, request_id, response}, _from, gen_state) do
    case Map.fetch(gen_state.hitl_requests, request_id) do
      :error -> {:reply, {:error, :not_found}, gen_state}
      {:ok, %{response: nil}} -> handle_fresh_hitl_response(gen_state, request_id, response)
      {:ok, %{response: existing}} -> handle_conflicting_hitl_response(gen_state, request_id, existing)
    end
  end

  # loop: reactive
  @impl GenServer
  def handle_call({:subscribe, caller, opts}, _from, gen_state) do
    ref = Process.monitor(caller)

    case AGUIStream.start_subscriber(caller, ref, opts) do
      {:ok, subscriber_pid} ->
        new_subscribers = [{ref, subscriber_pid} | gen_state.subscribers]
        {:reply, {:ok, ref}, %{gen_state | subscribers: new_subscribers}}

      {:error, reason} ->
        Process.demonitor(ref, [:flush])
        {:reply, {:error, reason}, gen_state}
    end
  end

  # loop: periodic
  @impl GenServer
  def handle_info(:heartbeat, gen_state) do
    {:noreply, run_heartbeat(gen_state)}
  end

  # loop: planning
  @impl GenServer
  def handle_info(:plan, gen_state) do
    {:noreply, run_planning(gen_state)}
  end

  # loop: reactive
  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, _reason}, gen_state) do
    new_subscribers = Enum.reject(gen_state.subscribers, fn {sub_ref, _pid} -> sub_ref == ref end)
    {:noreply, %{gen_state | subscribers: new_subscribers}}
  end

  # ---- reactive pipeline: PIIGuard -> idempotency -> transition -> diary ----

  defp handle_valid_event(event, gen_state) do
    case PIIGuard.apply(event.payload) do
      {:error, :pii_violation, paths} -> {:reply, {:error, {:pii_violation, paths}}, gen_state}
      {:ok, clean_payload, _redacted_paths} -> handle_clean_event(event, clean_payload, gen_state)
    end
  end

  defp handle_clean_event(event, clean_payload, gen_state) do
    case Idempotency.check_and_record(gen_state.loan_id, event.event_id, event.source) do
      {:duplicate, sequence} -> {:reply, {:duplicate, sequence}, gen_state}
      :fresh -> apply_event(event, clean_payload, gen_state)
    end
  end

  defp apply_event(event, clean_payload, gen_state) do
    %{loan_id: loan_id, state: state} = gen_state

    try do
      new_state = State.transition(state, event.type)
      {:ok, sequence} = append_entry(gen_state, event.type, Atom.to_string(event.source), clean_payload)
      :ok = Idempotency.record_sequence(loan_id, event.event_id, event.source, sequence)
      broadcast_state_delta(gen_state, new_state)
      maybe_trigger_planning(event.type)
      {:reply, {:ok, sequence}, %{gen_state | state: new_state}}
    rescue
      e in IllegalTransitionError ->
        payload = %{
          "attempted_event_type" => Atom.to_string(e.event_type),
          "from_status" => Atom.to_string(e.from)
        }

        {:ok, sequence} = append_entry(gen_state, :illegal_transition_attempted, "system", payload)
        :ok = Idempotency.record_sequence(loan_id, event.event_id, event.source, sequence)
        {:reply, {:error, {:illegal_transition, e.from, e.event_type}}, gen_state}
    end
  end

  # ---- HITL response handling (FT-028) ----

  defp handle_fresh_hitl_response(gen_state, request_id, response) do
    updated_requests = Map.update!(gen_state.hitl_requests, request_id, &%{&1 | response: response})
    gen_state = %{gen_state | hitl_requests: updated_requests}

    payload = %{
      "request_id" => request_id,
      "decision" => response.decision,
      "operator_id" => response.operator_id
    }

    {:ok, _seq} = append_entry(gen_state, :hitl_responded, "system", payload)

    content = %{
      "decision" => response.decision,
      "comment" => response.comment,
      "operator_id" => response.operator_id
    }

    gen_state = stream_tool_call_result(gen_state, request_id, content)
    {:reply, :ok, gen_state}
  end

  defp handle_conflicting_hitl_response(gen_state, request_id, existing_response) do
    payload = %{"request_id" => request_id, "existing_operator_id" => existing_response.operator_id}
    {:ok, _seq} = append_entry(gen_state, :approval_conflict, "system", payload)
    broadcast(gen_state, Encoder.hitl_conflict_event(gen_state.loan_id, request_id))
    {:reply, {:conflict, existing_response}, gen_state}
  end

  # Centralized so every code path in this module (reactive, heartbeat,
  # tool invocation, planning) automatically broadcasts — no call site can
  # forget to (FT-025).
  defp append_entry(gen_state, type, actor, payload) do
    %{loan_id: loan_id, store: store} = gen_state
    {:ok, tail} = store.tail(loan_id)

    entry =
      Entry.new(%{
        loan_id: loan_id,
        sequence: tail.sequence + 1,
        timestamp: DateTime.utc_now(),
        type: type,
        actor: actor,
        payload_hash: Chain.hash(Jason.encode!(payload)),
        prev_hash: Chain.next_prev_hash(tail)
      })

    case store.append(loan_id, entry) do
      {:ok, sequence} ->
        broadcast(gen_state, Encoder.diary_entry_event(loan_id, entry))
        {:ok, sequence}

      error ->
        error
    end
  end

  defp broadcast(gen_state, event) do
    Enum.each(gen_state.subscribers, fn {_ref, subscriber_pid} ->
      Subscriber.deliver(subscriber_pid, event)
    end)
  end

  defp broadcast_state_delta(gen_state, state) do
    patch = [%{"op" => "replace", "path" => "", "value" => encoder_state_value(state)}]
    broadcast(gen_state, Encoder.state_delta(gen_state.loan_id, patch))
  end

  # Encoder.state_delta/2 takes the patch array directly — reuse
  # state_snapshot/2's own "state" sub-shape by round-tripping through it,
  # rather than duplicating the struct -> JSON-safe-map logic here.
  defp encoder_state_value(state) do
    Encoder.state_snapshot("_", state)["state"]
  end

  # ---- boot / rehydration ----

  defp spawn_fresh(loan_id, store) do
    # The spawn payload is entirely system-generated (loan_id + timestamp,
    # no user-controlled data) — routing it through PIIGuard would be pure
    # ceremony with zero risk reduction, so it is hashed directly.
    payload = %{"loan_id" => loan_id, "spawned_at" => DateTime.to_iso8601(DateTime.utc_now())}

    genesis =
      Entry.new(%{
        loan_id: loan_id,
        sequence: 0,
        timestamp: DateTime.utc_now(),
        type: :spawned,
        actor: "system",
        payload_hash: Chain.hash(Jason.encode!(payload)),
        prev_hash: Entry.genesis_prev_hash()
      })

    {:ok, 0} = store.append(loan_id, genesis)

    %{
      loan_id: loan_id,
      state: State.new(%{loan_id: loan_id}),
      store: store,
      subscribers: [],
      hitl_requests: %{}
    }
  end

  defp rehydrate(loan_id, store) do
    event_types = MapSet.new(Model.event_types())

    state =
      loan_id
      |> then(&store.stream(&1, []))
      |> Enum.reduce(State.new(%{loan_id: loan_id}), fn entry, acc ->
        if MapSet.member?(event_types, entry.type) do
          State.transition(acc, entry.type)
        else
          acc
        end
      end)

    %{loan_id: loan_id, state: state, store: store, subscribers: [], hitl_requests: %{}}
  end

  defp diary_store, do: Application.get_env(:loan_actor, :diary_store, LoanActor.Diary.Mnesia)

  # ---- periodic loop (FT-018) ----

  defp heartbeat_ms, do: Application.get_env(:loan_actor, :heartbeat_ms, 60_000)

  defp run_heartbeat(gen_state) do
    gen_state
    |> log_heartbeat_entry()
    |> apply_record_heartbeat()
    |> run_verify_diary_chain()
    |> run_matched_skills()
  end

  defp log_heartbeat_entry(gen_state) do
    payload = %{"state_hash" => hash_term(gen_state.state)}
    {:ok, _seq} = append_entry(gen_state, :heartbeat, "system", payload)
    gen_state
  end

  defp apply_record_heartbeat(gen_state) do
    %{gen_state | state: State.record_heartbeat(gen_state.state, DateTime.utc_now())}
  end

  defp run_verify_diary_chain(gen_state) do
    {gen_state, result} = invoke_tool(gen_state, "verify_diary_chain", %{}, :periodic)

    case result do
      {:ok, %{verify_chain: true}} -> apply_verify_chain(gen_state)
      _other -> gen_state
    end
  end

  defp apply_verify_chain(gen_state) do
    %{loan_id: loan_id, store: store} = gen_state

    payload =
      case store.verify_chain(loan_id) do
        :ok -> %{"result" => "ok"}
        {:error, {:tamper, seq}} -> %{"result" => "tamper", "sequence" => seq}
        {:error, reason} -> %{"result" => "error", "reason" => inspect(reason)}
      end

    {:ok, _seq} = append_entry(gen_state, :diary_chain_verified, "system", payload)
    gen_state
  end

  defp run_matched_skills(gen_state) do
    loan_context = build_loan_context(gen_state.state, :heartbeat)
    {:ok, skills} = SkillLoader.load_all([])
    matched = SkillLoader.match(loan_context, skills)

    Enum.reduce(matched, gen_state, fn skill, acc ->
      acc = log_skill_activated(acc, skill)

      if Enum.any?(@periodic_skill_tools, &(&1 in skill.tools_required)) do
        run_skill_set_goal(acc, skill)
      else
        acc
      end
    end)
  end

  defp log_skill_activated(gen_state, skill) do
    payload = %{
      "skill_id" => skill.id,
      "version" => skill.version,
      "trigger_hash" => hash_term_json(skill.description)
    }

    {:ok, _seq} = append_entry(gen_state, :skill_activated, "system", payload)
    gen_state
  end

  defp run_skill_set_goal(gen_state, skill) do
    {gen_state, result} =
      invoke_tool(gen_state, "set_goal", %{"description" => skill.description}, :periodic)

    case result do
      {:ok, %{add_goal: goal}} -> apply_add_goal(gen_state, goal)
      _other -> gen_state
    end
  end

  defp apply_add_goal(gen_state, goal) do
    new_state = State.add_goal(gen_state.state, goal)

    payload = %{"goal_id" => goal.goal_id, "description" => goal.description}
    {:ok, _seq} = append_entry(gen_state, :goal_set, "system", payload)

    %{gen_state | state: new_state}
  end

  defp build_loan_context(state, event_type) do
    %{
      status: state.status,
      event_type: event_type,
      goal_descriptions: Enum.map(state.goals, & &1.description)
    }
  end

  # ---- planning loop (FT-019) ----

  @doc """
  Sends `:plan` to `self()` iff `event_type == :goal_set` — "when goals
  are set" per the task's literal wording, not "any state change
  re-plans". Exposed (not part of `contracts/loan-actor-api.md`'s public
  surface) so this decision is directly unit-testable: an
  integration-level diary-count assertion would be confounded by the
  periodic loop's own independent `verify_diary_chain` invocations
  (diary entries carry only a tool-args HASH, never the tool name in the
  clear, so "was this tool_invoked from planning or from the heartbeat"
  cannot be told apart by reading the diary from outside).
  """
  @spec maybe_trigger_planning(atom()) :: :ok
  def maybe_trigger_planning(:goal_set) do
    send(self(), :plan)
    :ok
  end

  def maybe_trigger_planning(_other_event_type), do: :ok

  @doc_type_keywords ~w(income identity appraisal)

  defp run_planning(gen_state) do
    loan_context = build_loan_context(gen_state.state, :plan)
    {:ok, skills} = SkillLoader.load_all([])
    matched = SkillLoader.match(loan_context, skills)

    Enum.reduce(matched, gen_state, fn skill, acc ->
      # Every match is diary-logged regardless of which tool it names —
      # mirrors run_matched_skills/1's (FT-018) established behavior.
      # request_document and request_operator_approval (FT-028) are the
      # only tools this loop acts on.
      acc = log_skill_activated(acc, skill)

      cond do
        "request_document" in skill.tools_required -> run_request_document(acc)
        "request_operator_approval" in skill.tools_required -> run_request_operator_approval(acc, skill)
        true -> acc
      end
    end)
  end

  defp run_request_document(gen_state) do
    doc_type = infer_doc_type(gen_state.state.goals)
    {gen_state, _result} = invoke_tool(gen_state, "request_document", %{"doc_type" => doc_type}, :planning)
    gen_state
  end

  # No document specifies a structured source for request_operator_approval's
  # "prompt"/"options" args (same gap infer_doc_type/1 already documents for
  # request_document's doc_type) — the skill's own trigger text becomes the
  # prompt, mirroring the periodic loop's set_goal invocation
  # (run_skill_set_goal/2); options default to data-model.md's own documented
  # example (`["approve", "reject"]`), the only options value any contract
  # names.
  defp run_request_operator_approval(gen_state, skill) do
    args = %{"prompt" => skill.description, "options" => ["approve", "reject"]}
    {gen_state, _result} = invoke_tool(gen_state, "request_operator_approval", args, :planning)
    gen_state
  end

  @doc """
  Keyword-match open goals' descriptions for one of the three
  `request_document` enum values; default `"income"` if none mention one
  (confirmed 2026-07-21 — neither the `Goal` struct nor the skill-format
  contract carries a structured `doc_type`, so this is the documented
  foundation placeholder, not a real business rule).

  Exposed (not part of `contracts/loan-actor-api.md`'s public surface) so
  it is directly unit-testable: diary entries only ever carry a *hash* of
  tool args (constitution Principle VIII), so which `doc_type` was chosen
  cannot be recovered by observing the diary from outside — pure logic
  like this needs a direct test, not an indirect one.
  """
  @spec infer_doc_type([LoanActor.Goal.t()]) :: String.t()
  def infer_doc_type(goals) do
    goals
    |> Enum.filter(&(&1.status == :open))
    |> Enum.map(&String.downcase(&1.description))
    |> Enum.find_value(fn description ->
      Enum.find(@doc_type_keywords, &String.contains?(description, &1))
    end)
    |> case do
      nil -> "income"
      doc_type -> doc_type
    end
  end

  # ---- generic tool invocation (constitution Principle VIII) ----

  defp invoke_tool(gen_state, tool_name, args, loop) do
    %{loan_id: loan_id, state: state} = gen_state
    invocation_id = "inv-#{System.unique_integer([:positive, :monotonic])}"

    ctx =
      Context.new(%{
        loan_id: loan_id,
        state: state,
        loop: loop,
        actor: "system",
        invocation_id: invocation_id
      })

    {redacted_args, args_hash} = redacted_args_and_hash(tool_name, args)

    invoked_payload = %{"tool" => tool_name, "invocation_id" => invocation_id, "args_hash" => args_hash}
    {:ok, _seq} = append_entry(gen_state, :tool_invoked, "system", invoked_payload)

    broadcast(gen_state, Encoder.tool_call_start(invocation_id, tool_name, loan_id))
    broadcast(gen_state, Encoder.tool_call_args(invocation_id, redacted_args))
    broadcast(gen_state, Encoder.tool_call_end(invocation_id))

    result = ToolRegistry.invoke(tool_name, args, ctx)
    gen_state = append_tool_result_entry(gen_state, tool_name, invocation_id, result)
    gen_state = maybe_stream_tool_result(gen_state, tool_name, invocation_id, redacted_args, result)
    {gen_state, result}
  end

  defp redacted_args_and_hash(tool_name, args) do
    case ToolRegistry.redacted_args(tool_name, args) do
      {:ok, redacted} -> {redacted, hash_term_json(redacted)}
      {:error, _reason} -> {%{"rejected" => true}, hash_term_json(%{"rejected" => true})}
    end
  end

  defp append_tool_result_entry(gen_state, tool_name, invocation_id, result) do
    {type, payload} =
      case result do
        {:ok, effects} ->
          {:tool_completed,
           %{"tool" => tool_name, "invocation_id" => invocation_id, "result_hash" => hash_term(effects)}}

        {:pending, id} ->
          {:tool_completed,
           %{
             "tool" => tool_name,
             "invocation_id" => invocation_id,
             "result_hash" => hash_term(id),
             "pending" => true
           }}

        {:error, reason} ->
          {:tool_failed, %{"tool" => tool_name, "invocation_id" => invocation_id, "reason" => inspect(reason)}}
      end

    {:ok, _seq} = append_entry(gen_state, type, "system", payload)
    gen_state
  end

  # `ToolCallResult` streams immediately for a synchronous result. The one
  # foundation exception is `request_operator_approval`'s `{:pending, id}` —
  # its Result is deferred until `respond_hitl/3` (FT-028).
  defp maybe_stream_tool_result(gen_state, "request_operator_approval", invocation_id, redacted_args, {:pending, request_id}) do
    request =
      HITLRequest.new(%{
        request_id: request_id,
        loan_id: gen_state.loan_id,
        prompt: Map.get(redacted_args, "prompt"),
        options: Map.get(redacted_args, "options"),
        created_at: DateTime.utc_now()
      })

    broadcast(gen_state, Encoder.hitl_request_event(gen_state.loan_id, Map.from_struct(request)))

    new_hitl_requests = Map.put(gen_state.hitl_requests, invocation_id, %{request: request, response: nil})
    %{gen_state | hitl_requests: new_hitl_requests}
  end

  defp maybe_stream_tool_result(gen_state, _tool_name, _invocation_id, _redacted_args, {:pending, _id}) do
    gen_state
  end

  defp maybe_stream_tool_result(gen_state, _tool_name, invocation_id, _redacted_args, {:ok, effects}) do
    stream_tool_call_result(gen_state, invocation_id, json_safe_effects(effects))
  end

  defp maybe_stream_tool_result(gen_state, _tool_name, invocation_id, _redacted_args, {:error, reason}) do
    stream_tool_call_result(gen_state, invocation_id, %{"error" => inspect(reason)})
  end

  defp stream_tool_call_result(gen_state, tool_call_id, content) do
    message_id = "msg-#{System.unique_integer([:positive, :monotonic])}"
    broadcast(gen_state, Encoder.tool_call_result(message_id, tool_call_id, content))
    gen_state
  end

  defp hash_term(term), do: term |> :erlang.term_to_binary() |> Chain.hash() |> Base.encode16()
  defp hash_term_json(term), do: term |> Jason.encode!() |> Chain.hash() |> Base.encode16()

  # A tool's `{:ok, effects}` map is defined by the contract as JSON-safe
  # (e.g. `%{transition: event_type}` — an atom value, which Jason already
  # encodes), with one existing exception: `set_goal`'s `%{add_goal: %Goal{}}`
  # (FT-043, pre-dating this task's streaming) carries a raw struct. Rather
  # than deriving Jason.Encoder on a domain struct (this codebase's
  # established pattern keeps JSON-shaping explicit — see
  # `AGUI.Encoder`'s own `_as_json` helpers), only the one shape that
  # actually appears in a foundation tool's effects is converted here.
  defp json_safe_effects(effects) when is_map(effects) do
    Map.new(effects, fn {k, v} -> {k, json_safe_value(v)} end)
  end

  defp json_safe_value(%LoanActor.Goal{} = goal) do
    %{
      "goal_id" => goal.goal_id,
      "description" => goal.description,
      "status" => Atom.to_string(goal.status),
      "due_at" => goal.due_at && DateTime.to_iso8601(goal.due_at)
    }
  end

  defp json_safe_value(other), do: other
end
