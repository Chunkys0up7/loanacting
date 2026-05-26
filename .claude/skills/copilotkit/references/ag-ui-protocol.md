# AG-UI Protocol Reference

AG-UI is an open, event-based protocol that streams JSON events between an agent backend and a user-facing app. CopilotKit is the reference 1st-party client; community SDKs exist for Kotlin, Go, Dart, Java, Rust.

## Transport

- **Default**: HTTP POST with `Accept: text/event-stream` → server streams SSE-formatted events.
- **Also valid**: WebSocket (bidirectional, lower overhead for long sessions), plain chunked HTTP.
- Each SSE message body is a JSON object with at minimum a `type` field; payload depends on type.

## The 17 event types

### Lifecycle (5)

| Event | Purpose |
|---|---|
| `RunStarted` | Begin of an agent execution. Carries `thread_id`, `run_id`. |
| `RunFinished` | Successful completion. Final state / message. |
| `RunError` | Failure. Carries error message and code. |
| `StepStarted` | Sub-task begin (multi-step graph node entry). |
| `StepFinished` | Sub-task end. |

### Text messages (3)

| Event | Purpose |
|---|---|
| `TextMessageStart` | New assistant message stream begins. `message_id`, `role`. |
| `TextMessageContent` | A delta chunk. `message_id`, `delta`. |
| `TextMessageEnd` | Message complete. |

### Tool calls (4)

| Event | Purpose |
|---|---|
| `ToolCallStart` | Agent is about to call a tool. `tool_call_id`, `tool_name`. |
| `ToolCallArgs` | Streaming arguments (delta chunks of the JSON args). |
| `ToolCallEnd` | Args complete; ready to execute. |
| `ToolCallResult` | Result of tool execution (when run server-side) or echo of client-returned result. |

### State management (3)

| Event | Purpose |
|---|---|
| `StateSnapshot` | Full state JSON. Send at run start or on reconnect. |
| `StateDelta` | Incremental change as RFC 6902 JSON Patch. |
| `MessagesSnapshot` | Full conversation history (for sync, thread restore). |

### Special (2)

| Event | Purpose |
|---|---|
| `RawEvent` | Pass-through of an underlying framework event (LangGraph node update, etc.) untouched. |
| `CustomEvent` | Application-defined extension. Used for HITL interrupts and A2UI surfaces. |

## Canonical event sequence

```
RunStarted
  StateSnapshot                    (optional, recommended)
  [ StepStarted
      TextMessageStart
      TextMessageContent ×N
      TextMessageEnd
      ToolCallStart
      ToolCallArgs ×N
      ToolCallEnd
      ToolCallResult              (server-executed tools)
      StateDelta ×N
    StepFinished
  ] ×N
RunFinished
```

`RunError` may replace `RunFinished` at any point. `CustomEvent` may appear anywhere.

## Minimal SSE producer (Python, FastAPI)

```python
from fastapi import FastAPI
from fastapi.responses import StreamingResponse
import json, uuid, asyncio

app = FastAPI()

async def ag_ui_stream(prompt: str):
    run_id = str(uuid.uuid4())
    thread_id = "t1"
    def evt(t, **kw): return f"data: {json.dumps({'type': t, **kw})}\n\n"

    yield evt("RunStarted", run_id=run_id, thread_id=thread_id)
    msg_id = str(uuid.uuid4())
    yield evt("TextMessageStart", message_id=msg_id, role="assistant")
    for token in ("Hello", ", ", "world", "!"):
        yield evt("TextMessageContent", message_id=msg_id, delta=token)
        await asyncio.sleep(0.05)
    yield evt("TextMessageEnd", message_id=msg_id)
    yield evt("RunFinished", run_id=run_id)

@app.post("/agent")
async def agent(body: dict):
    return StreamingResponse(ag_ui_stream(body["prompt"]),
                             media_type="text/event-stream")
```

## Minimal consumer (TypeScript)

```ts
const res = await fetch("/agent", {
  method: "POST",
  headers: { "Accept": "text/event-stream", "Content-Type": "application/json" },
  body: JSON.stringify({ prompt }),
});
const reader = res.body!.getReader();
const decoder = new TextDecoder();
let buf = "";
while (true) {
  const { value, done } = await reader.read();
  if (done) break;
  buf += decoder.decode(value, { stream: true });
  const lines = buf.split("\n\n");
  buf = lines.pop()!;
  for (const block of lines) {
    const data = block.replace(/^data: /, "");
    const event = JSON.parse(data);
    switch (event.type) {
      case "TextMessageContent": appendToken(event.message_id, event.delta); break;
      case "ToolCallResult":     displayToolResult(event); break;
      case "StateDelta":         applyJsonPatch(event.patch); break;
      case "RunFinished":        markDone(); break;
    }
  }
}
```

## Implementing a custom agent that CopilotKit can drive

1. Expose a single `POST` endpoint that accepts `{ thread_id, messages, state?, tools? }`.
2. Return `text/event-stream` of the events above.
3. Honor `thread_id` for multi-turn continuity; persist `messages` and `state` per thread.
4. For tools the *frontend* should run, emit `ToolCallStart`/`ToolCallArgs`/`ToolCallEnd` and stop — the client will execute and POST the result back as a tool message on the next request.
5. Point `<CopilotKit runtimeUrl="/your-endpoint" />` (or wire through `CopilotRuntime` adapter) at the URL.

## Spec & community

- Spec: <https://docs.ag-ui.com/>
- GitHub: <https://github.com/ag-ui-protocol/ag-ui>
- Discord: <https://discord.gg/Jd3FzfdJa8>
