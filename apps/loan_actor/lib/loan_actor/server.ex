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
  """

  use GenServer

  alias LoanActor.Diary.Chain
  alias LoanActor.Diary.Entry
  alias LoanActor.Event
  alias LoanActor.Idempotency
  alias LoanActor.IllegalTransitionError
  alias LoanActor.PIIGuard
  alias LoanActor.Registry
  alias LoanActor.State
  alias LoanActor.State.Model

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
      {:ok, nil} -> {:ok, spawn_fresh(loan_id, store)}
      {:ok, _tail} -> {:ok, rehydrate(loan_id, store)}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl GenServer
  def handle_call({:send_event, %Event{} = event}, _from, gen_state) do
    case Event.validate(event) do
      {:error, :invalid_event} = error -> {:reply, error, gen_state}
      :ok -> handle_valid_event(event, gen_state)
    end
  end

  @impl GenServer
  def handle_call(:state, _from, gen_state), do: {:reply, gen_state.state, gen_state}

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
end
