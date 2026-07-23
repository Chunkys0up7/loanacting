import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import App from "../src/App";

// FT-029 — proves the Vitest + jsdom + React harness actually renders,
// not just that it's configured. No @testing-library/react (not in
// plan.md's dependency list) — render via react-dom/client directly.
describe("App", () => {
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

  it("renders without crashing", () => {
    act(() => {
      root.render(<App />);
    });

    expect(container.textContent).toContain("Loan as Actor");
  });
});
