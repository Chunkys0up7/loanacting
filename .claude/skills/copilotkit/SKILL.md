---
name: copilotkit
description: Build agent-powered React UIs with CopilotKit and the AG-UI protocol. Use when the user is integrating an agent (LangGraph, CrewAI, PydanticAI, custom) with a React/Next.js frontend; adding chat, sidebar, popup, or generative-UI surfaces; wiring human-in-the-loop approvals; sharing state between agent and UI; or implementing/consuming the AG-UI event stream (SSE/WebSocket). Trigger on mentions of CopilotKit, AG-UI, useCopilotAction, useCoAgent, CopilotChat/Sidebar/Popup, or "agent frontend".
---

# CopilotKit + AG-UI

CopilotKit is the **frontend stack for agents and generative UI** (React + Angular). AG-UI is the open, event-based protocol it speaks to any agent backend. Use this skill to design and wire both ends.

## When to reach for what

| User goal | Reach for |
|---|---|
| Chat box / sidebar / popup over an existing agent | `CopilotChat` / `CopilotSidebar` / `CopilotPopup` + `<CopilotKit>` provider |
| Let the agent call a frontend function (open modal, navigate, mutate state) | `useCopilotAction` / `useFrontendTool` |
| Let the agent read app state (selected row, current user, filters) | `useCopilotReadable` / `useAgentContext` |
| Share live, bidirectional state with a LangGraph/CrewAI agent | `useCoAgent` + `useCoAgentStateRender` |
| Pause for human approval mid-run | `useHumanInTheLoop` / `useLangGraphInterrupt` |
| Render custom UI from agent output (generative UI) | Render prop on `useCopilotAction` / A2UI tool renderer |
| Connect a non-CopilotKit agent (Go/Rust/custom) | Implement AG-UI SSE endpoint — see [references/ag-ui-protocol.md](references/ag-ui-protocol.md) |
| Bootstrap a new app | `npx copilotkit@latest create` |

## Architecture in one diagram

```
React app                 Copilot Runtime              Agent backend
┌──────────────────┐      ┌──────────────────┐         ┌──────────────────┐
│ <CopilotKit>     │      │ /api/copilotkit  │         │ LangGraph        │
│   <CopilotChat/> │◄────►│ (Next.js route   │◄───────►│ CrewAI           │
│   useCoAgent()   │ SSE  │  or standalone)  │  AG-UI  │ PydanticAI       │
│   useCopilot     │      │                  │  SSE/WS │ Custom (any lang)│
│     Action()     │      └──────────────────┘         └──────────────────┘
└──────────────────┘
```

The runtime is the broker. AG-UI events flow agent→UI; tool results and human input flow UI→agent. Both directions over the same stream.

## Workflow — adding CopilotKit to an existing app

1. **Install** — `npm i @copilotkit/react-core @copilotkit/react-ui @copilotkit/runtime`
2. **Mount the runtime endpoint** (Next.js App Router): create `app/api/copilotkit/route.ts` that returns a `CopilotRuntime` handler pointed at your agent (or LLM directly).
3. **Wrap the app** in `<CopilotKit runtimeUrl="/api/copilotkit" agent="my-agent">`.
4. **Drop in a UI surface** — `<CopilotSidebar />` is the fastest win.
5. **Teach the copilot about your app** — call `useCopilotReadable({ description, value })` from components that hold relevant state.
6. **Let it act** — register `useCopilotAction({ name, parameters, handler, render })` for each thing the agent should be able to do.
7. **For stateful agents** — swap to `useCoAgent({ name, initialState })` to get bidirectional shared state.

Always cite [references/react-api.md](references/react-api.md) for exact prop and parameter shapes before writing code.

## Workflow — implementing an AG-UI agent from scratch

1. Choose transport: **SSE** is the default (HTTP POST returns `text/event-stream`). WebSocket and plain HTTP also valid.
2. Emit events in the canonical order: `RunStarted` → (optional `StepStarted`/`StepFinished`) → text/tool/state events interleaved → `RunFinished` (or `RunError`).
3. Use **JSON Patch deltas** (`StateDelta`) for incremental state updates; send a full `StateSnapshot` at run start.
4. For tools: `ToolCallStart` → streaming `ToolCallArgs` → `ToolCallEnd` → `ToolCallResult` once executed.
5. For HITL: emit a `CustomEvent` (or framework-specific interrupt) and wait for the UI's response message on the same thread.

See [references/ag-ui-protocol.md](references/ag-ui-protocol.md) for the full 17-event taxonomy and a minimal SSE producer in Python and TypeScript.

## Common patterns

- **Generative UI** — `useCopilotAction({ name, parameters, render: ({status, args}) => <Card .../> })`. The `render` prop turns a tool call into a React component; CopilotKit handles streaming/partial args.
- **Frontend-only actions** (no backend tool needed) — same hook, just provide `handler` that runs in the browser.
- **Shared agent state** — `const { state, setState } = useCoAgent({ name, initialState })`. Mutating `setState` syncs to the agent; the agent's `StateDelta` events update `state`.
- **Mid-run rendering of agent thoughts** — `useCoAgentStateRender({ name, render: (state) => <ProgressView .../> })`.
- **Approval gate** — `useHumanInTheLoop` or LangGraph's `useLangGraphInterrupt` pauses execution; resolve with `respond({...})`.

## Things to verify before writing code

- **CopilotKit version** — API names shifted around v1.x (e.g., `useFrontendTool` ↔ `useCopilotAction`, `useAgent` ↔ `useCoAgent`). Check `package.json` and the docs at <https://docs.copilotkit.ai/reference>.
- **Agent framework binding** — LangGraph uses `@copilotkit/runtime-client-gql` + LangGraph platform; CrewAI uses `CopilotKitState`. Pick the right adapter.
- **AG-UI version** — protocol is event-stable but new event types appear (A2UI surface events landed via the Oracle/Google partnership in 2026). Don't assume `RawEvent`/`CustomEvent` payloads.

## Reference files in this skill

- [references/ag-ui-protocol.md](references/ag-ui-protocol.md) — 17 event types, sequence rules, SSE wire format, minimal producer/consumer
- [references/react-api.md](references/react-api.md) — Provider, components, hooks with signatures and minimal examples
- [references/backend-integration.md](references/backend-integration.md) — Wiring CopilotRuntime to LangGraph / CrewAI / PydanticAI / custom AG-UI agents
- [references/genui-and-hitl.md](references/genui-and-hitl.md) — Generative UI render props, human-in-the-loop, interrupts, A2UI

## Authoritative URLs

- CopilotKit docs: <https://docs.copilotkit.ai/>
- API reference: <https://docs.copilotkit.ai/reference>
- AG-UI spec: <https://docs.ag-ui.com/>
- AG-UI GitHub: <https://github.com/ag-ui-protocol/ag-ui>
- CopilotKit GitHub: <https://github.com/CopilotKit/CopilotKit>
- Demo apps: <https://dojo.ag-ui.com/>
