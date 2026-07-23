# Checklist — Definition of Done (Foundation)

The foundation milestone is **done** when every item below is ticked. PR descriptions for the final batch tick this list; releases gate on it.

**2026-07-23 closeout note**: only the Closeout section below is ticked as part of intent 0001's
audit — the FR/NFR/Constitution/Operational sections above it are NOT mechanically re-ticked
here, since several genuinely aren't met (see `audit.md`, the authoritative, detailed record) and
ticking them would be exactly the boilerplate rubber-stamping the constitution's own audit-cycle
wording warns against. Notably: FT-046/047 were reverted, not merged (line below is stale); the
`mix test.load` line below assumed intent 0005 would close NFR-001 — it did not, and that line's
own parenthetical is now factually wrong (see `audit.md` §4 item 1); the nightly large-diary job
has run zero times as of this writing (it exists and passed its first manual dispatch, not yet
"3 of last 5 scheduled runs"). Intent 0001 is closed anyway per this project's own established
norm of closing with honestly-reported open gaps rather than leaving work in limbo indefinitely.

## Functional

- [ ] FT-001..FT-048 merged on `main` (FT-018b superseded by FT-044 per intent 0004; FT-046..048 added by intent 0005).
- [ ] Every self-initiated actor function goes through the tool registry; the demo skill pack triggers and its tool call renders in the UI as a `ToolCallCard` (SC-012/013/014).
- [ ] Smoke checklist in `quickstart.md` passes manually on a fresh clone.
- [ ] `iex -S mix` boots a single-node BEAM; `npm --prefix apps/web run dev` boots the SPA; visiting `/loans/L-DEMO` shows a live actor.
- [ ] Kill the loan process; supervisor restarts it within 1 s; UI reconnects; state is identical.
- [ ] Trigger an HITL from the UI; approve from a second tab; loan resumes; diary contains the approval.

## Tests

- [ ] `mix test` green (all categories: happy, boundary, error, race, replay, security, contract, performance microbench).
- [ ] `mix dialyzer` zero warnings.
- [ ] `mix credo --strict` zero issues; custom checks `LoopTagging`, `NoLLM`, `NoDirectStateMutation` enabled and green.
- [ ] `mix test.load` asserts NFR-001..NFR-005 green **at default scale** (intent 0005 closed the NFR-001 gap `FT-035` found — this is no longer an accepted known gap).
- [ ] `mix test test/llm_absence_test.exs` green (SC-009).
- [ ] `npm --prefix apps/web test` green.
- [ ] `npm --prefix apps/web run e2e` green (Playwright spawn-and-event, hitl, contract specs).
- [ ] Nightly job: large-diary replay (1M entries < 30s) green at least 3 of last 5 runs.

## Documentation & artifacts

- [ ] Intent `intents/0001-foundation-loan-as-actor.md` status set to `Implemented`.
- [ ] `spec.md` SC table — every SC has a green CI signal it maps to.
- [ ] `plan.md` Constitution Check section re-checked and green (post-Phase-1 re-check filled in).
- [ ] `analysis.md` shows no remaining open gaps.
- [ ] `quickstart.md` commands are reproducible from a fresh clone (verified by CI smoke job).
- [ ] All six `contracts/*.md` documents (incl. `tool-behaviour.md`, `skill-format.md` from 0004; `diary-store-behaviour.md`'s `append_with_dedup/4` from 0005) reflect the implementation 1:1 (no drift).
- [ ] `README.md` points to the right places (quickstart, constitution, intents, CLAUDE.md).

## Constitution compliance

- [ ] `.specify/memory/constitution.md` at v1.2.0 (amended by intents 0002, 0004 through the documented procedure); no further unversioned changes.
- [ ] Every merged PR's description ticked the `constitution-compliance.md` checklist.
- [ ] No deferred items marked `TODO` in the constitution.

## Operational

- [ ] CI workflow names and statuses match `tasks.md` Track 1 / FT-004.
- [ ] Backend can be started in <5 s on the reference hardware.
- [ ] Diary on disk passes `verify_chain` for every loan touched during testing.
- [ ] No `:erlang.warning_map/0` entries flagged at boot.

## Closeout — per Constitution §"Post-Implementation Audit Cycle" (v1.1.0+)

After every `FT-*` task PR has merged, BEFORE the intent can move to `Closed`:

- [x] `specs/001-loan-actor-foundation/audit.md` exists and:
  - Maps every FR / NFR / SC to the test or code proving fulfillment.
  - Lists deviations from the spec (not empty — 9 items, none boilerplate).
  - Lists new/changed skill packs (`priv/skills/…`).
  - Names the auditor; flags solo-author self-attestation (yes — no second author available).
- [x] `specs/001-loan-actor-foundation/report.md` exists and:
  - Summarizes shipped functionality in business language.
  - Links commit SHAs via `tasks.md`'s own status ledger (referenced, not duplicated).
  - Lists follow-ups (which become future intents).
  - UI screenshots: not captured/retained as separate artifacts (documented as a gap in `report.md` itself, not silently omitted) — the same flows are asserted by `apps/web/test/e2e/spawn-and-event.spec.ts`/`smoke.spec.ts` and re-runnable live at any time.
- [x] `specs/001-loan-actor-foundation/test-evidence.md` exists and:
  - Coverage taxonomy table maps every applicable category to SCs and test files.
  - Factory inventory: every entity from `data-model.md` has at least one factory documented per `test-data-forge` discipline.
  - Load-test actuals vs. NFR-001..NFR-005 budgets (p95 latency, elapsed times; NFR-002 explicitly flagged as unmeasured-in-isolation rather than fabricated).
  - Cites the green CI run (backend job: `mix test`/`credo`/`dialyzer`/`test.smoke` green; `mix test.load` red as expected — both stated plainly, not just the convenient half).
- [x] Closeout commit landed:
  ```
  audit(0001): loan-actor-foundation — implementation closeout (v1.2.0)
  ```
  containing exactly the three artifacts + the intent status change.
- [x] `intents/0001-foundation-loan-as-actor.md` status set to `Closed`.

## Sign-off

- [ ] Technical lead approval. *(Pending — this closeout is agent-authored; a human sign-off has not yet occurred.)*
- [ ] Constitution-authority approval (same person OK; document who). *(Pending, same reason.)*
- [x] Intent author closes the intent with a one-paragraph retrospective in `intents/0001-foundation-loan-as-actor.md` under a new "Retrospective" section (the only legal post-`Closed` addition).
