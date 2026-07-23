import { expect, test } from "@playwright/test";

/**
 * FT-032 — end-to-end proof that LoanView's live wiring works against a
 * REAL backend: spawn a loan through the app's own form, watch the
 * initial StateSnapshot render, send an event through the UI, and see
 * the diary feed and state card update from the live AG-UI stream.
 *
 * Requires `LoanActor.Web.Endpoint` running at http://localhost:4000
 * (`vite.config.ts`'s own dev-server proxy target) — CI starts it as a
 * separate step (`.github/workflows/ci.yml`'s own "Playwright (against
 * booted backend)" line); this file isn't set up to boot it itself.
 */
test("spawning a loan, opening it, and sending an event updates the diary feed and state card", async ({
  page,
}) => {
  await page.goto("/");

  await page.getByRole("button", { name: "Open loan" }).click();

  // No "L-" prefix here — that's an Elixir-test-factory convention
  // (LoanActor.Factory.unique_loan_id/0), not the real runtime format,
  // which is a raw UUIDv7 (Uniq.UUID.uuid7/0, router.ex's own fallback
  // when the caller omits loan_id).
  const heading = page.getByRole("heading", { level: 1 });
  await expect(heading).toContainText(/Loan [0-9a-f-]{36}/, { timeout: 5_000 });

  // The initial StateSnapshot arrives asynchronously over the AG-UI stream.
  await expect(page.getByText("spawned", { exact: true })).toBeVisible({ timeout: 5_000 });

  await page.getByLabel("Event type").selectOption("goal_set");
  await page.getByRole("button", { name: "Send event" }).click();

  await expect(page.getByText(/Event ok \(sequence \d+\)/)).toBeVisible({ timeout: 5_000 });
  await expect(page.getByText("awaiting_documents", { exact: true })).toBeVisible({ timeout: 5_000 });
  await expect(page.locator("li", { hasText: "goal_set" })).toBeVisible();
});
