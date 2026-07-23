import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { DiaryFeed } from "../src/components/DiaryFeed";
import type { DiaryEntry } from "../src/types";

function entry(overrides: Partial<DiaryEntry>): DiaryEntry {
  return {
    loan_id: "L-1",
    sequence: 0,
    timestamp: "2026-01-01T00:00:00Z",
    type: "spawned",
    actor: "system",
    payload_hash: "aa",
    payload_ref: null,
    prev_hash: "00",
    ...overrides,
  };
}

describe("DiaryFeed", () => {
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

  it("renders a placeholder for an empty diary (boundary)", () => {
    act(() => {
      root.render(<DiaryFeed entries={[]} />);
    });

    expect(container.textContent).toContain("No diary entries yet.");
  });

  it("renders every entry's sequence, type, and actor, in arrival order", () => {
    const entries = [
      entry({ sequence: 0, type: "spawned", actor: "system" }),
      entry({ sequence: 1, type: "goal_set", actor: "operator" }),
    ];

    act(() => {
      root.render(<DiaryFeed entries={entries} />);
    });

    const items = container.querySelectorAll("li");
    expect(items).toHaveLength(2);
    expect(items[0]?.textContent).toContain("#0");
    expect(items[0]?.textContent).toContain("spawned");
    expect(items[0]?.textContent).toContain("system");
    expect(items[1]?.textContent).toContain("#1");
    expect(items[1]?.textContent).toContain("goal_set");
    expect(items[1]?.textContent).toContain("operator");
  });
});
