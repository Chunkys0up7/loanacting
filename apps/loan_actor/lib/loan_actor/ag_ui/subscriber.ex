defmodule LoanActor.AGUI.Subscriber do
  @moduledoc """
  Per-client AG-UI event delivery process (FT-024; `research.md` R-2).

  Sits between a loan actor (which `cast`s events, fire-and-forget, never
  back-pressured) and the process that ultimately wants them — per
  `contracts/loan-actor-api.md`'s `subscribe/2`, "the caller receives
  `{:ag_ui_event, ref, event}` messages". This module is that delivery
  path's own process, so one slow/misbehaving subscriber can never affect
  the loan actor or any other subscriber.

  **Backpressure signal (confirmed 2026-07-21 — no answer came back on the
  clarifying question raised; proceeding with the flagged recommendation,
  documented here for easy revisit):** research.md R-2 says resync mode
  triggers when "the subscriber's mailbox exceeds the bound", but `send/2`
  never blocks or reveals whether ANY receiver is keeping up — some
  concrete signal has to stand in for "mailbox". This implementation reads
  it literally: `Process.info(self(), :message_queue_len)`, checked at the
  start of each `:deliver` cast, is the subscriber GenServer's OWN Erlang
  mailbox depth — if the loan actor is casting events faster than this
  process can drain them, THAT count grows. This is simple and dependency-free,
  but weaker than a real ack protocol: a slow HTTP/SSE *owner* process
  holding its own separate mailbox full of undelivered `:ag_ui_event`
  messages does not show up here unless the loan actor is also casting in
  a tight burst. An explicit ack protocol (subscriber holds a real pending
  queue, owner acks each delivery, drop-to-resync on unacked backlog) would
  detect that case for real, but invents a new protocol with no owner-side
  implementation yet (FT-027, the HTTP layer, doesn't exist). Revisit if
  this proves insufficient once FT-027 lands.

  Once in resync mode, `:deliver` casts are silently dropped — this
  process does NOT try to recover on its own. The caller (FT-025's
  `Server.subscribe/2` integration, or a test) is expected to notice via
  `resyncing?/1` and call `resync/2` with a freshly built `StateSnapshot`
  when it is ready; that single call both delivers the snapshot and clears
  resync mode.
  """

  use GenServer

  @default_max_queue 128

  @enforce_keys [:owner, :ref, :max_queue]
  defstruct [:owner, :ref, :max_queue, resync?: false]

  @type t :: %__MODULE__{
          owner: pid(),
          ref: reference(),
          max_queue: pos_integer(),
          resync?: boolean()
        }

  @doc """
  Start a subscriber delivering to `owner` (monitored — the subscriber
  stops itself if `owner` dies), correlated by `ref`. `opts`:
  `:max_queue` (default #{@default_max_queue}).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Deliver `event` (a JSON-safe map from `LoanActor.AGUI.Encoder`) fire-and-forget."
  @spec deliver(pid(), map()) :: :ok
  def deliver(subscriber, event) when is_map(event) do
    GenServer.cast(subscriber, {:deliver, event})
  end

  @doc """
  Deliver `snapshot` immediately and clear resync mode — the caller's
  answer to `resyncing?/1` being `true`.
  """
  @spec resync(pid(), map()) :: :ok
  def resync(subscriber, snapshot) when is_map(snapshot) do
    GenServer.cast(subscriber, {:resync, snapshot})
  end

  @doc "Whether this subscriber is currently in resync mode (dropping `:deliver` events)."
  @spec resyncing?(pid()) :: boolean()
  def resyncing?(subscriber), do: GenServer.call(subscriber, :resyncing?)

  # ---- GenServer callbacks ----

  @impl GenServer
  def init(opts) do
    owner = Keyword.fetch!(opts, :owner)
    ref = Keyword.fetch!(opts, :ref)
    max_queue = Keyword.get(opts, :max_queue, @default_max_queue)

    Process.monitor(owner)

    {:ok, %__MODULE__{owner: owner, ref: ref, max_queue: max_queue}}
  end

  @impl GenServer
  def handle_cast({:deliver, _event}, %__MODULE__{resync?: true} = state) do
    {:noreply, state}
  end

  def handle_cast({:deliver, event}, state) do
    {:noreply, maybe_deliver(state, event)}
  end

  def handle_cast({:resync, snapshot}, state) do
    send(state.owner, {:ag_ui_event, state.ref, snapshot})
    {:noreply, %{state | resync?: false}}
  end

  @impl GenServer
  def handle_call(:resyncing?, _from, state) do
    {:reply, state.resync?, state}
  end

  @impl GenServer
  def handle_info({:DOWN, _mon_ref, :process, owner, _reason}, %{owner: owner} = state) do
    {:stop, :normal, state}
  end

  defp maybe_deliver(state, event) do
    case Process.info(self(), :message_queue_len) do
      {:message_queue_len, len} when len > state.max_queue ->
        %{state | resync?: true}

      _ ->
        send(state.owner, {:ag_ui_event, state.ref, event})
        state
    end
  end
end
