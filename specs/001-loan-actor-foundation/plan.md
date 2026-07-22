# Implementation Plan: Loan-Actor Foundation

**Branch**: `001-loan-actor-foundation`
**Date**: 2026-05-26
**Spec**: [`spec.md`](spec.md)
**Clarifications**: [`clarifications.md`](clarifications.md)
**Constitution**: [`v1.2.0`](../../.specify/memory/constitution.md)
**Amended**: 2026-07-21 by intent 0004 — agent functions are tools + skills (structure tree, Principle VIII row, tracks 12/14, FT-041..045).
**Amended**: 2026-07-22 by intent 0005 — reactive pipeline throughput (`append_with_dedup/4`, track 15, FT-046..048; see "Reactive pipeline throughput design" below).

## Summary

Foundation establishes the loan as a long-running supervised process on the BEAM. A single Elixir umbrella project hosts (a) `loan_actor` — the OTP application implementing per-loan supervised GenServers, the three-loop harness, the immutable diary store, and the AG-UI SSE endpoint — and (b) `web` — a Vite + React + TypeScript SPA using CopilotKit to render a live single-loan view with diary feed and HITL controls. No LLM calls, no business-domain capabilities, no real auth. Everything is exercised by a taxonomic test suite (happy/boundary/error/race/replay/security) including property-based state-machine tests, load tests asserting NFR budgets, and chain-link tamper detection.

## Technical Context

**Language/Version**: Elixir 1.16+ on Erlang/OTP 26+ (backend); TypeScript 5+ on Node 20+ (frontend)

**Primary Dependencies**:
- Backend: `:bandit` (HTTP), `:plug`, `:jason` (JSON), `:stream_data` (property-based testing), `:dialyxir` (static analysis), `:credo` (linting + custom checks), `:mnesia` (bundled with OTP), `:telemetry` (metrics).
- Frontend: `@copilotkit/react-core`, `@copilotkit/react-ui`, `react`, `vite`, `typescript`, `vitest`, `@playwright/test`.

**Storage**: Mnesia (primary, `disc_copies`, ordered_set); flat-file JSONL (alternative `DiaryStore` impl, used in tests).

**Testing**:
- Backend: ExUnit + StreamData (property-based) + a load-test module using `Benchee` for NFR assertions.
- Frontend: Vitest for units, Playwright for end-to-end against a running BEAM node.
- Cross-stack contract test: TypeScript consumer of the AG-UI SSE endpoint.

**Target Platform**: Linux/macOS/Windows dev. Production target deferred (single-node only in foundation).

**Project Type**: Mix umbrella (`apps/loan_actor/` + `apps/web/`).

**Performance Goals**: 100 concurrent loan actors × 10 events/sec/loan; p95 event-to-diary < 100 ms; AG-UI delivery p95 < 250 ms.

**Constraints**: Resident memory < 256 MB at the above load profile; crash recovery < 1 s; replay of 1M-entry diary < 30 s; zero LLM calls.

**Scale/Scope**: Single-node foundation. ~12 modules in `loan_actor`, ~8 components in `web`. ~3,000 LOC total estimate.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Evidence in this plan |
|---|---|---|
| I. Loan-is-the-actor | ✅ | `LoanActor.Supervisor` + `LoanActor.Server` per loan; no central orchestrator. |
| II. Three-loop harness | ✅ | Reactive (`handle_call`/`handle_cast`), periodic (`handle_info(:heartbeat, …)`), planning (self-sent `:plan` message). Credo check enforces tagging. |
| III. Deterministic-first | ✅ | Foundation contains zero LLM calls. SC-009 grep test enforces. |
| IV. Immutable diary | ✅ | `DiaryStore` behaviour; chain-linked entries; atomic write with state mutation; tamper-detection test (SC-006). |
| V. Test-first, taxonomic coverage | ✅ | Test taxonomy mapped in tasks.md; property-based tests via StreamData; load tests assert NFRs. |
| VI. Operating procedures are content | ⚠ | Foundation includes one demo **skill pack** to prove the load → trigger → tool path (0004). Real skill semantics are a later intent (0003) — but the loader interface MUST be present. Tracked as FT-044. |
| VIII. Agent functions are tools and skills (0004) | ✅ | `LoanActor.Tool` behaviour + config-driven registry (FT-041/042); 7 deterministic foundation tools (FT-043); skill packs + loader (FT-044); every invocation diary-logged and streamed as ToolCall events (FT-023); PIIGuard before hashing AND emission; reactive pipeline explicitly non-tool (clarify Q11). |
| VII. Portable identity & artifacts | ✅ | `loan_id` is UUIDv7; spec/clarifications/plan/tasks/checklist artifacts all committed. |
| Architectural invariants | ✅ | Runtime: BEAM. UI: CopilotKit + AG-UI. PII out of diary. NFR budgets in NFR section. |
| Anti-vibe clauses | ✅ | No stubs without a corresponding intent (only the demo skill pack, justified above). Examples in docs are test files. |

**Re-check at end of Phase 1**: deferred until `data-model.md` + `quickstart.md` complete.

## Project Structure

### Documentation (this feature)

```text
specs/001-loan-actor-foundation/
├── spec.md
├── clarifications.md
├── plan.md             ← this file
├── research.md         ← Phase 0 output
├── data-model.md       ← Phase 1 output
├── quickstart.md       ← Phase 1 output
├── contracts/
│   ├── ag-ui-events.md           # AG-UI event types we emit + payload shapes
│   ├── loan-actor-api.md         # Public Elixir API of LoanActor.Server
│   ├── diary-store-behaviour.md  # The DiaryStore behaviour spec
│   └── http-endpoints.md         # HTTP routes + request/response contracts
├── tasks.md            ← Phase 2 output (/speckit-tasks)
└── checklists/
    └── (filled by /speckit-checklist)
```

### Source Code (repository root)

```text
apps/
├── loan_actor/
│   ├── lib/
│   │   ├── loan_actor.ex                      # OTP application entrypoint
│   │   ├── loan_actor/
│   │   │   ├── application.ex                 # Supervisor tree root
│   │   │   ├── supervisor.ex                  # DynamicSupervisor of loan servers
│   │   │   ├── server.ex                      # The GenServer (three-loop harness)
│   │   │   ├── state.ex                       # %LoanActor.State{} struct + transition/2
│   │   │   ├── goal.ex                        # %LoanActor.Goal{} struct
│   │   │   ├── event.ex                       # %LoanActor.Event{} struct
│   │   │   ├── registry.ex                    # via-tuple registry for loan pids
│   │   │   ├── diary/
│   │   │   │   ├── store.ex                   # @behaviour DiaryStore
│   │   │   │   ├── mnesia.ex                  # Primary impl
│   │   │   │   ├── file.ex                    # Alternative impl
│   │   │   │   ├── entry.ex                   # %DiaryEntry{} struct
│   │   │   │   └── chain.ex                   # prev_hash + verify
│   │   │   ├── ag_ui/
│   │   │   │   ├── encoder.ex                 # Elixir → AG-UI JSON (15 event types incl. ToolCall*)
│   │   │   │   ├── stream.ex                  # SSE stream supervisor
│   │   │   │   └── subscriber.ex              # Per-client subscription
│   │   │   ├── tool.ex                        # @behaviour LoanActor.Tool (0004)
│   │   │   ├── tool/
│   │   │   │   ├── spec.ex                    # %Tool.Spec{} + validate_args/2 (schema subset)
│   │   │   │   ├── context.ex                 # %Tool.Context{}
│   │   │   │   └── registry.ex                # config-driven; zero routing logic
│   │   │   ├── tools/                         # 7 deterministic foundation tools (0004)
│   │   │   │   ├── set_goal.ex … verify_diary_chain.ex
│   │   │   ├── skill.ex                       # %Skill{} (0004)
│   │   │   ├── skill/
│   │   │   │   └── loader.ex                  # pack loading, trigger match, reload
│   │   │   ├── hitl.ex                        # Interrupt request/response (via request_operator_approval tool)
│   │   │   └── pii_guard.ex                   # Asserts events + tool args contain no PII
│   │   ├── web/                               # Plug router (HTTP layer)
│   │   │   ├── endpoint.ex                    # Bandit + Plug
│   │   │   ├── router.ex                      # /loans, /loans/:id/events, /loans/:id/ag-ui
│   │   │   └── operator_plug.ex               # Reads x-operator-id header
│   │   └── credo/
│   │       └── checks/                        # Custom Credo checks (loop tagging, no-LLM)
│   ├── test/
│   │   ├── loan_actor_test.exs                # Unit
│   │   ├── server_test.exs                    # Unit
│   │   ├── server_property_test.exs           # Property-based (StreamData)
│   │   ├── diary/
│   │   │   ├── mnesia_test.exs                # Integration (real Mnesia)
│   │   │   ├── file_test.exs                  # Integration
│   │   │   └── chain_test.exs                 # Tamper detection
│   │   ├── ag_ui/
│   │   │   └── encoder_test.exs               # 17-event coverage
│   │   ├── replay_test.exs                    # Diary replay = same state
│   │   ├── idempotency_test.exs               # (event_id, source) dedup
│   │   ├── hitl_test.exs                      # Interrupt + response
│   │   ├── pii_guard_test.exs                 # Regex-based PII rejection
│   │   ├── llm_absence_test.exs               # Grep assertion (SC-009)
│   │   ├── load/
│   │   │   └── nfr_load_test.exs              # 100 loans × 10 ev/s × 60 s
│   │   └── support/
│   │       ├── factory.ex                     # Event + Loan factories (test-data-forge discipline)
│   │       └── data_case.ex                   # Shared test setup
│   └── mix.exs
├── web/
│   ├── src/
│   │   ├── main.tsx
│   │   ├── App.tsx
│   │   ├── pages/
│   │   │   └── LoanView.tsx                   # The single-loan UI
│   │   ├── components/
│   │   │   ├── DiaryFeed.tsx
│   │   │   ├── StateCard.tsx
│   │   │   ├── EventSender.tsx
│   │   │   └── HitlInterruptCard.tsx
│   │   ├── lib/
│   │   │   ├── ag-ui-client.ts                # Direct AG-UI SSE consumer (typed)
│   │   │   └── copilotkit-bindings.ts         # useCoAgent / useCoAgentStateRender wiring
│   │   └── types.ts                           # Mirror of contracts/ag-ui-events.md
│   ├── test/
│   │   ├── ag-ui-client.test.ts               # Vitest, contract test
│   │   └── e2e/
│   │       ├── spawn-and-event.spec.ts        # Playwright, against running backend
│   │       └── hitl.spec.ts
│   ├── package.json
│   └── vite.config.ts
├── mix.exs                                    # Umbrella
├── config/
│   ├── config.exs
│   ├── dev.exs
│   └── test.exs
├── .formatter.exs
├── .credo.exs
└── README.md
```

### Skill bindings

- **`speckit` skill** drives the workflow this plan was produced by.
- **`copilotkit` skill** is the canonical reference for `apps/web/` and the AG-UI encoder in `apps/loan_actor/lib/loan_actor/ag_ui/`.
- **`test-guardian` skill** drives the test taxonomy and antipattern checks listed in tasks.
- **`test-data-forge` skill** drives the design of `apps/loan_actor/test/support/factory.ex`.

## Phase 0 — Research (output: `research.md`)

The clarifications resolved Q1–Q7. Remaining research questions, tracked in `research.md`:

- R-1: Mnesia transaction granularity vs. per-loan throughput (validates NFR-001).
- R-2: AG-UI SSE backpressure handling in Bandit; recommended chunk size.
- R-3: StreamData generators for the loan state machine — model the state diagram exactly.
- R-4: Chain-link hash function (BLAKE2b vs SHA-256) — pick the cheaper one that meets tamper-detection needs.
- R-5: How Mnesia interacts with property-based tests under `async: true` — required isolation pattern.

## Phase 1 — Design (output: `data-model.md`, `quickstart.md`, `contracts/`)

- **`data-model.md`** — full entity definitions (`Loan`, `DiaryEntry`, `Event`, `Goal`, `HITLRequest`, `HITLResponse`, `Tool.Spec`, `Skill`) and the state-machine diagram.
- **`quickstart.md`** — the developer onboarding path: `mix deps.get`, `mix test`, `mix run` to start the BEAM node, `npm run dev` in `apps/web`, open `http://localhost:5173/loans/L-DEMO`.
- **`contracts/`** — four contract documents listed in the project structure. These are referenced by both backend unit tests and frontend contract tests. Drift between contract docs and code is a CI failure.

## Phase 2 — Tasks (output: `tasks.md`, NOT produced by `/speckit-plan`)

Tasks will be sequenced under these tracks (ordering enforced by dependencies declared in `tasks.md`):

1. **Foundation skeleton** — umbrella, mix.exs, credo, dialyzer, CI scaffold.
2. **Diary store + chain** — behaviour, Mnesia impl, File impl, tamper detection.
3. **State + transition gate** — `LoanActor.State`, typed structs, Credo check.
4. **Server + three-loop harness** — GenServer with reactive/periodic/planning.
5. **Idempotency + PII guard** — composite-key dedup, PII regex test corpus.
6. **AG-UI encoder + SSE stream** — full 17-event encoder + Bandit endpoint.
7. **HTTP API** — Plug router, operator-id plug.
8. **Frontend SPA** — Vite + React + CopilotKit + AG-UI client.
9. **HITL mechanism** — backend interrupt event, frontend `useHumanInTheLoop`.
10. **Property-based + replay tests** — StreamData suites.
11. **Load test asserting NFR budgets** — Benchee + scripted load.
12. **Skill loader + demo pack** *(0004; replaces "procedure loader stub")* — pack loading, trigger matching, reload, load-time tools_required validation.
13. **CI wiring** — `mix test`, `mix dialyzer`, `mix credo --strict`, `npm test`, Playwright, load test.
14. **Tool layer** *(0004)* — `LoanActor.Tool` behaviour, registry, 7 deterministic foundation tools, shared tool contract suite (FT-041..043, before the Server track).
15. **Reactive pipeline throughput** *(0005)* — `DiaryStore.append_with_dedup/4` (behaviour + both implementations), `Server` reactive-path refactor onto it, `FT-035` load-test re-run as acceptance gate (FT-046..048).

## Reactive pipeline throughput design *(0005)*

`FT-035`'s load test found `NFR-001` does not hold at full `SC-001` scale — see
`clarifications.md` Q17 for the full option analysis. The adopted design:

- **New behaviour callback**: `DiaryStore.append_with_dedup(loan_id, event_id, source,
  entry_builder)`, `entry_builder :: (tail :: entry | nil -> entry)`. Returns `{:fresh,
  sequence, entry}` or `{:duplicate, sequence}`.
- **`Diary.Mnesia`**: `:mnesia.dirty_read/2` peek on `loan_idem` first (near-zero cost, safe
  because a single loan's events are only ever handled by that loan's one serialized
  `Server` process — no concurrent writer can race this key). On a miss, one
  `:mnesia.transaction/1` re-checks the key, reads the `loan_diary` tail, calls
  `entry_builder.(tail)`, verifies chain linkage (`Chain.verify_append/2`, unchanged), writes
  the diary entry, and writes `{received_at, sequence}` to `loan_idem` — one transaction,
  down from three.
- **`Diary.File`**: keeps the pre-0005 two-call internal shape (idempotency check against
  Mnesia's `loan_idem`, then a File append) — there is no Mnesia transaction on this path to
  fold into, and `File` is test-only (`NFR-001` is measured against Mnesia specifically).
  Same external `{:fresh, ...} | {:duplicate, ...}` contract either way — `NFR-005`'s
  "switching requires zero changes outside the implementation module" holds.
- **`Server`**: `handle_clean_event/3` no longer calls `Idempotency.check_and_record/3`
  directly. `apply_event/3` computes the `State.transition/2` attempt first (pure, unchanged
  — including the `IllegalTransitionError` rescue path; its result is discarded, harmlessly,
  on the eventual `:duplicate` branch), builds an `entry_builder` closure from whichever
  entry type/payload resulted, and calls `store.append_with_dedup/4` once.
  **Correction found during implementation** (see `clarifications.md`'s addendum to Q17):
  `Idempotency.check_and_record/3` + `record_sequence/4` are **not** retired — `Diary.File`
  still needs them (no Mnesia transaction of its own to fold into); they just gain a new
  caller (`Diary.File`, not `Server`). `Idempotency` additionally gains `txn_check/3` +
  `txn_record/4`, transaction-scoped siblings consumed only from `Diary.Mnesia`'s combined
  transaction.
- **Acceptance gate**: `FT-035`'s existing load test, re-run unmodified at its default scale
  (SC-015). No new load-test file — the fix is proven against the same measurement that
  found the gap.

## Phase 3 — Implement

Driven by `tasks.md`. Tests are committed alongside (or before) the code they exercise. Each task has a PR; each PR's description maps the test-taxonomy categories it touches.

## Risks & mitigations (delta from intent 0001)

| Risk | Mitigation |
|---|---|
| Mnesia bottleneck under load profile | R-1 research + load test SC-001 as early-warning. Fallback: switch to LMDB-style append-only file with index. |
| Bandit SSE backpressure for slow clients | R-2 research. Drop-and-snapshot semantics — slow client gets `MessagesSnapshot` on resume. |
| Property-based tests cover only the modeled state diagram | Generators are derived from `data-model.md`; drift between code and data-model causes a CI failure. |
| Frontend coupling to AG-UI implementation drift | Cross-stack contract test pins event shapes against `contracts/ag-ui-events.md`. |
| Operator-id stub leaks into production | Production builds set `:require_operator_id` to `true`; the stub-only branch is excluded by `Mix.env() == :prod`. |
| Umbrella complexity for a small team | Documented in quickstart; revisit if the umbrella becomes a hindrance — splitting to two repos is a later intent, not an emergency. |
| Collapsing transactions (0005) doesn't fully close the NFR-001 gap | `FT-035`'s re-run (SC-015) is the hard gate; if it doesn't clear, escalate to Q17's deferred Q3 (batching) or Q4 (further Mnesia tuning) as a follow-up amendment rather than declaring the fix done. |

## Re-check after Phase 1

*To be filled by `/speckit-analyze` after `data-model.md` + `quickstart.md` exist.*
