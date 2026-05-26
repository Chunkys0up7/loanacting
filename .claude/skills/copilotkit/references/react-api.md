# CopilotKit React API

Names and shapes evolve — always cross-check against `node_modules/@copilotkit/*/dist/*.d.ts` or <https://docs.copilotkit.ai/reference> for the version in `package.json`.

## Provider

### `<CopilotKit />`
Wraps the app. Required ancestor for all hooks and UI components.

```tsx
import { CopilotKit } from "@copilotkit/react-core";

<CopilotKit
  runtimeUrl="/api/copilotkit"   // your Next.js route or runtime server
  agent="research-agent"          // optional: name of a CoAgent
  publicApiKey={process.env.NEXT_PUBLIC_CPK_KEY} // optional, for cloud
>
  {children}
</CopilotKit>
```

## UI Components (`@copilotkit/react-ui`)

Import `@copilotkit/react-ui/styles.css` once at the app root.

### `<CopilotChat />`
Inline chat panel. Props: `instructions`, `labels`, `Markdown`, `RenderMessage`, `makeSystemMessage`.

### `<CopilotSidebar />`
Side panel variant; same props as `CopilotChat` plus `defaultOpen`, `clickOutsideToClose`.

### `<CopilotPopup />`
Floating launcher + chat bubble; same props plus `defaultOpen`.

### `<CopilotChatView />` / `<CopilotChatInput />`
Lower-level pieces for custom layouts.

### `<CopilotTextarea />`
Drop-in `<textarea>` with autocomplete from agent context.

```tsx
import { CopilotTextarea } from "@copilotkit/react-textarea";

<CopilotTextarea
  className="..."
  value={text} onValueChange={setText}
  autosuggestionsConfig={{
    textareaPurpose: "Email body to a customer",
    chatApiConfigs: {},
  }}
/>
```

## Hooks (`@copilotkit/react-core`)

### `useCopilotAction({ name, description, parameters, handler?, render? })`
Register an action the agent can call. `handler` runs in the browser; `render` turns the call into a React component (generative UI).

```tsx
useCopilotAction({
  name: "highlightRow",
  description: "Highlight a row in the data table",
  parameters: [
    { name: "rowId", type: "string", required: true },
    { name: "color", type: "string", enum: ["red","yellow","green"] },
  ],
  handler: async ({ rowId, color }) => {
    setHighlight({ rowId, color });
  },
  render: ({ status, args }) =>
    status === "executing" ? <Spinner /> : <Badge>Highlighted {args.rowId}</Badge>,
});
```

### `useCopilotReadable({ description, value, parentId? })`
Expose app state to the agent. Re-runs when `value` changes.

```tsx
useCopilotReadable({
  description: "Currently selected customer",
  value: selectedCustomer,
});
```

### `useCoAgent({ name, initialState })`
Bidirectional state with a stateful agent (LangGraph, CrewAI). Returns `{ state, setState, run, running, nodeName }`.

```tsx
const { state, setState, running } = useCoAgent<ResearchState>({
  name: "research-agent",
  initialState: { topic: "", sources: [] },
});
```

### `useCoAgentStateRender({ name, render })`
Render in the chat transcript whenever the agent's state changes (progress, intermediate results).

```tsx
useCoAgentStateRender<ResearchState>({
  name: "research-agent",
  render: ({ state, nodeName, status }) => (
    <ResearchProgress sources={state.sources} step={nodeName} />
  ),
});
```

### `useLangGraphInterrupt({ render })` (and generic `useHumanInTheLoop`)
Pause LangGraph execution and render an approval/edit UI. The `respond` callback resumes the graph with the user's answer.

```tsx
useLangGraphInterrupt({
  render: ({ event, respond }) => (
    <ApprovalCard
      question={event.value}
      onApprove={() => respond({ approved: true })}
      onReject={() => respond({ approved: false })}
    />
  ),
});
```

### Other hooks
- `useCopilotKit()` — low-level context access (messages, threads, runtime).
- `useFrontendTool()` — newer alias / variant of `useCopilotAction` in some versions.
- `useAgent()` / `useAgentContext()` — direct AG-UI agent access in newer API.
- `useThreads()` — list/rename/archive/delete conversation threads.
- `useChat()` — programmatic access to the chat (append message, abort, regenerate).

## Common pitfalls

- Forgetting `import "@copilotkit/react-ui/styles.css"` → unstyled chat.
- Returning bulky objects from `useCopilotReadable` re-serializes every render. Memoize.
- `useCoAgent` state must be JSON-serializable (no class instances, Dates as ISO strings).
- `parameters` for `useCopilotAction` use a JSON-Schema-like shape, **not** raw JSON Schema. Stick to `type: "string" | "number" | "boolean" | "object" | "string[]" ...` + `enum`.
- The runtime endpoint must run on the **server** (Node, not edge) when adapting Python agents over child_process; edge runtimes work for pure-LLM proxying.
