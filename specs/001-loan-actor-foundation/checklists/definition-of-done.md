# Checklist — Definition of Done (Foundation)

The foundation milestone is **done** when every item below is ticked. PR descriptions for the final batch tick this list; releases gate on it.

## Functional

- [ ] FT-001..FT-045 merged on `main` (FT-018b superseded by FT-044 per intent 0004).
- [ ] Every self-initiated actor function goes through the tool registry; the demo skill pack triggers and its tool call renders in the UI as a `ToolCallCard` (SC-012/013/014).
- [ ] Smoke checklist in `quickstart.md` passes manually on a fresh clone.
- [ ] `iex -S mix` boots a single-node BEAM; `npm --prefix apps/web run dev` boots the SPA; visiting `/loans/L-DEMO` shows a live actor.
- [ ] Kill the loan process; supervisor restarts it within 1 s; UI reconnects; state is identical.
- [ ] Trigger an HITL from the UI; approve from a second tab; loan resumes; diary contains the approval.

## Tests

- [ ] `mix test` green (all categories: happy, boundary, error, race, replay, security, contract, performance microbench).
- [ ] `mix dialyzer` zero warnings.
- [ ] `mix credo --strict` zero issues; custom checks `LoopTagging`, `NoLLM`, `NoDirectStateMutation` enabled and green.
- [ ] `mix test.load` asserts NFR-001..NFR-005 green.
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
- [ ] All six `contracts/*.md` documents (incl. `tool-behaviour.md`, `skill-format.md` from 0004) reflect the implementation 1:1 (no drift).
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

- [ ] `specs/001-loan-actor-foundation/audit.md` exists and:
  - Maps every FR / NFR / SC to the test or code proving fulfillment.
  - Lists deviations from the spec (empty list explicitly stated, not omitted).
  - Lists new/changed skill packs (`priv/skills/…`).
  - Names the auditor; flags solo-author self-attestation if applicable.
- [ ] `specs/001-loan-actor-foundation/report.md` exists and:
  - Summarizes shipped functionality in business language.
  - Links PRs / commit SHAs by tasks.md track.
  - Lists follow-ups (which become future intents).
  - Includes UI screenshots / recordings for the LoanView surfaces.
- [ ] `specs/001-loan-actor-foundation/test-evidence.md` exists and:
  - Coverage taxonomy table maps every applicable category to SCs and test files.
  - Factory inventory: every entity from `data-model.md` has at least one factory documented per `test-data-forge` discipline.
  - Load-test actuals (p50/p95/p99 latency, peak memory, throughput) vs. NFR-001..NFR-005 budgets.
  - Cites the green CI run.
- [ ] Closeout commit landed:
  ```
  audit(0001): loan-actor-foundation — implementation closeout (v1.0.0)
  ```
  containing exactly the three artifacts + the intent status change.
- [ ] `intents/0001-foundation-loan-as-actor.md` status set to `Closed`.

## Sign-off

- [ ] Technical lead approval.
- [ ] Constitution-authority approval (same person OK; document who).
- [ ] Intent author closes the intent with a one-paragraph retrospective in `intents/0001-foundation-loan-as-actor.md` under a new "Retrospective" section (the only legal post-`Closed` addition).
