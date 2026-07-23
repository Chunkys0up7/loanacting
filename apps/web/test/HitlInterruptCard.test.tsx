import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { HitlInterruptCard } from "../src/components/HitlInterruptCard";
import type { HITLRequest } from "../src/types";

function flushPromises() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

const request: HITLRequest = {
  request_id: "inv-1",
  loan_id: "L-1",
  prompt: "Approve the ambiguous document?",
  options: ["approve", "reject"],
  created_at: null,
};

describe("HitlInterruptCard", () => {
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
    vi.unstubAllGlobals();
  });

  it("renders the prompt and one button per option (happy)", () => {
    act(() => {
      root.render(<HitlInterruptCard request={request} loanId="L-1" />);
    });

    expect(container.textContent).toContain("Approve the ambiguous document?");
    const buttons = Array.from(container.querySelectorAll("button")).map((b) => b.textContent);
    expect(buttons).toEqual(["approve", "reject"]);
  });

  it("POSTs the chosen decision to /loans/:loan_id/hitl/:request_id and calls onResolved (happy)", async () => {
    const fetchMock = vi.fn().mockResolvedValue({ ok: true, status: 200, json: async () => ({ result: "accepted" }) });
    vi.stubGlobal("fetch", fetchMock);

    const onResolved = vi.fn();
    act(() => {
      root.render(<HitlInterruptCard request={request} loanId="L-1" baseUrl="http://localhost:4000" onResolved={onResolved} />);
    });

    const approveButton = Array.from(container.querySelectorAll("button")).find((b) => b.textContent === "approve");
    if (!approveButton) throw new Error("approve button not found");

    await act(async () => {
      approveButton.dispatchEvent(new MouseEvent("click", { bubbles: true }));
      await flushPromises();
    });

    expect(fetchMock).toHaveBeenCalledWith(
      "http://localhost:4000/loans/L-1/hitl/inv-1",
      expect.objectContaining({
        method: "POST",
        headers: expect.objectContaining({ "x-operator-id": "web-ui-operator" }),
        body: JSON.stringify({ decision: "approve" }),
      }),
    );
    expect(onResolved).toHaveBeenCalledWith("approve");
  });

  it("calls onError with the conflict response's result when the backend returns 409 (error)", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: false,
        status: 409,
        json: async () => ({ result: "conflict", existing_response: { operator_id: "someone-else" } }),
      }),
    );

    const onError = vi.fn();
    act(() => {
      root.render(<HitlInterruptCard request={request} loanId="L-1" onError={onError} />);
    });

    const approveButton = Array.from(container.querySelectorAll("button")).find((b) => b.textContent === "approve");
    if (!approveButton) throw new Error("approve button not found");

    await act(async () => {
      approveButton.dispatchEvent(new MouseEvent("click", { bubbles: true }));
      await flushPromises();
    });

    expect(onError).toHaveBeenCalledWith("conflict");
  });

  it("calls onError when fetch itself rejects (error)", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("network down")));

    const onError = vi.fn();
    act(() => {
      root.render(<HitlInterruptCard request={request} loanId="L-1" onError={onError} />);
    });

    const approveButton = Array.from(container.querySelectorAll("button")).find((b) => b.textContent === "approve");
    if (!approveButton) throw new Error("approve button not found");

    await act(async () => {
      approveButton.dispatchEvent(new MouseEvent("click", { bubbles: true }));
      await flushPromises();
    });

    expect(onError).toHaveBeenCalledWith("network down");
  });
});
