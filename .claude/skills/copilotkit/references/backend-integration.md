# Backend Integration

CopilotKit's runtime is the broker between your React app and the agent. You have three deployment shapes.

## 1. Next.js route (most common)

`app/api/copilotkit/route.ts`:

```ts
import { CopilotRuntime, OpenAIAdapter, copilotRuntimeNextJSAppRouterEndpoint } from "@copilotkit/runtime";
import OpenAI from "openai";

const runtime = new CopilotRuntime({
  agents: {
    // LangGraph hosted agent
    "research-agent": new LangGraphAgent({
      deploymentUrl: process.env.LANGGRAPH_URL!,
      graphId: "research",
    }),
  },
});

export const POST = async (req: Request) => {
  const { handleRequest } = copilotRuntimeNextJSAppRouterEndpoint({
    runtime,
    serviceAdapter: new OpenAIAdapter({ openai: new OpenAI() }),
    endpoint: "/api/copilotkit",
  });
  return handleRequest(req);
};
```

## 2. Standalone runtime (Express/Fastify/Hono)

Use `copilotRuntimeNodeHttpEndpoint` and mount on any Node HTTP server. Same `CopilotRuntime` construction.

## 3. Remote AG-UI agent (no Node runtime needed)

If your agent already speaks AG-UI directly, point `<CopilotKit runtimeUrl="https://my-agent.example.com/ag-ui" />` at it. No CopilotRuntime in the middle.

## Adapters

| Agent | Adapter |
|---|---|
| OpenAI / Azure OpenAI | `OpenAIAdapter` |
| Anthropic | `AnthropicAdapter` |
| Google (Gemini) | `GoogleGenerativeAIAdapter` |
| Groq | `GroqAdapter` |
| LangChain (JS) | `LangChainAdapter` |
| LangGraph (hosted) | `LangGraphAgent` in `agents` |
| LangGraph (Python, local) | `LangGraphPlatformAgent` or AG-UI bridge |
| CrewAI | `CrewAIAgent` (in `agents`) |
| Generic AG-UI | `HttpAgent` / `RemoteAgent` |

## LangGraph wiring (Python agent)

Python side — install the AG-UI bridge:

```bash
pip install copilotkit langgraph
```

```python
from copilotkit import CopilotKitRemoteEndpoint, LangGraphAgent
from langgraph.graph import StateGraph

graph = StateGraph(MyState)
# ... add nodes ...
compiled = graph.compile()

sdk = CopilotKitRemoteEndpoint(
    agents=[LangGraphAgent(name="research-agent", description="...", graph=compiled)]
)
# Serve sdk via FastAPI: from copilotkit.integrations.fastapi import add_fastapi_endpoint
```

Node runtime points at it:

```ts
const runtime = new CopilotRuntime({
  remoteEndpoints: [{ url: "http://python-agent:8000/copilotkit" }],
});
```

## CrewAI

```python
from copilotkit import CopilotKitRemoteEndpoint, CrewAIAgent
sdk = CopilotKitRemoteEndpoint(agents=[
    CrewAIAgent(name="content-team", description="...", crew=my_crew),
])
```

## Custom AG-UI agent (any language)

Implement the SSE producer from [ag-ui-protocol.md](ag-ui-protocol.md). The frontend can either:
- Talk directly to it (skip CopilotRuntime), or
- Be registered as a `remoteEndpoint` in CopilotRuntime if you want runtime features (threading, persistence, auth).

## Auth & multi-tenancy

- Pass `headers` / `properties` from `<CopilotKit>` → forwarded to runtime → forwarded to agent.
- Use `properties={{ userId, orgId }}` on the provider; read on the server via the request handler context.
- For LangGraph platform, set `auth: { token }` in the agent constructor.
