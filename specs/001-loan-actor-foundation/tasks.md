# Tasks — Loan-Actor Foundation

Derived from [`spec.md`](spec.md), [`plan.md`](plan.md), [`data-model.md`](data-model.md), [`research.md`](research.md), [`contracts/`](contracts/), and [`analysis.md`](analysis.md).

Conventions:
- `FT-NNN` = Foundation Task NNN.
- `[P]` = parallelizable with same-numbered other `[P]` tasks (no ordering dep).
- Every task lists: deliverable artifacts, applicable test-taxonomy categories, dependency tasks.
- Tests are committed in the **same** PR as code. Tasks of type `test` are about test infrastructure or pure test suites; production tasks include their own tests.

## Status ledger

Updated by `/speckit-implement` as each task lands. Absent = not started.

| Task | Status | Commit |
|---|---|---|
| FT-001 | DONE | `7532190` (bootstrap scaffold) |
| FT-002 | DONE | `7532190` (bootstrap scaffold) |
| FT-003 | DONE | `FT-003` commit |
| FT-004 | DONE | `FT-004` commit |
| FT-005 | DONE | `2af785a` |
| FT-006 | DONE | `FT-006` commit (incl. factory seed of FT-037 + shared store suite) |
| FT-007 | DONE | `FT-007` commit |
| FT-008 | DONE | `FT-008` commit |
| FT-018b | SUPERSEDED | by FT-044 (intent 0004) |
| FT-041 | DONE | `FT-041` commit |
| FT-042 | DONE | `FT-042` commit |
| FT-010 | DONE | `FT-010` commit |
| FT-011 | DONE | `FT-011` commit |
| FT-012 | DONE | `FT-012` commit |
| FT-013 | DONE | `FT-013` commit |
| FT-014 | DONE | `FT-014` commit |
| FT-015 | DONE | `FT-015` commit |
| FT-009 | DONE | `FT-009` commit |
| FT-016 | DONE | `FT-016` commit |
| FT-017 | DONE | `FT-017` commit |
| FT-043 | DONE | `FT-043` commit |
| FT-044 | DONE | `FT-044` commit |
| FT-018 | DONE | `FT-018` commit |
| FT-020 | DONE | `FT-020` commit |
| FT-021 | DONE | this commit |
| FT-022 | DONE | `FT-021/FT-022` commit |
| FT-023 | DONE | `FT-023` commit |
| FT-019 | DONE | `FT-019` commit |
| FT-024 | DONE | `FT-024` commit |
| FT-025 | DONE | `FT-025` commit |
| FT-026 | DONE | `FT-026/FT-027` commit |
| FT-027 | DONE | `FT-026/FT-027` commit (HITL route added retroactively by FT-028) |
| FT-028 | DONE | `FT-028` commit |
| FT-034 | DONE | `FT-034` commit |
| FT-035 | DONE (SC-001 gap found and documented — see commit) | this commit |
| FT-046 | REVERTED (regression — see `clarifications.md` Q17 Addendum 2) | implemented `4e688f6`, reverted `cca65b0` |
| FT-047 | REVERTED (depended on FT-046) | implemented `480226d`, reverted `9fdf498` |
| FT-048 | DONE — gap NOT closed (NFR-001 still fails; regression found instead) | `FT-048` commit |
| FT-029 | DONE | `107e4bc` |
| FT-030 | DONE | `130407c` |
| FT-031 | DONE | `130407c` |
| FT-032 | DONE | `e61f339` (+ `9eddc19` inspector fix) |
| FT-045 | DONE | `d6f51ae` |
| FT-033 | DONE | `95b6fa0` |
| FT-036 | DONE (switched File → Mnesia after measuring — see commit) | this commit |

*(Task list amended 2026-07-21 by intent 0004: FT-041..FT-045 added; FT-017/018/019/023/028/030/031/032/034/035/037/038 deltas; FT-019 dep corrected FT-024 → FT-023.)*

*(Task list amended 2026-07-22 by intent 0005: FT-046..FT-048 added (Track 15, reactive pipeline throughput). FT-046/FT-047 were implemented, then REVERTED after FT-048's load-test re-run showed the fix is a regression, not an improvement — see `clarifications.md` Q17 Addendum 2 for the full evidence. NFR-001 remains unmet; intent 0005 stays `Specified`, not `Implemented`.)*

---

## Track 1 — Foundation skeleton

### FT-001 — Initialize umbrella project
- Deliverable: `mix.exs` (umbrella), `apps/loan_actor/mix.exs`, `apps/web/package.json`, `config/{config,dev,test}.exs`, `.formatter.exs`, `README.md` pointing at quickstart.
- Taxonomy: n/a.
- Depends on: none.

### FT-002 — Pin Elixir/OTP via `.tool-versions`; add `dialyxir` + `credo` + `stream_data` + `bandit` + `plug` + `jason` + `uniq` + `benchee`
- Deliverable: `apps/loan_actor/mix.exs` deps; `.tool-versions` at repo root.
- Taxonomy: n/a.
- Depends on: FT-001.

### FT-003 [P] — Custom Credo checks scaffold
- Deliverable: `apps/loan_actor/lib/credo/checks/` directory; empty placeholders for `LoopTagging`, `NoLLM`, `NoDirectStateMutation`. `.credo.exs` registers them.
- Taxonomy: n/a.
- Depends on: FT-002.

### FT-004 [P] — CI workflow
- Deliverable: `.github/workflows/ci.yml` running `mix test`, `mix dialyzer`, `mix credo --strict`, `mix test.load`, `npm test`, Playwright (against booted backend).
- Taxonomy: n/a.
- Depends on: FT-002.

---

## Track 2 — Diary

### FT-005 — `LoanActor.Diary.Entry` struct + `Chain` helpers (BLAKE2b-256, prev_hash compute, verify)
- Deliverable: `lib/loan_actor/diary/entry.ex`, `lib/loan_actor/diary/chain.ex`.
- Tests: `test/diary/entry_test.exs`, `test/diary/chain_test.exs` — happy, boundary (zero prev_hash for entry 0), error (malformed entry), security (tampering detection).
- Taxonomy: happy / boundary / error / security.
- Depends on: FT-002.

### FT-006 — `DiaryStore` behaviour
- Deliverable: `lib/loan_actor/diary/store.ex` matching [`contracts/diary-store-behaviour.md`](contracts/diary-store-behaviour.md).
- Tests: `test/diary/shared_behaviour_test.exs` (parameterized; runs against each implementation).
- Taxonomy: contract.
- Depends on: FT-005.

### FT-007 — `LoanActor.Diary.File` implementation
- Deliverable: `lib/loan_actor/diary/file.ex` (JSONL per loan, fsync per append).
- Tests: `test/diary/file_test.exs` (happy, replay, tamper, large diary 100k entries).
- Taxonomy: happy / replay / security / boundary.
- Depends on: FT-006.

### FT-008 — `LoanActor.Diary.Mnesia` implementation
- Deliverable: `lib/loan_actor/diary/mnesia.ex`; `mix loan_actor.init_mnesia` task.
- Tests: `test/diary/mnesia_test.exs` (happy, replay, tamper, concurrent write race).
- Taxonomy: happy / replay / security / race.
- Depends on: FT-006.

### FT-009 — Replay test (cross-cutting)
- Deliverable: `test/replay_test.exs` proving diary replay yields byte-identical state for every state-mutating handler.
- Taxonomy: replay.
- Depends on: FT-007, FT-008, FT-014.

---

## Track 3 — State + transition gate

### FT-010 — `LoanActor.State` struct + `Goal` + status enum
- Deliverable: `lib/loan_actor/state.ex`, `lib/loan_actor/goal.ex`.
- Tests: `test/state_test.exs` covering all status enum values.
- Taxonomy: happy / boundary.
- Depends on: FT-002.

### FT-011 — `LoanActor.State.transition/2` + state-machine model
- Deliverable: `transition/2` enforces the diagram in `data-model.md`; `LoanActor.State.Model` exposes `next_events_for/1` for property tests; illegal transitions raise.
- Tests: `test/state_transition_test.exs` (happy = all legal edges; error = all illegal pairs).
- Taxonomy: happy / error.
- Depends on: FT-010.

### FT-012 — Credo check `LoanActor.Credo.NoDirectStateMutation`
- Deliverable: AST walker rejecting `%LoanActor.State{...} | ...` outside `transition/2`.
- Tests: `test/credo/no_direct_state_mutation_test.exs`.
- Taxonomy: happy / error.
- Depends on: FT-003, FT-010.

---

## Track 4 — Event + Idempotency + PII Guard

### FT-013 — `LoanActor.Event` struct + validation
- Deliverable: `lib/loan_actor/event.ex` with `validate/1` enforcing required fields and source enum.
- Tests: `test/event_test.exs` (happy + boundary on each field; error on bad enum).
- Taxonomy: happy / boundary / error.
- Depends on: FT-002.

### FT-014 — `PIIGuard` module + `priv/pii_patterns.yml`
- Deliverable: `lib/loan_actor/pii_guard.ex`, `priv/pii_patterns.yml` (SSN, account, routing, DOB patterns), `apply/1` returning `{:ok, stripped_payload, redacted_paths}` or `{:error, :pii_violation, paths}`.
- Tests: `test/pii_guard_test.exs` with 200-case synthetic corpus.
- Taxonomy: happy / error / security.
- Depends on: FT-013.

### FT-015 — Idempotency table (`loan_idem`) + check function
- Deliverable: Mnesia table init in `Diary.Mnesia.init/1`; `LoanActor.Idempotency.check_and_record/3` returning `:fresh` or `:duplicate`.
- Tests: `test/idempotency_test.exs` (happy fresh, happy duplicate, race two-writers).
- Taxonomy: happy / race / replay.
- Depends on: FT-008, FT-013.

---

## Track 5 — Server + three-loop harness

### FT-016 — `LoanActor.Supervisor` (DynamicSupervisor) + `LoanActor.Registry`
- Deliverable: `lib/loan_actor/supervisor.ex`, `lib/loan_actor/registry.ex` (via-tuple).
- Tests: `test/supervisor_test.exs` (spawn, lookup, restart on crash).
- Taxonomy: happy / error.
- Depends on: FT-002.

### FT-017 — `LoanActor.Server` reactive loop (`handle_call :send_event`)
- Deliverable: `lib/loan_actor/server.ex` with `handle_call/3` for `:send_event`. PIIGuard → idempotency → transition → diary append, atomic.
- Tests: `test/server_reactive_test.exs` (each step on its own + integration).
- Taxonomy: happy / error / boundary.
- Depends on: FT-008, FT-011, FT-014, FT-015, FT-016.

### FT-018 — Server periodic loop (heartbeat) *(amended by 0004)*
- Deliverable: `handle_info(:heartbeat, _)`. Configurable interval (config: `:heartbeat_ms`, default 60_000; test override). The pass trigger-matches skills and self-initiated actions go through tools (`set_goal`, `verify_diary_chain`).
- Tests: `test/server_heartbeat_test.exs` — verifies SC-011 cadence.
- Taxonomy: happy / boundary.
- Depends on: FT-017, FT-043, FT-044.

### FT-018b — ~~Procedure loader runtime test~~ **SUPERSEDED by FT-044** (intent 0004)
- The single-file procedure loader was never built; skill packs + `Skill.Loader` (FT-044) replace it, including the analysis Gap-1 runtime-reload test.

### FT-019 — Server planning loop (`:plan` self-message) *(amended by 0004)*
- Deliverable: `handle_info(:plan, _)`. When goals are set, the planning loop trigger-matches skills and invokes the `request_document` **tool** — producing the diary pair + full ToolCall sequence per SC-012 (rewritten).
- Tests: `test/server_planning_test.exs` — verifies SC-012; race test: planning-loop tool invocation vs inbound reactive event.
- Taxonomy: happy / race.
- Depends on: FT-017, FT-023 (AG-UI encoder — dep id corrected by 0004; was mislabeled FT-024), FT-043, FT-044.

### FT-020 — Credo check `LoanActor.Credo.LoopTagging`
- Deliverable: Enforces every `handle_*` clause carries a `# loop: reactive|periodic|planning` comment.
- Tests: `test/credo/loop_tagging_test.exs`.
- Taxonomy: happy / error.
- Depends on: FT-003.

### FT-021 — Credo check `LoanActor.Credo.NoLLM`
- Deliverable: Rejects imports/uses of `OpenAI`, `Anthropic`, `Bumblebee.Text.completion`, fetch URLs matching LLM-provider regex, in production paths.
- Tests: `test/credo/no_llm_test.exs`.
- Taxonomy: happy / error / security (prevents accidental LLM dep).
- Depends on: FT-003.

### FT-022 — LLM absence grep test
- Deliverable: `test/llm_absence_test.exs` greps `apps/loan_actor/lib/` for forbidden tokens.
- Taxonomy: security.
- Depends on: FT-001.

---

## Track 6 — AG-UI encoder + SSE stream

### FT-023 — `LoanActor.AGUI.Encoder` — **15** emitted event types per `contracts/ag-ui-events.md` *(amended by 0004: + ToolCallStart/Args/End/Result)*
- Deliverable: `lib/loan_actor/ag_ui/encoder.ex` producing canonical JSON per event, including the four ToolCall events (single-frame `ToolCallArgs`, PII-redacted args, deferred-Result HITL semantics).
- Tests: `test/ag_ui/encoder_test.exs` snapshotting each event type (15 snapshots).
- Taxonomy: contract / happy / boundary.
- Depends on: FT-010, FT-005, FT-041.

### FT-024 — `LoanActor.AGUI.Stream` + `Subscriber` (bounded mailbox, slow-client resync per R-2)
- Deliverable: per-subscriber GenServer; bounded queue (128); slow-client resync via fresh `StateSnapshot`.
- Tests: `test/ag_ui/subscriber_test.exs` — happy delivery, slow-consumer resync.
- Taxonomy: happy / race / boundary.
- Depends on: FT-023, FT-016.

### FT-025 — `LoanActor.Server.subscribe/2`
- Deliverable: API per `contracts/loan-actor-api.md`; loan actor broadcasts to subscribers on state change.
- Tests: `test/server_subscribe_test.exs`.
- Taxonomy: happy / race.
- Depends on: FT-017, FT-024.

---

## Track 7 — HTTP API

### FT-026 — `LoanActor.Web.OperatorPlug`
- Deliverable: Reads `x-operator-id` header; assigns `:operator_id`; rejects with 401 in prod when absent.
- Tests: `test/web/operator_plug_test.exs`.
- Taxonomy: happy / error / security.
- Depends on: FT-002.

### FT-027 — `LoanActor.Web.Router` + `Endpoint` per `contracts/http-endpoints.md`
- Deliverable: Bandit + Plug.Router for `POST /loans`, `POST /loans/:id/events`, `POST /loans/:id/hitl/:request_id`, `GET /loans/:id/ag-ui`.
- Tests: `test/web/router_test.exs` per endpoint covering all documented response codes.
- Taxonomy: happy / error / boundary / security.
- Depends on: FT-017, FT-024, FT-026.

---

## Track 8 — HITL

### FT-028 — `LoanActor.HITL` module — request emission + response handling *(amended by 0004: rewired through the `request_operator_approval` tool)*
- Deliverable: `lib/loan_actor/hitl.ex`; the HITL request is emitted by the `request_operator_approval` tool (`{:pending, request_id}`; Server parks `invocation_id ↔ request_id`); still emits `CustomEvent name="hitl_request"`; `respond_hitl/3` completes the deferred `ToolCallResult`; first-response-wins; conflict → `:approval_conflict` diary entry + error-shaped ToolCallResult.
- Tests: `test/hitl_test.exs` — happy (deferred Result observed), conflict (double respond, first wins), error (responding to non-existent request).
- Taxonomy: happy / error / race.
- Depends on: FT-017, FT-023, FT-024, FT-043.

---

## Track 9 — Frontend SPA

### FT-029 — Scaffold `apps/web` (Vite + React + TS + ESLint + Vitest + Playwright)
- Deliverable: `apps/web/{src,test,e2e,package.json,vite.config.ts,tsconfig.json}`.
- Depends on: FT-001.

### FT-030 — `apps/web/src/lib/ag-ui-client.ts` typed SSE consumer
- Deliverable: client implementing the consumer pattern from `.claude/skills/copilotkit/references/ag-ui-protocol.md`; reject unknown event types. *(0004: accepts the four ToolCall events; strict rejection retained; tolerates interleaving between a HITL `ToolCallEnd` and its deferred `ToolCallResult`.)*
- Tests: `apps/web/test/ag-ui-client.test.ts` against a recorded stream + a live backend.
- Taxonomy: happy / error / contract.
- Depends on: FT-023, FT-029.

### FT-031 — `apps/web/src/types.ts` mirror of `contracts/ag-ui-events.md`
- Deliverable: TypeScript types for every emitted event *(0004: 15 types incl. ToolCall discriminated-union members)*.
- Tests: type-only; covered by FT-030 consumer tests.
- Depends on: FT-029.

### FT-032 — `LoanView` page + `StateCard` + `DiaryFeed` + `EventSender` components
- Deliverable: `apps/web/src/pages/LoanView.tsx` and listed components; wired via `useCoAgent` + `useCoAgentStateRender`.
- Tests: Vitest component tests; Playwright e2e `spawn-and-event.spec.ts`.
- Taxonomy: happy / boundary.
- Depends on: FT-030, FT-031, FT-027.

### FT-045 *(new, 0004)* — `ToolCallCard` component
- Deliverable: `apps/web/src/components/ToolCallCard.tsx` — correlates `ToolCallStart/Args/End/Result` by `tool_call_id`; renders pending state until Result (incl. long-lived HITL pending); rendered in `DiaryFeed`/`LoanView`.
- Tests: Vitest (frame correlation, pending → resolved, error-shaped Result); covered e2e by FT-038.
- Taxonomy: happy / boundary / error.
- Depends on: FT-030, FT-031.

### FT-033 — `HitlInterruptCard` via `useHumanInTheLoop`
- Deliverable: `apps/web/src/components/HitlInterruptCard.tsx`.
- Tests: Vitest unit; Playwright `hitl.spec.ts`.
- Taxonomy: happy / error.
- Depends on: FT-028, FT-032.

---

## Track 10 — Property-based + replay + load

### FT-034 — Property-based state-machine tests *(amended by 0004)*
- Deliverable: `test/server_property_test.exs` using StreamData + `LoanActor.State.Model`. 10,000 sequences in CI. Property extended: diaries containing tool-invocation entries replay to identical state; the tool-invocation sequence is replay-stable.
- Tests: itself.
- Taxonomy: happy / boundary / replay.
- Depends on: FT-011, FT-017, FT-009.

### FT-035 — Load test (`mix test.load`) *(amended by 0004)*
- Deliverable: `test/load/nfr_load_test.exs` + Mix alias `test.load`. Asserts NFR-001..NFR-005, SC-001, SC-002 **with tool ceremony on** (diary pairs + 4 SSE frames per invocation) — this is the early-warning gate for intent 0004's hot-path risk.
- Taxonomy: happy + performance (treated as boundary).
- Depends on: FT-017, FT-018, FT-027.

### FT-036 — Diary scale test (1M entries replay < 30s)
- Deliverable: `test/load/large_diary_replay_test.exs`. Tagged `:slow`, run nightly in CI.
- Taxonomy: replay / boundary.
- Depends on: FT-008, FT-009.

---

## Track 11 — Cross-cutting

### FT-037 — Factory module `apps/loan_actor/test/support/factory.ex` *(amended by 0004)*
- Deliverable: Factory pattern per `.claude/skills/test-data-forge/references/factory-patterns.md` for `%Event{}`, `%LoanActor.State{}`, `%Goal{}`, `%HITLRequest{}` + *(0004)* `tool_spec/1`, `skill/1` (+ on-disk pack writer), `tool_invocation_diary_pair/1`. Each factory carries discovery-checklist comment. (Diary.Entry factory landed with FT-006.)
- Depends on: FT-010, FT-013, FT-041.

### FT-038 — Cross-stack contract test (Playwright) *(amended by 0004)*
- Deliverable: `apps/web/test/e2e/contract.spec.ts` — capture live AG-UI stream and diff against backend's snapshot test outputs, **including ToolCall frames and the HITL deferred-Result sequence**.
- Taxonomy: contract.
- Depends on: FT-023, FT-030, FT-032, FT-045.

### FT-039 — Mix tasks: `loan_actor.spawn`, `loan_actor.replay`, `loan_actor.verify_chain`, `loan_actor.dump_diary`
- Deliverable: One `Mix.Task` per quickstart command.
- Tests: each task has a unit test invoking it via `Mix.Task.run/2`.
- Taxonomy: happy / error.
- Depends on: FT-017, FT-008.

### FT-040 — Update `README.md` to point at quickstart; smoke section runs in CI
- Deliverable: `README.md`; CI step `mix test.smoke` mirroring quickstart's "smoke checklist".
- Depends on: FT-027, FT-032.

---

## Track 12 — Tool layer + skills *(added by intent 0004)*

### FT-041 — `LoanActor.Tool` behaviour + `Tool.Spec` + `Tool.Context` + `validate_args/2`
- Deliverable: `lib/loan_actor/tool.ex`, `lib/loan_actor/tool/spec.ex` (JSON-schema **subset** validator: `type`/`properties`/`required`/`enum` — hard cap per `contracts/tool-behaviour.md`), `lib/loan_actor/tool/context.ex`.
- Tests: `test/tool/spec_test.exs` — validator happy + each subset keyword's violation + boundary (empty schema, empty args); behaviour-surface pin vs `contracts/tool-behaviour.md`.
- Taxonomy: happy / boundary / error / contract.
- Depends on: FT-002.

### FT-042 — `LoanActor.Tool.Registry` + shared tool contract suite
- Deliverable: `lib/loan_actor/tool/registry.ex` (config-driven `:loan_actor, :tools` list; `list/0`, `fetch/1`, `invoke/3` with args validation + telemetry; **zero routing logic**); `test/support/tool_shared.ex` parameterized suite (mirrors `diary_store_shared.ex`).
- Tests: `test/tool/registry_test.exs` — unknown tool, invalid args, telemetry, config injection of fixture tools.
- Taxonomy: happy / error / contract.
- Depends on: FT-041.

### FT-043 — Foundation tool set (7 deterministic tools)
- Deliverable: `lib/loan_actor/tools/{set_goal, satisfy_goal, request_document, transition_state, append_note, request_operator_approval, verify_diary_chain}.ex` — each returns **effects** (never mutates state); `request_operator_approval` returns `{:pending, request_id}`.
- Tests: each via the shared tool suite + tool-specific effect tests; determinism (same args+ctx → same result); PII order-of-operations test (synthetic PII arg absent from redacted output).
- Taxonomy: happy / boundary / error / security / replay.
- Depends on: FT-041, FT-042, FT-010, FT-011 (state-effecting tools), FT-014 (PIIGuard).

### FT-044 — `LoanActor.Skill` + `Skill.Loader` + demo pack *(replaces FT-018b)*
- Deliverable: `lib/loan_actor/skill.ex`, `lib/loan_actor/skill/loader.ex` (pack loading from `priv/skills/`, restricted front-matter grammar, load-time `tools_required` validation, `reload/0`, naive trigger match per `contracts/skill-format.md`); demo pack `priv/skills/0001-demo-document-request/` (SKILL.md + one reference file).
- Tests: `test/skill/loader_test.exs` against fixture packs in `test/fixtures/skills/` (valid / bad front-matter / unresolvable tools_required / multi-file); reload picks up an added pack (analysis Gap-1 inherited); non-matching state activates nothing.
- Taxonomy: happy / boundary / error / contract.
- Depends on: FT-041, FT-042.

(FT-045 — `ToolCallCard` — is listed under Track 9 with its frontend siblings.)

---

## Track 15 — Reactive pipeline throughput *(added by intent 0005; FT-046/FT-047 REVERTED after load-test evidence — see `clarifications.md` Q17 Addendum 2. Task descriptions below are left as-authored to document what was attempted and why; they do not describe the current state of the code.)*

### FT-046 — `DiaryStore.append_with_dedup/4` — behaviour + both implementations
- Deliverable: `contracts/diary-store-behaviour.md` amended (new callback, done as part of this spec commit); `lib/loan_actor/diary/store.ex` gains the `@callback`; `lib/loan_actor/diary/mnesia.ex` implements it as a dirty-read peek + one combined `:mnesia.transaction/1` (dedup-check + tail-read + chain-verify + diary write + idem write); `lib/loan_actor/diary/file.ex` implements it by delegating to the pre-0005 separate-calls shape (idempotency is always Mnesia-backed regardless of diary backend).
- Tests: extend `test/support/diary_store_shared.ex` (parameterized, both implementations) with: fresh-then-duplicate; concurrent-duplicate-delivery race (exactly one `:fresh` winner — this test **replaces** `test/idempotency_test.exs`'s existing FT-015 race test outright, it does not run alongside it); duplicate-produces-zero-diary-writes; forced-abort-mid-transaction leaves zero trace in either table (proves atomicity — not a simulation of the old two-phase design's failure mode, which no longer exists); `entry_builder` called with `tail == nil` (genesis) as well as a real tail; chain-link rejection (bad `prev_hash`) still aborts through this path same as plain `append/2`. Optional: a Benchee microbenchmark (single loan, sequential events, no concurrency) comparing transaction count/latency against the pre-0005 shape, for fast iteration ahead of FT-048's full load test.
- Taxonomy: happy / boundary / race / replay / error / contract.
- Depends on: FT-006 (shared store suite), FT-007, FT-008, FT-015.

### FT-047 — `LoanActor.Server` reactive path onto `append_with_dedup/4`; retire two-phase `Idempotency` API
- Deliverable: `lib/loan_actor/server.ex`'s `handle_clean_event/3`/`apply_event/3` call `store.append_with_dedup/4` once per event (builder closure captures the already-computed `State.transition/2` result / `IllegalTransitionError` rescue path, unchanged); `lib/loan_actor/idempotency.ex`'s public `check_and_record/3` + `record_sequence/4` are retired in favor of transaction-scoped helpers consumed only from `Diary.Mnesia` (FT-046).
- Tests: `test/server_reactive_test.exs` updated for the new call shape; `test/idempotency_test.exs` updated to unit-test the transaction-scoped helpers directly (narrow, not a race test — they only ever run inside an already-open transaction, so concurrency correctness is fully covered by FT-046's shared-suite race test, not re-tested here); FT-034's property-based replay suite re-run and must stay green with no changes required (diary entry shapes are unchanged; replay never touches `loan_idem`, so this is a non-regression gate, not coverage of the new logic).
- Taxonomy: happy / replay / error / regression.
- Depends on: FT-046, FT-017.

### FT-048 — Re-run `FT-035` load test as the acceptance gate (SC-015)
- Deliverable: `mix test.load` green at default `LOAN_LOAD_*` scale (100 loans, 10 events/sec/loan, 60 s) — p95 event-to-diary latency < 100 ms; `NFR-002`/`NFR-003`/`NFR-004` unregressed in the same run. `apps/loan_actor/test/load/nfr_load_test.exs`'s moduledoc updated to record the outcome (the "genuine gap" callout from the `FT-035` commit is corrected/closed, referencing intent 0005) — no new load-test file; this is the same test, re-run.
- Tests: none new — the existing load test is the test.
- Taxonomy: performance (treated as boundary, matching FT-035's own precedent).
- Depends on: FT-047.

---

## Dependency graph (high-level, as amended by 0004, 0005)

```
FT-001 ─► FT-002 ─► (most others)
FT-005 ─► FT-006 ─► (FT-007, FT-008)
FT-041 ─► FT-042 ─► (FT-043, FT-044)                 ← tool layer precedes the Server track
FT-008 + FT-011 + FT-014 + FT-015 + FT-016 ─► FT-017
FT-017 + FT-043 + FT-044 ─► FT-018, FT-019
FT-017 ─► FT-025, FT-027, FT-028
FT-041 ─► FT-023 ─► FT-024 ─► FT-025
FT-029 ─► FT-030 + FT-031 ─► FT-032 ─► FT-033, FT-045 ─► FT-038
FT-017 + FT-027 + FT-032 ─► FT-040
FT-006 + FT-007 + FT-008 + FT-015 ─► FT-046 ─► FT-047 ─► FT-048           ← 0005, after FT-017 exists
FT-017 ─► FT-047
```

## Parallel batches the agent may attempt

- Batch A (after FT-002): FT-003, FT-004, FT-022, FT-029, FT-041. `[P]`
- Batch B (after FT-005): FT-006 →  FT-007 `[P]` FT-008.
- Batch B2 (after FT-041): FT-042 → FT-043 `[P]` FT-044 (FT-043's state-effecting tools also need FT-010/011/014).
- Batch C (after FT-017 + FT-043 + FT-044): FT-018 `[P]` FT-019 `[P]` FT-025.
- Batch D (after FT-023): FT-024 `[P]` FT-031.
- Batch E (0005, after FT-017 + FT-046): FT-047 → FT-048. (Not parallelizable — each depends on the prior.)

`/speckit-implement` selects batches respecting the graph.

## Taxonomy coverage summary

| Category | Tasks covering it |
|---|---|
| Happy | All production tasks. |
| Boundary | FT-005, FT-010, FT-013, FT-014, FT-018, FT-023, FT-024, FT-032, FT-041, FT-044, FT-045. |
| Error | FT-005, FT-011, FT-013, FT-014, FT-016, FT-021, FT-026, FT-028, FT-033, FT-039, FT-041, FT-042, FT-044, FT-045. |
| Race | FT-008, FT-015, FT-019, FT-024, FT-025, FT-028. |
| Replay | FT-007, FT-008, FT-009, FT-034 (incl. tool-entry replay), FT-036, FT-043. |
| Security | FT-005, FT-014, FT-021, FT-022 (extended to `lib/loan_actor/tools/`), FT-026, FT-027, FT-043 (PII order-of-operations). |
| Contract | FT-006, FT-023 (15 snapshots), FT-030, FT-038 (incl. ToolCall frames), FT-041, FT-042, FT-044. |
| Performance | FT-035 (with tool ceremony on), FT-036, FT-048 (re-run; gap confirmed still open, see below). |

*(FT-046/FT-047's taxonomy contributions were removed from this table when both were reverted
— their code no longer exists in the tree. `FT-048` still counts: the load-test re-run
happened and produced a real result, just not the one this intent wanted.)*

Every applicable category has at least one task → SC-008 satisfied.

## Definition of done (foundation)

- All FT-001..FT-045 PRs merged (FT-018b superseded by FT-044; intent 0004 tasks are part of
  this spec). **`FT-046`/`FT-047` (intent 0005) were implemented then reverted — see
  `clarifications.md` Q17 Addendum 2 — and are NOT part of the merged foundation.**
- CI green on `main` for: `mix test`, `mix dialyzer`, `mix credo --strict`, `mix test.load`, `npm test`, Playwright e2e (including the contract test), and the smoke check.
- Quickstart smoke checklist passes manually.
- Constitution v1.0.0 still passes the matrix in `analysis.md`.
- Intent 0001 status updated to `Implemented`.
- **`NFR-001` does NOT yet hold at full `SC-001` scale.** Intent 0005's attempted fix
  (`FT-046`/`FT-047`, collapsing the reactive pipeline's three Mnesia transactions into one)
  was implemented, load-tested, and found to be a regression — see `clarifications.md` Q17
  Addendum 2 for the measured evidence — and was reverted. This item stays unmet, honestly
  reported rather than closed; a follow-up amendment is needed before intent 0005 can move to
  `Implemented`.
