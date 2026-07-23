defmodule LoanActor.Web.Router do
  @moduledoc """
  HTTP surface per `contracts/http-endpoints.md` (FT-027, HITL route added
  by FT-028 once `LoanActor.respond_hitl/3` existed): `POST /loans`,
  `POST /loans/:loan_id/events`, `POST /loans/:loan_id/hitl/:request_id`,
  `GET|POST /loans/:loan_id/ag-ui`.

  ## HITL response (`POST /loans/:loan_id/hitl/:request_id`)

  Body `{"decision": ..., "comment": ...}` (comment optional); the
  operator id comes from `conn.assigns.operator_id` (`OperatorPlug`, which
  already ran ahead of this route in the pipeline — no separate lookup).
  `{:error, :not_found}` (a `request_id` the loan never parked) maps to
  404 same as `:not_running`, distinguished by `error` value, since the
  contract's general error table lists 404 for `/hitl` without splitting
  out the two cases. A malformed body (e.g. missing `decision`) raises via
  `HITLResponse.new/1` — uncaught, per the contract's own documented
  "500 — unhandled" fallback; no 400 is listed for this route.

  ## AG-UI streaming (`GET|POST /loans/:loan_id/ag-ui`)

  Subscribes (`LoanActor.subscribe/2`), emits `RunStarted` then
  `StateSnapshot`, then blocks on `receive` forwarding each
  `{:ag_ui_event, ref, event}` as an SSE `data: ...\\n\\n` chunk — genuinely
  unbounded in production (a quiet-but-still-subscribed client must stay
  connected; there is no idle-timeout disconnect, which would incorrectly
  drop a legitimate long-lived connection during a quiet period).

  Tests need the handler to actually RETURN, and there is no way to reach
  a per-call parameter through a real HTTP route — so the loop's bound is
  `config :loan_actor, :ag_ui_stream_max_events` (default `:infinity`),
  the same pattern as `:heartbeat_ms`/`:ag_ui_subscriber_buffer`: tests set
  it low via `Application.put_env/3` before calling the route. `since_sequence`
  replay-before-live is deferred: FT-027's own deliverable text doesn't ask
  for it and no replay mechanism exists yet independent of this task.
  """

  use Plug.Router

  alias LoanActor.AGUI.Encoder
  alias LoanActor.Event
  alias LoanActor.HITLResponse
  alias Uniq.UUID

  plug LoanActor.Web.OperatorPlug
  plug :match
  plug :fetch_query_params

  plug Plug.Parsers,
    parsers: [:json],
    json_decoder: Jason,
    pass: ["application/json"]

  plug :dispatch

  post "/loans" do
    handle_create_loan(conn)
  end

  post "/loans/:loan_id/events" do
    handle_send_event(conn, loan_id)
  end

  post "/loans/:loan_id/hitl/:request_id" do
    handle_respond_hitl(conn, loan_id, request_id)
  end

  get "/loans/:loan_id/ag-ui" do
    handle_ag_ui(conn, loan_id, conn.query_params)
  end

  post "/loans/:loan_id/ag-ui" do
    handle_ag_ui(conn, loan_id, conn.body_params)
  end

  match _ do
    send_json(conn, 404, %{"error" => "not_found"})
  end

  # ---- POST /loans ----

  defp handle_create_loan(conn) do
    loan_id = Map.get(conn.body_params, "loan_id") || UUID.uuid7()
    already_existed? = LoanActor.whereis(loan_id) != nil

    case LoanActor.spawn(loan_id) do
      {:ok, _pid} ->
        {:ok, state} = LoanActor.state(loan_id)
        status_code = if already_existed?, do: 200, else: 201

        send_json(conn, status_code, %{
          "loan_id" => loan_id,
          "status" => Atom.to_string(state.status),
          "version" => state.version
        })

      {:error, reason} ->
        send_json(conn, 500, %{"request_id" => request_id(), "error" => inspect(reason)})
    end
  end

  # ---- POST /loans/:loan_id/events ----

  defp handle_send_event(conn, loan_id) do
    event = build_event(conn.body_params)

    case LoanActor.send_event(loan_id, event) do
      {:ok, sequence} ->
        send_json(conn, 202, %{"result" => "ok", "sequence" => sequence})

      {:duplicate, sequence} ->
        send_json(conn, 202, %{"result" => "duplicate", "sequence" => sequence})

      {:error, :not_running} ->
        send_json(conn, 404, %{"error" => "not_running"})

      {:error, :invalid_event} ->
        send_json(conn, 400, %{"error" => "invalid_event"})

      {:error, {:pii_violation, paths}} ->
        send_json(conn, 422, %{"error" => "pii_violation", "paths" => paths})

      {:error, {:illegal_transition, from, event_type}} ->
        send_json(conn, 409, %{
          "error" => "illegal_transition",
          "from" => Atom.to_string(from),
          "event_type" => Atom.to_string(event_type)
        })
    end
  end

  defp build_event(body) do
    %Event{
      event_id: body["event_id"],
      source: to_existing_atom_or_nil(body["source"]),
      type: to_existing_atom_or_nil(body["type"]),
      payload: body["payload"] || %{},
      created_at: parse_datetime(body["created_at"]),
      received_at: DateTime.utc_now()
    }
  end

  defp to_existing_atom_or_nil(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> nil
  end

  defp to_existing_atom_or_nil(_other), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> dt
      _error -> nil
    end
  end

  defp parse_datetime(_other), do: nil

  # ---- POST /loans/:loan_id/hitl/:request_id ----

  defp handle_respond_hitl(conn, loan_id, request_id) do
    response =
      HITLResponse.new(%{
        request_id: request_id,
        decision: conn.body_params["decision"],
        comment: conn.body_params["comment"],
        operator_id: conn.assigns.operator_id,
        responded_at: DateTime.utc_now()
      })

    case LoanActor.respond_hitl(loan_id, request_id, response) do
      :ok ->
        send_json(conn, 200, %{"result" => "accepted"})

      {:conflict, existing} ->
        send_json(conn, 409, %{"result" => "conflict", "existing_response" => hitl_response_as_json(existing)})

      {:error, :not_found} ->
        send_json(conn, 404, %{"error" => "request_not_found"})

      {:error, :not_running} ->
        send_json(conn, 404, %{"error" => "not_running"})
    end
  end

  defp hitl_response_as_json(%HITLResponse{} = response) do
    %{
      "request_id" => response.request_id,
      "decision" => response.decision,
      "comment" => response.comment,
      "operator_id" => response.operator_id,
      "responded_at" => DateTime.to_iso8601(response.responded_at)
    }
  end

  # ---- GET|POST /loans/:loan_id/ag-ui ----

  defp handle_ag_ui(conn, loan_id, params) do
    case LoanActor.whereis(loan_id) do
      nil ->
        send_json(conn, 404, %{"error" => "not_running"})

      _pid ->
        {:ok, ref} = LoanActor.subscribe(loan_id)
        {:ok, state} = LoanActor.state(loan_id)
        run_id = "run-#{System.unique_integer([:positive, :monotonic])}"

        conn
        |> put_resp_content_type("text/event-stream")
        |> send_chunked(200)
        |> write_sse!(Encoder.run_started(run_id, params["thread_id"], loan_id))
        |> write_sse!(Encoder.state_snapshot(loan_id, state))
        |> stream_loop(ref, 0, max_events_config())
    end
  end

  defp max_events_config, do: Application.get_env(:loan_actor, :ag_ui_stream_max_events, :infinity)

  defp stream_loop(conn, _ref, count, max_events)
       when is_integer(max_events) and count >= max_events do
    conn
  end

  defp stream_loop(conn, ref, count, max_events) do
    receive do
      {:ag_ui_event, ^ref, event} ->
        case chunk(conn, sse_line(event)) do
          {:ok, new_conn} -> stream_loop(new_conn, ref, count + 1, max_events)
          {:error, _reason} -> conn
        end
    after
      stream_after_timeout(max_events) ->
        conn
    end
  end

  # Production (max_events: :infinity) blocks forever — correct for a
  # quiet-but-still-subscribed client. A finite max_events (tests only)
  # needs a bounded wait so a run that legitimately produces fewer than
  # max_events doesn't hang.
  defp stream_after_timeout(:infinity), do: :infinity
  defp stream_after_timeout(_finite), do: 1_000

  defp write_sse!(conn, event) do
    {:ok, new_conn} = chunk(conn, sse_line(event))
    new_conn
  end

  defp sse_line(event), do: "data: #{Jason.encode!(event)}\n\n"

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end

  defp request_id, do: "req-#{System.unique_integer([:positive, :monotonic])}"
end
