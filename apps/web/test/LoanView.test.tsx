import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { AGUIClientHandlers } from "../src/lib/ag-ui-client";

let capturedHandlers: AGUIClientHandlers | null = null;

vi.mock("../src/lib/ag-ui-client", () => ({
  consumeAGUIStream: vi.fn((_options: unknown, handlers: AGUIClientHandlers) => {
    capturedHandlers = handlers;
    return Promise.resolve();
  }),
}));

// Imported after the mock so LoanView picks up the mocked module.
const { LoanView } = await import("../src/pages/LoanView");

/**
 * FT-032 — proves the useCoAgent/ag-ui-client wiring itself: an incoming
 * event dispatched to the captured handlers is what actually drives
 * StateCard/DiaryFeed, not just that the components render in isolation
 * (StateCard.test.tsx/DiaryFeed.test.tsx already cover that).
 */
describe("LoanView", () => {
  let container: HTMLDivElement;
  let root: Root;

  beforeEach(() => {
    capturedHandlers = null;
    container = document.createElement("div");
    document.body.appendChild(container);
    root = createRoot(container);
  });

  afterEach(() => {
    act(() => {
      root.unmount();
    });
    container.remove();
  });

  it("renders a StateSnapshot's state into StateCard (happy)", () => {
    act(() => {
      root.render(<LoanView loanId="L-1" />);
    });

    expect(capturedHandlers).not.toBeNull();

    act(() => {
      capturedHandlers?.onEvent({
        type: "StateSnapshot",
        loan_id: "L-1",
        state: {
          loan_id: "L-1",
          status: "awaiting_documents",
          goals: [],
          context: {},
          version: 1,
          last_heartbeat_at: null,
        },
      });
    });

    expect(container.textContent).toContain("awaiting_documents");
  });

  it("appends a diary_entry CustomEvent to the diary feed (happy)", () => {
    act(() => {
      root.render(<LoanView loanId="L-1" />);
    });

    act(() => {
      capturedHandlers?.onEvent({
        type: "CustomEvent",
        name: "diary_entry",
        loan_id: "L-1",
        entry: {
          loan_id: "L-1",
          sequence: 1,
          timestamp: "2026-01-01T00:00:00Z",
          type: "goal_set",
          actor: "operator",
          payload_hash: "aa",
          payload_ref: null,
          prev_hash: "bb",
        },
      });
    });

    expect(container.textContent).toContain("goal_set");
  });

  it("applies a StateDelta whole-state replace patch (contract: server.ex's single-root-replace scope)", () => {
    act(() => {
      root.render(<LoanView loanId="L-1" />);
    });

    act(() => {
      capturedHandlers?.onEvent({
        type: "StateDelta",
        loan_id: "L-1",
        patch: [
          {
            op: "replace",
            path: "",
            value: { loan_id: "L-1", status: "processing", goals: [], context: {}, version: 5, last_heartbeat_at: null },
          },
        ],
      });
    });

    expect(container.textContent).toContain("processing");
  });

  it("renders a ToolCallCard, correlated across Start/Args/End/Result (happy, FT-045)", () => {
    act(() => {
      root.render(<LoanView loanId="L-1" />);
    });

    act(() => {
      capturedHandlers?.onEvent({ type: "ToolCallStart", tool_call_id: "inv-1", tool_call_name: "verify_diary_chain", loan_id: "L-1" });
      capturedHandlers?.onEvent({ type: "ToolCallArgs", tool_call_id: "inv-1", delta: "{}" });
      capturedHandlers?.onEvent({ type: "ToolCallEnd", tool_call_id: "inv-1" });
    });

    expect(container.textContent).toContain("verify_diary_chain");
    expect(container.querySelector("[data-status]")?.getAttribute("data-status")).toBe("pending");

    act(() => {
      capturedHandlers?.onEvent({
        type: "ToolCallResult",
        message_id: "msg-1",
        tool_call_id: "inv-1",
        content: '{"verify_chain":true}',
      });
    });

    expect(container.querySelector("[data-status]")?.getAttribute("data-status")).toBe("complete");
  });

  it("surfaces an unrecognized event as an alert rather than dropping it (error)", () => {
    act(() => {
      root.render(<LoanView loanId="L-1" />);
    });

    act(() => {
      capturedHandlers?.onUnknownEvent({ type: "SomethingWeird" });
    });

    expect(container.querySelector('[role="alert"]')?.textContent).toContain("unrecognized");
  });

  it("surfaces a connection error as an alert (error)", () => {
    act(() => {
      root.render(<LoanView loanId="L-1" />);
    });

    act(() => {
      capturedHandlers?.onError?.(new Error("stream closed"));
    });

    expect(container.querySelector('[role="alert"]')?.textContent).toContain("stream closed");
  });
});
