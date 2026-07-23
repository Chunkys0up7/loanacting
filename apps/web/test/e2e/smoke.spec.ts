import { expect, test } from "@playwright/test";

// FT-029 — proves the Playwright harness actually drives a browser
// against the Vite dev server, not just that it's configured.
// LoanView (FT-032) replaces this page's content; real backend-driven
// e2e flows (spawn-and-event.spec.ts, hitl.spec.ts) arrive with their
// owning tasks.
test("the scaffold page loads and renders the placeholder heading", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Loan as Actor" })).toBeVisible();
});
