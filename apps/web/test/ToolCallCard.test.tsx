import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { ToolCallCard } from "../src/components/ToolCallCard";
import type { ToolCallState } from "../src/lib/tool-calls";

function pendingToolCall(overrides: Partial<ToolCallState> = {}): ToolCallState {
  return {
    toolCallId: "inv-1",
    toolCallName: "request_document",
    loanId: "L-1",
    argsDelta: null,
    ended: false,
    status: "pending",
    result: null,
    ...overrides,
  };
}

describe("ToolCallCard", () => {
  let container: HTMLDivElement;
  let root: Root;

  beforeEach(() => {
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

  it("renders a pending indicator while status is pending (happy)", () => {
    act(() => {
      root.render(<ToolCallCard toolCall={pendingToolCall()} />);
    });

    expect(container.textContent).toContain("request_document");
    expect(container.textContent).toContain("pending");
    expect(container.querySelector("li")?.getAttribute("data-status")).toBe("pending");
  });

  it("stays pending even after ended:true with no result — a long-lived HITL tool call (boundary)", () => {
    act(() => {
      root.render(<ToolCallCard toolCall={pendingToolCall({ ended: true })} />);
    });

    expect(container.querySelector("li")?.getAttribute("data-status")).toBe("pending");
  });

  it("renders the result content once complete (happy)", () => {
    const toolCall = pendingToolCall({
      status: "complete",
      ended: true,
      result: { messageId: "msg-1", content: '{"verify_chain":true}' },
    });

    act(() => {
      root.render(<ToolCallCard toolCall={toolCall} />);
    });

    expect(container.querySelector("li")?.getAttribute("data-status")).toBe("complete");
    expect(container.textContent).toContain("complete");
    expect(container.textContent).toContain('{"verify_chain":true}');
  });

  it("renders an error state for an error-shaped result (error)", () => {
    const toolCall = pendingToolCall({
      status: "complete",
      ended: true,
      result: { messageId: "msg-1", content: '{"error":"goal_not_found"}' },
    });

    act(() => {
      root.render(<ToolCallCard toolCall={toolCall} />);
    });

    expect(container.querySelector("li")?.getAttribute("data-status")).toBe("error");
    expect(container.textContent).toContain("failed");
  });
});
