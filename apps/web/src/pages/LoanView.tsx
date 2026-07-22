import { useEffect, useState } from "react";
import { CopilotKit, useCoAgent, useCoAgentStateRender } from "@copilotkit/react-core";
import { consumeAGUIStream } from "../lib/ag-ui-client";
import { StateCard } from "../components/StateCard";
import { DiaryFeed } from "../components/DiaryFeed";
import { EventSender } from "../components/EventSender";
import type { AGUIEvent, DiaryEntry, LoanState } from "../types";

export interface LoanViewProps {
  loanId: string;
  baseUrl?: string;
}

function emptyLoanState(loanId: string): LoanState {
  return { loan_id: loanId, status: "spawned", goals: [], context: {}, version: 0, last_heartbeat_at: null };
}

/**
 * FT-032 — the live loan page: subscribes to `/loans/:loan_id/ag-ui` via
 * `ag-ui-client.ts` (FT-030) and renders `StateCard`/`DiaryFeed`/
 * `EventSender` from the resulting state.
 *
 * `useCoAgent`'s **external state management** variant (`{name, state,
 * setState}`, not `initialState`) is the wiring point: this app owns the
 * actual data flow (our own already-proven SSE consumer), and hands the
 * result to CopilotKit rather than asking CopilotKit's own runtime/agent
 * machinery to fetch it — that machinery is built around its own
 * `{messages, tools}` chat protocol, not this loan's
 * `{thread_id, since_sequence}` AG-UI endpoint.
 *
 * `state` must never be `null`/`undefined` — confirmed empirically
 * against a real browser (Playwright, not just jsdom): CopilotKit's
 * internal agent-registry bookkeeping crashes
 * (`TypeError: Cannot read properties of undefined (reading 'length')`)
 * the moment a coagent's external state is nullish, even before any
 * `render`/network activity. `displayState` (`LoanState | null`, so
 * `StateCard` can still show its own loading placeholder before the
 * first `StateSnapshot` arrives) stays separate from what's actually
 * handed to `useCoAgent`, which always gets a well-formed placeholder
 * object until real data replaces it.
 *
 * `useCoAgentStateRender`'s `render` is intentionally inert (`() =>
 * null`): it only fires from state CopilotKit's own internal
 * agent-run tracking populates, which nothing here triggers (there's
 * no `<CopilotChat>`/message-transcript surface to display it in even
 * if it did) — `StateCard`/`DiaryFeed` render directly from
 * `displayState`/`diaryEntries` instead, which IS provably live.
 */
function LoanViewInner({ loanId, baseUrl }: LoanViewProps) {
  const [displayState, setDisplayState] = useState<LoanState | null>(null);
  const [diaryEntries, setDiaryEntries] = useState<DiaryEntry[]>([]);
  const [connectionError, setConnectionError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  useCoAgent<LoanState>({
    name: "loan-actor",
    state: displayState ?? emptyLoanState(loanId),
    setState: (next) => setDisplayState(typeof next === "function" ? next(displayState ?? undefined) : next),
  });

  useCoAgentStateRender<LoanState>({
    name: "loan-actor",
    render: () => null,
  });

  useEffect(() => {
    const controller = new AbortController();

    void consumeAGUIStream(
      { loanId, baseUrl, signal: controller.signal },
      {
        onEvent: (event: AGUIEvent) => {
          switch (event.type) {
            case "StateSnapshot":
              setDisplayState(event.state);
              break;

            case "StateDelta": {
              // Foundation only ever emits one whole-state "replace" at the
              // root path (server.ex's own scope note, no incremental-diff
              // engine) — applying the patch's value directly is exactly
              // as much as this contract requires, not a generic RFC 6902
              // JSON Patch implementation.
              const op = event.patch[0];
              if (op && op.op === "replace" && op.path === "") {
                setDisplayState(op.value as LoanState);
              }
              break;
            }

            case "CustomEvent":
              if (event.name === "diary_entry") {
                setDiaryEntries((previous) => [...previous, event.entry]);
              }
              break;

            default:
              break;
          }
        },
        onUnknownEvent: () => {
          // Strict per ag-ui-client.ts's own contract — surfaced, not dropped.
          setConnectionError("received an unrecognized AG-UI event");
        },
        onError: (error) => setConnectionError(error.message),
      },
    );

    return () => controller.abort();
  }, [loanId, baseUrl]);

  return (
    <main>
      <h1>Loan {loanId}</h1>
      {connectionError && <p role="alert">{connectionError}</p>}
      {notice && <p role="status">{notice}</p>}
      <StateCard state={displayState} />
      <DiaryFeed entries={diaryEntries} />
      <EventSender
        loanId={loanId}
        baseUrl={baseUrl}
        onSent={(result) => setNotice(`Event ${result.result} (sequence ${result.sequence})`)}
        onError={(message) => setConnectionError(message)}
      />
    </main>
  );
}

export function LoanView({ loanId, baseUrl }: LoanViewProps) {
  // CopilotKit validates at runtime (despite typing the prop optional) that
  // one of runtimeUrl/publicApiKey/publicLicenseKey is set, or throws
  // ConfigurationError on mount. Points at our own per-loan AG-UI endpoint —
  // the "remote AG-UI agent" pattern the CopilotKit skill docs recommend —
  // even though this page's actual data flow doesn't depend on CopilotKit's
  // own runtime machinery reaching it correctly (see this component's own
  // moduledoc-equivalent comment above).
  const runtimeUrl = `${baseUrl ?? ""}/loans/${encodeURIComponent(loanId)}/ag-ui`;

  return (
    <CopilotKit
      runtimeUrl={runtimeUrl}
      // This page never depends on CopilotKit's own runtime connecting
      // (see above) — its built-in AG-UI Inspector (enabled by default)
      // would otherwise show a permanently-stuck "Connecting..." banner,
      // which is misleading rather than useful here. showDevConsole is
      // a different (deprecated) toggle for error toasts/banners only —
      // enableInspector is what actually controls this panel.
      enableInspector={false}
      onError={({ type, error }) => {
        // Deliberately not surfaced to the user (LoanViewInner's own
        // connectionError state is for our own ag-ui-client stream, which
        // is what actually drives this page) — logged only so a real
        // misconfiguration isn't silent.
        console.warn("[CopilotKit]", type, error);
      }}
    >
      <LoanViewInner loanId={loanId} baseUrl={baseUrl} />
    </CopilotKit>
  );
}
