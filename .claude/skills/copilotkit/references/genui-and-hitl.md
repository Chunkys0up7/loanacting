# Generative UI & Human-in-the-Loop

## Generative UI

"Generative UI" = the agent emits a tool/action call, and the *call itself* renders as a React component in the chat transcript (or wherever you mount it). Three flavors:

### 1. Action with `render` (most common)

```tsx
useCopilotAction({
  name: "showFlightOptions",
  parameters: [{ name: "flights", type: "object[]" }],
  // No handler — purely visual.
  render: ({ status, args }) => {
    if (status === "inProgress") return <Skeleton rows={3} />;
    return <FlightCardList flights={args.flights} />;
  },
});
```

`status` cycles: `inProgress` (args streaming) → `executing` (handler running, if any) → `complete`. Use it to show partial UIs while args stream.

### 2. Agent-state render

```tsx
useCoAgentStateRender<MyState>({
  name: "agent",
  render: ({ state, nodeName }) => <NodeView node={nodeName} data={state} />,
});
```

Re-renders on every `StateDelta` from the agent. Good for live dashboards, maps, progress visualizations.

### 3. A2UI tool renderer

A2UI (Agent-to-UI) is a spec for portable UI descriptors that an agent can emit. CopilotKit consumes A2UI surfaces emitted over AG-UI `CustomEvent`s and renders them with built-in or registered components. Use when you want the *agent* to choose the UI shape (form, table, chart) rather than the frontend dev pre-defining each one.

Register A2UI component overrides via the provider:

```tsx
<CopilotKit a2ui={{ components: { TextInput: MyInput, Card: MyCard } }}>
```

## Human-in-the-Loop

### Generic interrupt (framework-agnostic)

```tsx
useHumanInTheLoop({
  name: "confirm-destructive-action",
  render: ({ args, respond }) => (
    <ConfirmDialog
      message={args.summary}
      onConfirm={() => respond({ ok: true })}
      onCancel={() => respond({ ok: false })}
    />
  ),
});
```

The agent calls the tool, the UI renders, agent execution pauses until `respond()` is called.

### LangGraph `interrupt()`

When a LangGraph node calls `interrupt(value)`, CopilotKit surfaces it via:

```tsx
useLangGraphInterrupt({
  render: ({ event, respond }) => (
    <ApprovalForm
      data={event.value}                  // whatever the node passed to interrupt()
      onSubmit={(edited) => respond(edited)}
    />
  ),
});
```

`respond(value)` resumes the graph from the interrupted node with `value` as the resumed input.

### CrewAI HITL

CrewAI emits a special `CustomEvent` for human input requests; the `useHumanInTheLoop` hook handles it transparently.

## Patterns

**Edit-before-execute** — pause on destructive tools (delete, send, deploy), render the agent's proposed args as an editable form, resume with the user's edits.

**Branching approval** — `respond({ branch: "A" })` vs `{ branch: "B" }` and let the agent route accordingly.

**Cancel** — call `respond({ cancelled: true })` and have the agent check for that and `RunError` out cleanly.

**Streaming approval** — combine `useCoAgentStateRender` for the live preview with `useLangGraphInterrupt` for the gate. User sees the agent working, then is asked to approve at the checkpoint.

## Pitfalls

- HITL stalls forever if `respond()` is never called. Add timeout UI for safety.
- `args` during `inProgress` status are *partial* — guard against missing fields.
- A2UI is newest; component override surface may differ between minor versions.
- Don't put non-serializable values (functions, DOM nodes) into `respond()` — they cross the AG-UI wire.
