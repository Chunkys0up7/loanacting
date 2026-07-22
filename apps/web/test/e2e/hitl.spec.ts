import { expect, test } from "@playwright/test";
import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

/**
 * FT-033 — end-to-end proof that HitlInterruptCard's real flow (driven
 * by the `hitl_request` CustomEvent + a direct POST to
 * `/loans/:loan_id/hitl/:request_id`, NOT `useHumanInTheLoop`'s
 * CopilotKit-chat-tool machinery — see LoanView.tsx's own comment)
 * genuinely works against a REAL backend.
 *
 * `request_operator_approval` only ever fires from the planning loop
 * when a matched skill names it (no public invoke API, Principle I) —
 * the default installed pack (`0001-demo-document-request`) doesn't.
 * `LoanActor.Skill.Loader` re-reads `priv/skills/` from disk on every
 * loop pass (no cache to invalidate — its own moduledoc), so writing a
 * temporary pack here needs no backend restart; `test.afterAll` removes
 * it so this file leaves no permanent trace, mirroring the same
 * approach the Elixir-side `hitl_test.exs`/`router_test.exs` already use
 * (a temp skill pack, not a permanent addition to `priv/skills/` — that
 * would be inventing "when to use" skill content beyond what this task
 * asks for).
 *
 * Requires `LoanActor.Web.Endpoint` running at http://localhost:4000,
 * same as `spawn-and-event.spec.ts` — and, unlike that file, ALSO
 * requires it to already be running (not freshly started after this
 * writes the pack): `mix` copies `apps/loan_actor/priv/` into
 * `_build/<env>/lib/loan_actor/priv/` at compile time, and a running
 * node reads from that copy, not the source tree. A backend started
 * fresh after this pack exists picks it up from the source tree fine
 * either way; writing to both is what makes this work against an
 * ALREADY-running one too, confirmed empirically (a source-tree-only
 * write was invisible to a backend already up).
 */
const sourceSkillPackDir = path.join(__dirname, "..", "..", "..", "loan_actor", "priv", "skills", "0099-e2e-hitl-temp");
const buildSkillPackDir = path.join(
  __dirname,
  "..",
  "..",
  "..",
  "..",
  "_build",
  "dev",
  "lib",
  "loan_actor",
  "priv",
  "skills",
  "0099-e2e-hitl-temp",
);

const skillMd = [
  "---",
  "name: e2e-hitl-temp",
  "version: 1.0.0",
  "description: During plan review, ask the operator to approve or reject this loan.",
  "tools_required: [request_operator_approval]",
  "---",
  "",
  "Body.",
  "",
].join("\n");

test.beforeAll(() => {
  for (const dir of [sourceSkillPackDir, buildSkillPackDir]) {
    mkdirSync(dir, { recursive: true });
    writeFileSync(path.join(dir, "SKILL.md"), skillMd);
  }
});

test.afterAll(() => {
  for (const dir of [sourceSkillPackDir, buildSkillPackDir]) {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("responding to a HITL request through the UI resolves it and shows the tool call's outcome", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("button", { name: "Open loan" }).click();

  await expect(page.getByText("spawned", { exact: true })).toBeVisible({ timeout: 5_000 });

  await page.getByLabel("Event type").selectOption("goal_set");
  await page.getByRole("button", { name: "Send event" }).click();

  // The planning loop's skill match invokes request_operator_approval
  // asynchronously, after the goal_set reactive transition.
  const approveButton = page.getByRole("button", { name: "approve" });
  await expect(approveButton).toBeVisible({ timeout: 10_000 });

  await approveButton.click();

  await expect(page.getByText(/Responded approve to request/)).toBeVisible({ timeout: 5_000 });
  await expect(page.getByText("No pending approvals.")).toBeVisible();
  await expect(page.locator("[data-status='complete']", { hasText: "request_operator_approval" })).toBeVisible();
});
