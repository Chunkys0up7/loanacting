import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { EventSender } from "../src/components/EventSender";

function flushPromises() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

const ALL_EVENT_TYPES = [
  "goal_set",
  "document_uploaded",
  "document_review_requested",
  "operator_approval_required",
  "operator_approval_granted",
  "operator_approval_denied",
  "goal_satisfied",
  "goal_abandoned",
  "complete",
  "abort",
  "heartbeat",
];

describe("EventSender", () => {
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

  it("renders every documented event type as a select option", () => {
    act(() => {
      root.render(<EventSender loanId="L-1" />);
    });

    const values = Array.from(container.querySelectorAll("option")).map((o) => (o as HTMLOptionElement).value);
    expect(values).toEqual(expect.arrayContaining(ALL_EVENT_TYPES));
    expect(values).toHaveLength(ALL_EVENT_TYPES.length);
  });

  it("POSTs to /loans/:loan_id/events and calls onSent on success (happy)", async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      status: 202,
      json: async () => ({ result: "ok", sequence: 3 }),
    });
    vi.stubGlobal("fetch", fetchMock);

    const onSent = vi.fn();
    act(() => {
      root.render(<EventSender loanId="L-1" baseUrl="http://localhost:4000" onSent={onSent} />);
    });

    const form = container.querySelector("form");
    if (!form) throw new Error("form not found");

    await act(async () => {
      form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
      await flushPromises();
    });

    expect(fetchMock).toHaveBeenCalledWith(
      "http://localhost:4000/loans/L-1/events",
      expect.objectContaining({ method: "POST" }),
    );
    expect(onSent).toHaveBeenCalledWith({ result: "ok", sequence: 3 });
  });

  it("calls onError with the backend's error when the response is not ok (error)", async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: false,
      status: 422,
      json: async () => ({ error: "pii_violation" }),
    });
    vi.stubGlobal("fetch", fetchMock);

    const onError = vi.fn();
    act(() => {
      root.render(<EventSender loanId="L-1" onError={onError} />);
    });

    const form = container.querySelector("form");
    if (!form) throw new Error("form not found");

    await act(async () => {
      form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
      await flushPromises();
    });

    expect(onError).toHaveBeenCalledWith("pii_violation");
  });

  it("calls onError when fetch itself rejects (error)", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("network down")));

    const onError = vi.fn();
    act(() => {
      root.render(<EventSender loanId="L-1" onError={onError} />);
    });

    const form = container.querySelector("form");
    if (!form) throw new Error("form not found");

    await act(async () => {
      form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
      await flushPromises();
    });

    expect(onError).toHaveBeenCalledWith("network down");
  });
});
