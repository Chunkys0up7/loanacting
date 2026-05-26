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
