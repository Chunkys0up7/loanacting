import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { StateCard } from "../src/components/StateCard";
import type { LoanState } from "../src/types";

describe("StateCard", () => {
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

  it("renders a loading placeholder when state is null (boundary)", () => {
    act(() => {
      root.render(<StateCard state={null} />);
    });

    expect(container.textContent).toContain("Loading state…");
  });

  it("renders status, version, and heartbeat", () => {
    const state: LoanState = {
      loan_id: "L-1",
      status: "awaiting_documents",
      goals: [],
      context: {},
      version: 3,
      last_heartbeat_at: "2026-01-01T00:00:00Z",
    };

    act(() => {
      root.render(<StateCard state={state} />);
    });

    expect(container.textContent).toContain("Loan L-1");
    expect(container.textContent).toContain("awaiting_documents");
    expect(container.textContent).toContain("3");
    expect(container.textContent).toContain("2026-01-01T00:00:00Z");
  });

  it("renders \"No goals yet.\" for an empty goals list (boundary)", () => {
    const state: LoanState = {
      loan_id: "L-1",
      status: "spawned",
      goals: [],
      context: {},
      version: 0,
      last_heartbeat_at: null,
    };

    act(() => {
      root.render(<StateCard state={state} />);
    });

    expect(container.textContent).toContain("No goals yet.");
    expect(container.textContent).toContain("never");
  });

  it("renders each goal's description and status", () => {
    const state: LoanState = {
      loan_id: "L-1",
      status: "awaiting_documents",
      goals: [
        { goal_id: "G-1", description: "Obtain income documentation", status: "open", due_at: null },
        { goal_id: "G-2", description: "Verify identity", status: "satisfied", due_at: null },
      ],
      context: {},
      version: 1,
      last_heartbeat_at: null,
    };

    act(() => {
      root.render(<StateCard state={state} />);
    });

    expect(container.textContent).toContain("Obtain income documentation");
    expect(container.textContent).toContain("open");
    expect(container.textContent).toContain("Verify identity");
    expect(container.textContent).toContain("satisfied");
  });
});
