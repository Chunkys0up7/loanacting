# Analysis — Loan-Actor Foundation

Cross-artifact consistency check across:

- [`../../.specify/memory/constitution.md`](../../.specify/memory/constitution.md) v1.0.0
- [`../../intents/0001-foundation-loan-as-actor.md`](../../intents/0001-foundation-loan-as-actor.md)
- [`spec.md`](spec.md)
- [`clarifications.md`](clarifications.md)
- [`plan.md`](plan.md)
- [`research.md`](research.md)
- [`data-model.md`](data-model.md)
- [`quickstart.md`](quickstart.md)
- [`contracts/`](contracts/)

Date: 2026-05-26. This document is the gate that `/speckit-tasks` consumes.

---

## Constitution → spec/plan matrix

| Constitution principle | Spec evidence | Plan evidence | Status |
|---|---|---|---|
| I. Loan-is-the-actor | FR-001, FR-006, US-1 | `LoanActor.Supervisor` + per-loan `LoanActor.Server`; no central orchestrator | ✅ |
| II. Three-loop harness | FR-006 | `LoanActor.Server` with reactive (`handle_call/cast`), periodic (`handle_info(:heartbeat,_)`), planning (`:plan` self-message); Credo check `LoanActor.Credo.LoopTagging` | ✅ |
| III. Deterministic-first, LLM-escalated | FR-014, SC-009 | `test/llm_absence_test.exs`; Credo check `LoanActor.Credo.NoLLM`; no LLM deps in `mix.exs` | ✅ |
| IV. Immutable diary | FR-003, FR-005, FR-013, SC-006, SC-007 | `DiaryStore` behaviour with chain linkage; `verify_chain/1`; replay tests; tamper test | ✅ |
| V. Test-first, taxonomic coverage | SC-001..SC-010 | Test directory layout in `plan.md` enumerates happy/boundary/error/race/replay/security; tasks.md will tag each task with its taxonomy categories | ✅ |
| VI. Operating procedures are content | FR (implicit) | `procedure_loader.ex` + `priv/procedures/0001-noop.md`; **gap**: no test asserts the loader picks up a new procedure file at runtime | ⚠ Gap-1 |
| VII. Portable identity & artifacts | FR-001 (UUIDv7), all artifacts committed | spec/clarifications/plan/research/data-model/quickstart/contracts all committed; tasks.md + checklists pending | ✅ (pending tasks/checklist) |
| Architectural invariants (BEAM) | Implicit | Plan technical context: Elixir 1.16 / OTP 26 / Bandit / Mnesia | ✅ |
| Architectural invariants (UI) | FR-007, FR-009, US-1, US-3 | `apps/web` Vite + React + CopilotKit; AG-UI emitted from BEAM directly | ✅ |
| Architectural invariants (PII out of diary) | FR-011, SC-010 | `pii_guard.ex`; payload_hash covers PII-stripped payload | ✅ |
| Architectural invariants (perf budget) | NFR-001..NFR-005 | `test/load/nfr_load_test.exs` (task FT-027) | ✅ |
| Anti-vibe: no stubs without intent | — | One stub (procedure_loader) justified in plan §Constitution Check as required by Principle VI | ✅ |
| Anti-vibe: examples are tests | — | quickstart.md commands run in CI as smoke check | ✅ |

---

## Intent → spec coverage

Intent 0001 lists 11 success criteria. Each maps to one or more spec SCs:

| Intent SC | Spec SC | Notes |
|---|---|---|
| Spawn produces supervised pid + first diary entry | SC-001 (spawn covered), US-1 acceptance #1 | ✅ |
| Event acceptance < 100 ms p95 | SC-001 (load test) | ✅ |
| Reactive determinism (replay = same state) | SC-004 (property-based replay) | ✅ |
| Heartbeat fires + diary entry | Spec has `:heartbeat` in event-type enum; **but no explicit SC asserts heartbeat firing** | ⚠ Gap-2 |
| Planning loop emits outbound event on goal | US-3 (HITL is one such outbound); **no explicit SC for a non-HITL planning emission** | ⚠ Gap-3 |
| Crash recovery < 1s, byte-identical state | SC-002, NFR-003 | ✅ |
| Idempotency on duplicate event_id | SC-003, FR-004 | ✅ |
| AG-UI events RunStarted → StateSnapshot → StateDelta | contracts/ag-ui-events.md + frontend contract test | ✅ |
| CopilotKit UI live updates | US-1 #2, US-1 #3 | ✅ |
| HITL stub round-trip | US-3, SC-005 | ✅ |
| Test taxonomy coverage | SC-008 | ✅ |
| No mocks at boundaries | Constitution Principle V; plan testing strategy | ✅ |
| Performance budget asserted | SC-001, SC-002, SC-007, NFR-001..NFR-005 | ✅ |

---

## Gaps to close before `/speckit-tasks`

### Gap-1 — Procedure loader needs a runtime test

**Issue.** Constitution Principle VI ("operating procedures are content") demands the loader prove it can pick up procedures. The plan ships one no-op procedure but no test that adding a second procedure makes it visible.

**Resolution.** Add task **FT-018b**: write `apps/loan_actor/test/procedure_loader_test.exs` that
1. Drops a temporary procedure file under a test-scoped `priv/procedures/` path
2. Calls `ProcedureLoader.reload/0`
3. Asserts the new procedure is listed.

Cost: small. Closes the gap.

### Gap-2 — No SC for heartbeat firing

**Issue.** Intent calls for the periodic loop to fire on a configured interval; the spec models the event but no SC asserts cadence.

**Resolution.** Add to spec:

> **SC-011**: Configure heartbeat interval to 1 second; over 10 seconds observe ≥ 9 and ≤ 11 `:heartbeat` diary entries on a single loan. (Verifies FR-006 periodic loop.)

I will append this to `spec.md` as part of analyze-output. Re-check after edit.

### Gap-3 — No SC for non-HITL planning emission

**Issue.** Intent calls for the planning loop to emit outbound events when goals are set; the only planning path the spec exercises is HITL.

**Resolution.** Add to spec:

> **SC-012**: Given a loan with goal `:require_document(:income)`, when the goal is set, the planning loop within one heartbeat emits a `CustomEvent name="document_request"` event over AG-UI. (Verifies planning loop semantics independent of HITL.)

I will append this to `spec.md`.

---

## Re-check after gaps closed

Once SC-011 and SC-012 are added to `spec.md` and task FT-018b is added to `tasks.md`, this analysis is **PASS**. Proceed to `/speckit-tasks`.

## Inconsistencies found and resolved during analysis

| Where | Issue | Resolution |
|---|---|---|
| `spec.md` SC list | SC numbering was sequential; new SC-011/SC-012 will continue the sequence | Append, do not renumber |
| `plan.md` task track list | Item 12 says "Procedure loader stub" with no test; analysis adds FT-018b | tasks.md will reflect |
| Contracts/ag-ui-events.md | "Events not emitted" list named `MessagesSnapshot` — but the slow-client resync per research.md R-2 sends `StateSnapshot + MessagesSnapshot`. **Conflict.** | **Fix research.md R-2** to remove the MessagesSnapshot mention (foundation does not implement messages history); resync is `StateSnapshot` only. Or alternatively, add `MessagesSnapshot` to the contracts list. **Decision: drop MessagesSnapshot from R-2 — foundation has no chat-message history yet.** |
| `data-model.md` `Procedure.trigger` field | Said "front-matter declared (foundation: free-form string)"; loader test (FT-018b) expects to read it | Acceptable for foundation; no fix needed |

Applying the fixes inline now.

---

# Re-analysis — amendment 0004 (2026-07-21): agent functions are tools and skills

Cross-artifact consistency check re-run over the amended spec 001 artifacts.

## Constitution alignment (v1.2.0)

| Principle | Artifact evidence | Status |
|---|---|---|
| I. Loan-is-the-actor | Tool invocation internal-only (`loan-actor-api.md` normative note; clarify Q8) — no external orchestration seam | ✅ |
| III. Deterministic-first | Foundation tool set is deterministic-only; SC-009 grep extended to `lib/loan_actor/tools/`; first LLM tool arrives in 0003 behind the gate | ✅ |
| IV. Immutable diary | Tool pairs (`:tool_invoked` → terminal) are ordinary chained entries; `Entry.new/1` already accepts the new type atoms (no code change to merged diary track) | ✅ |
| V. Taxonomic tests | Taxonomy summary table extended (FT-041..045 rows); tool/skill categories in `test-coverage.md` | ✅ |
| VI. Procedures are content | Skill packs ARE the procedure mechanism; registry holds zero routing logic (pinned in `tool-behaviour.md` invariant 6) | ✅ |
| VIII. Tools and skills (new) | FR-016/017/018 + SC-012(rew)/013/014 + two new contract docs + FT-041..045 | ✅ |

## Consistency findings

| Where | Issue | Resolution |
|---|---|---|
| `tasks.md` FT-019 | Dep said "FT-024 (AG-UI encoder)" — encoder is FT-023 | Fixed in the amended task text |
| `spec.md` SC-012 vs FR-018 | Old SC-012 pinned `CustomEvent name="document_request"`; conflicted with all-tools-stream rule | SC-012 rewritten onto the `request_document` ToolCall sequence |
| PII invariant vs `ToolCallArgs` | Cleartext args would reach the browser | PIIGuard-before-hash-and-emission rule encoded in FR-016, `tool-behaviour.md` invariant 3, Principle VIII checklist |
| Reactive pipeline double-logging risk | If ingestion were a tool call, every event produces two diary pairs | Clarify Q11: reactive pipeline is NOT a tool call |
| `definition-of-done.md` / constitution closeout | Referenced `priv/procedures/…` | Both updated to `priv/skills/…` |
| Old FT-018b | Single-file procedure loader superseded before being built | Marked SUPERSEDED by FT-044; Gap-1's reload test inherited by FT-044 |

## Verdict

**PASS.** No unresolved conflicts between spec.md, plan.md, data-model.md, contracts/, tasks.md, checklists, and constitution v1.2.0. Implementation may resume at FT-041 (Batch A parallel-eligible) per the amended dependency graph.

---

# Re-analysis — amendment 0005 (2026-07-22): reactive pipeline throughput

Cross-artifact consistency check re-run over the amended spec 001 artifacts after intent 0005.

## Constitution alignment (v1.2.0 — unchanged, no version bump)

This amendment does not add or modify a constitutional Principle; it is a performance fix
within already-binding invariants. No `.specify/memory/constitution.md` or `CLAUDE.md` change
accompanies this commit (both stay as of intent 0004) — consistent with intent 0005's own
Constraints section, which names no constitution bump.

| Principle | Artifact evidence | Status |
|---|---|---|
| IV. Immutable diary | `append_with_dedup/4`'s combined-transaction invariant (`diary-store-behaviour.md` invariant 6) strengthens, not weakens, atomicity — a crash mid-write is now provably impossible by construction rather than merely narrow | ✅ |
| V. Taxonomic tests | Track 15 (FT-046..048) taxonomy rows added to `tasks.md`'s coverage summary; `test-coverage.md` gained a "Reactive pipeline throughput" section | ✅ |
| Test-guardian consult | Reviewed the taxonomy plan before implementation (see `clarifications.md` Q17 context); corrected one mis-scoped checklist item (atomicity test, not a nonexistent "orphaned reservation" simulation) and clarified that FT-046's race test replaces rather than duplicates FT-015's | ✅ |
| Test-data-forge consult | Confirmed existing `Factory` helpers (`chain/2`/`next_entry/2` for nil-tail vs real-tail, the existing forged-`prev_hash` pattern) fully cover the new test cases — no new factory needed | ✅ |

## Consistency findings

| Where | Issue | Resolution |
|---|---|---|
| `spec.md` FR-019 vs `clarifications.md` Q17 | FR-019 deliberately states an outcome ("MUST hold NFR-001... without weakening FR-004/FR-005") rather than prescribing the transaction shape, since the mechanism was still open when the FR was drafted | Resolved by Q17 before `plan.md`'s design section was written; no conflict — FR-019's wording was written to accommodate whichever answer Q17 gave |
| `clarifications.md` Q6/Q13 vs Q17 | Q6/Q13 are frozen per intent 0001/FT-017 precedent (once Specified, don't edit) | Addendum notes added to both (not edits to their resolved content) forward-referencing Q17; Q17 itself supersedes their transaction-shape consequence while leaving the composite-key/`{:duplicate, sequence}` decisions those Qs made untouched |
| `tasks.md` FT-046 dependency on FT-015 | FT-015 (`Idempotency.check_and_record/3`) is partially retired by FT-047, one task later | Correct as written — FT-046 builds the new `DiaryStore` callback against the existing FT-015 substrate; FT-047 (not FT-046) is where `Idempotency`'s public API actually changes. No forward-reference to unbuilt work. |
| `research.md` R-1 vs as-built system | R-1's original "one transaction per event" adopted answer was never fully realized (loan_state table never used; idempotency added two more transactions later without revisiting R-1) | Addendum added to R-1 documenting both divergences; 0005 restores R-1's original throughput intent rather than contradicting it |
| `contracts/diary-store-behaviour.md` new callback vs `NFR-005` | Adding a callback that behaves differently per implementation (Mnesia collapses transactions, File does not) could be read as violating "switching requires zero changes outside the implementation module" | No violation: `NFR-005`'s invariant is about the **external contract** staying identical across implementations (same call, same return shape), not about internal implementation cost being identical — both implementations satisfy `{:fresh, ...} | {:duplicate, ...}` identically; `Server` code needs zero changes to switch backends |
| `checklists/test-coverage.md` "no orphaned reservation" item (first draft) | Assumed a reservation step the collapsed design no longer has — caught during the test-guardian consult, before implementation started | Reworded to test transaction atomicity (forced abort leaves no trace in either table) instead |
| `checklists/test-data-quality.md` | Not touched by this amendment | Correct — no new entities/structs are introduced, so no factory-inventory update is due |

## Verdict

**PASS.** No unresolved conflicts between `spec.md`, `plan.md`, `data-model.md`, `contracts/`, `clarifications.md`, `research.md`, `tasks.md`, checklists, and constitution v1.2.0 (unchanged). Implementation may proceed at FT-046 per the amended dependency graph. `FT-048`'s re-run of `FT-035`'s load test is the acceptance gate for closing this amendment — a failing re-run does not block landing FT-046/047 as correctness improvements, but does block treating `NFR-001` as satisfied and block this intent's closeout (`audit(0005)`).
