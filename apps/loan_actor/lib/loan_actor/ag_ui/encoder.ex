defmodule LoanActor.AGUI.Encoder do
  @moduledoc """
  Elixir → AG-UI canonical JSON (FT-023). One function per event row in
  `contracts/ag-ui-events.md` (15 rows; `CustomEvent` has three named
  variants, so 13 distinct AG-UI `type` values in total).

  Every function returns a **JSON-safe map** (string keys, only
  string/number/boolean/list/map/nil values) — never a raw JSON string
  and never a struct. Turning that map into the actual `data: ...\\n\\n`
  SSE wire line is `LoanActor.AGUI.Stream`'s job (FT-024), not this
  module's; keeping the two separate means this module is pure and
  trivially snapshot-testable.

  Two fields are the explicit exception, per the contract's own wording —
  `ToolCallArgs.delta` and `ToolCallResult.content` are themselves
  "`<... as JSON string>`", i.e. pre-encoded with `Jason.encode!/1` inside
  this module, not left as nested maps. Callers must pass JSON-safe
  content for both (a `Tool.Spec`-schema-shaped args map, and a JSON-safe
  result/error map respectively) — this module does not sanitize its
  inputs, only shapes them.

  Depends only on `LoanActor.State` (+ `Goal`) and `LoanActor.Diary.Entry`
  (FT-010/FT-005/FT-041) — deliberately NOT on `LoanActor.Server`,
  `HITLRequest`, or the Registry, none of which this task depends on.
  `hitl_request_event/2` and `tool_call_result/3` therefore accept plain
  maps rather than not-yet-existing structs; FT-028/FT-017 build those
  shapes when they land.

  Binary hash fields (`payload_hash`, `prev_hash`) are lower-case hex —
  raw bytes are not valid JSON string content. `payload_ref`, when
  non-nil, is already a printable URI string per `data-model.md` and
  passes through unchanged.
  """

  alias LoanActor.Diary.Entry
  alias LoanActor.Goal
  alias LoanActor.State

  # ---- Lifecycle ----

  @spec run_started(String.t(), String.t() | nil, String.t()) :: map()
  def run_started(run_id, thread_id, loan_id) do
    %{"type" => "RunStarted", "run_id" => run_id, "thread_id" => thread_id, "loan_id" => loan_id}
  end

  @spec run_finished(String.t()) :: map()
  def run_finished(run_id) do
    %{"type" => "RunFinished", "run_id" => run_id}
  end

  @spec run_error(String.t(), String.t(), term()) :: map()
  def run_error(run_id, message, code) do
    %{"type" => "RunError", "run_id" => run_id, "message" => message, "code" => code}
  end

  # ---- State ----

  @spec state_snapshot(String.t(), State.t()) :: map()
  def state_snapshot(loan_id, %State{} = state) do
    %{"type" => "StateSnapshot", "loan_id" => loan_id, "state" => state_as_json(state)}
  end

  @spec state_delta(String.t(), [map()]) :: map()
  def state_delta(loan_id, patch) when is_list(patch) do
    %{"type" => "StateDelta", "loan_id" => loan_id, "patch" => patch}
  end

  # ---- Text messages ----

  @spec text_message_start(String.t()) :: map()
  def text_message_start(message_id) do
    %{"type" => "TextMessageStart", "message_id" => message_id, "role" => "assistant"}
  end

  @spec text_message_content(String.t(), String.t()) :: map()
  def text_message_content(message_id, delta) do
    %{"type" => "TextMessageContent", "message_id" => message_id, "delta" => delta}
  end

  @spec text_message_end(String.t()) :: map()
  def text_message_end(message_id) do
    %{"type" => "TextMessageEnd", "message_id" => message_id}
  end

  # ---- Custom events ----

  @spec diary_entry_event(String.t(), Entry.t()) :: map()
  def diary_entry_event(loan_id, %Entry{} = entry) do
    %{
      "type" => "CustomEvent",
      "name" => "diary_entry",
      "loan_id" => loan_id,
      "entry" => entry_as_json(entry)
    }
  end

  @spec hitl_request_event(String.t(), map()) :: map()
  def hitl_request_event(loan_id, request) when is_map(request) do
    %{
      "type" => "CustomEvent",
      "name" => "hitl_request",
      "loan_id" => loan_id,
      "request" => hitl_request_as_json(request)
    }
  end

  @spec hitl_conflict_event(String.t(), String.t()) :: map()
  def hitl_conflict_event(loan_id, request_id) do
    %{
      "type" => "CustomEvent",
      "name" => "hitl_conflict",
      "loan_id" => loan_id,
      "request_id" => request_id
    }
  end

  # ---- Tool calls (0004) ----

  @spec tool_call_start(String.t(), String.t(), String.t()) :: map()
  def tool_call_start(tool_call_id, tool_call_name, loan_id) do
    %{
      "type" => "ToolCallStart",
      "tool_call_id" => tool_call_id,
      "tool_call_name" => tool_call_name,
      "loan_id" => loan_id
    }
  end

  @spec tool_call_args(String.t(), map()) :: map()
  def tool_call_args(tool_call_id, redacted_args) when is_map(redacted_args) do
    %{"type" => "ToolCallArgs", "tool_call_id" => tool_call_id, "delta" => Jason.encode!(redacted_args)}
  end

  @spec tool_call_end(String.t()) :: map()
  def tool_call_end(tool_call_id) do
    %{"type" => "ToolCallEnd", "tool_call_id" => tool_call_id}
  end

  @spec tool_call_result(String.t(), String.t(), term()) :: map()
  def tool_call_result(message_id, tool_call_id, content) do
    %{
      "type" => "ToolCallResult",
      "message_id" => message_id,
      "tool_call_id" => tool_call_id,
      "content" => Jason.encode!(content)
    }
  end

  # ---- struct -> JSON-safe map helpers ----

  defp state_as_json(%State{} = state) do
    %{
      "loan_id" => state.loan_id,
      "status" => Atom.to_string(state.status),
      "goals" => Enum.map(state.goals, &goal_as_json/1),
      "context" => state.context,
      "version" => state.version,
      "last_heartbeat_at" => datetime_or_nil(state.last_heartbeat_at)
    }
  end

  defp goal_as_json(%Goal{} = goal) do
    %{
      "goal_id" => goal.goal_id,
      "description" => goal.description,
      "status" => Atom.to_string(goal.status),
      "due_at" => datetime_or_nil(goal.due_at)
    }
  end

  defp entry_as_json(%Entry{} = entry) do
    %{
      "loan_id" => entry.loan_id,
      "sequence" => entry.sequence,
      "timestamp" => DateTime.to_iso8601(entry.timestamp),
      "type" => Atom.to_string(entry.type),
      "actor" => entry.actor,
      "payload_hash" => hex(entry.payload_hash),
      "payload_ref" => entry.payload_ref,
      "prev_hash" => hex(entry.prev_hash)
    }
  end

  defp hitl_request_as_json(request) do
    %{
      "request_id" => Map.fetch!(request, :request_id),
      "loan_id" => Map.fetch!(request, :loan_id),
      "prompt" => Map.fetch!(request, :prompt),
      "options" => Map.fetch!(request, :options),
      "created_at" => datetime_or_nil(Map.get(request, :created_at))
    }
  end

  defp datetime_or_nil(nil), do: nil
  defp datetime_or_nil(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp hex(binary) when is_binary(binary), do: Base.encode16(binary, case: :lower)
end
