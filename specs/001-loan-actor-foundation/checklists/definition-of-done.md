# Checklist — Definition of Done (Foundation)

The foundation milestone is **done** when every item below is ticked. PR descriptions for the final batch tick this list; releases gate on it.

## Functional

- [ ] FT-001..FT-040 merged on `main`.
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
- [ ] All four `contracts/*.md` documents reflect the implementation 1:1 (no drift).
- [ ] `README.md` points to the right places (quickstart, constitution, intents, CLAUDE.md).

## Constitution compliance

- [ ] `.specify/memory/constitution.md` v1.0.0 unchanged (no scope creep). If anything required an amendment, the constitution was bumped through the documented procedure.
- [ ] Every merged PR's description ticked the `constitution-compliance.md` checklist.
- [ ] No deferred items marked `TODO` in the constitution.

## Operational

- [ ] CI workflow names and statuses match `tasks.md` Track 1 / FT-004.
- [ ] Backend can be started in <5 s on the reference hardware.
- [ ] Diary on disk passes `verify_chain` for every loan touched during testing.
- [ ] No `:erlang.warning_map/0` entries flagged at boot.

## Sign-off

- [ ] Technical lead approval.
- [ ] Constitution-authority approval (same person OK; document who).
- [ ] Intent author closes the intent with a one-paragraph retrospective in `intents/0001-foundation-loan-as-actor.md` under a new "Retrospective" section (the only legal post-`Implemented` addition).
