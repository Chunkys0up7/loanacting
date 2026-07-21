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
  self-reschedule from each handler's OWN completion — keeps cadence
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
  invariant 4). No AG-UI streaming yet — the encoder (FT-023) hasn't landed.
  """

  use GenServer

  alias LoanActor.Diary.Chain
  alias LoanActor.Diary.Entry
  alias LoanActor.Event
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

  # loop: periodic
  @impl GenServer
  def handle_info(:heartbeat, gen_state) do
    {:noreply, run_heartbeat(gen_state)}
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
    %{loan_id: loan_id, state: state, store: store} = gen_state

    try do
      new_state = State.transition(state, event.type)
      {:ok, sequence} = append_entry(store, loan_id, event.type, Atom.to_string(event.source), clean_payload)
      :ok = Idempotency.record_sequence(loan_id, event.event_id, event.source, sequence)
      {:reply, {:ok, sequence}, %{gen_state | state: new_state}}
    rescue
      e in IllegalTransitionError ->
        payload = %{
          "attempted_event_type" => Atom.to_string(e.event_type),
          "from_status" => Atom.to_string(e.from)
        }

        {:ok, sequence} = append_entry(store, loan_id, :illegal_transition_attempted, "system", payload)
        :ok = Idempotency.record_sequence(loan_id, event.event_id, event.source, sequence)
        {:reply, {:error, {:illegal_transition, e.from, e.event_type}}, gen_state}
    end
  end

  defp append_entry(store, loan_id, type, actor, payload) do
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

    store.append(loan_id, entry)
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
    %{loan_id: loan_id, state: State.new(%{loan_id: loan_id}), store: store}
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

    %{loan_id: loan_id, state: state, store: store}
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
    %{loan_id: loan_id, state: state, store: store} = gen_state
    payload = %{"state_hash" => hash_term(state)}
    {:ok, _seq} = append_entry(store, loan_id, :heartbeat, "system", payload)
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

    {:ok, _seq} = append_entry(store, loan_id, :diary_chain_verified, "system", payload)
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
    %{loan_id: loan_id, store: store} = gen_state

    payload = %{
      "skill_id" => skill.id,
      "version" => skill.version,
      "trigger_hash" => hash_term_json(skill.description)
    }

    {:ok, _seq} = append_entry(store, loan_id, :skill_activated, "system", payload)
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
    %{loan_id: loan_id, store: store} = gen_state
    new_state = State.add_goal(gen_state.state, goal)

    payload = %{"goal_id" => goal.goal_id, "description" => goal.description}
    {:ok, _seq} = append_entry(store, loan_id, :goal_set, "system", payload)

    %{gen_state | state: new_state}
  end

  defp build_loan_context(state, event_type) do
    %{
      status: state.status,
      event_type: event_type,
      goal_descriptions: Enum.map(state.goals, & &1.description)
    }
  end

  # ---- generic tool invocation (constitution Principle VIII) ----

  defp invoke_tool(gen_state, tool_name, args, loop) do
    %{loan_id: loan_id, state: state, store: store} = gen_state
    invocation_id = "inv-#{System.unique_integer([:positive, :monotonic])}"

    ctx =
      Context.new(%{
        loan_id: loan_id,
        state: state,
        loop: loop,
        actor: "system",
        invocation_id: invocation_id
      })

    args_hash =
      case ToolRegistry.redacted_args(tool_name, args) do
        {:ok, redacted} -> hash_term_json(redacted)
        {:error, _reason} -> hash_term_json(%{"rejected" => true})
      end

    invoked_payload = %{"tool" => tool_name, "invocation_id" => invocation_id, "args_hash" => args_hash}
    {:ok, _seq} = append_entry(store, loan_id, :tool_invoked, "system", invoked_payload)

    result = ToolRegistry.invoke(tool_name, args, ctx)
    gen_state = append_tool_result_entry(gen_state, tool_name, invocation_id, result)
    {gen_state, result}
  end

  defp append_tool_result_entry(gen_state, tool_name, invocation_id, result) do
    %{loan_id: loan_id, store: store} = gen_state

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

    {:ok, _seq} = append_entry(store, loan_id, type, "system", payload)
    gen_state
  end

  defp hash_term(term), do: term |> :erlang.term_to_binary() |> Chain.hash() |> Base.encode16()
  defp hash_term_json(term), do: term |> Jason.encode!() |> Chain.hash() |> Base.encode16()
end
