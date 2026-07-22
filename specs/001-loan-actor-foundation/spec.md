# Feature Specification: Loan-Actor Foundation

**Feature Branch**: `001-loan-actor-foundation`

**Created**: 2026-05-26

**Status**: Draft

**Input**: Intent [`intents/0001-foundation-loan-as-actor.md`](../../intents/0001-foundation-loan-as-actor.md)

**Amended**: 2026-07-21 by intent [`0004-amend-agent-functions-tools-skills`](../../intents/0004-amend-agent-functions-tools-skills.md) — agent functions are tools + skills (FR-016..018, SC-013/014; FR-007 + SC-012 rewritten; `Procedure` entity superseded by `ToolSpec` + `Skill`).

**Amended**: 2026-07-22 by intent [`0005-amend-reactive-pipeline-throughput`](../../intents/0005-amend-reactive-pipeline-throughput.md) — reactive pipeline throughput (FR-019 added; NFR-001 gap found by `FT-035`'s load test being closed; SC-015 added).

**Constitution**: [`v1.2.0`](../../.specify/memory/constitution.md)

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Spawn and observe a live loan (Priority: P1)

A back-office operator opens the loan-management interface, creates a new loan record, and immediately sees a live "actor" representation of the loan: its current state, its goals, and a real-time diary feed of every event the loan has experienced. The operator can send the loan a synthetic event (e.g., "document received") and watch the loan's state and diary update in the UI within a second.

**Why this priority**: Without an addressable, observable, live loan actor, every later capability (compliance, valuation, servicing) has nothing to attach to. This is the inversion the entire architecture depends on. If we cannot demonstrate a single loan as a supervised process surfaced through CopilotKit, the foundation has failed.

**Independent Test**: Given a freshly-started runtime, spawning loan `L-001` and sending it a `document_uploaded` event MUST result in (a) a diary entry visible in the UI within 1 second, (b) a state transition reflected in the UI, (c) no operator intervention required.

**Acceptance Scenarios**:

1. **Given** a running BEAM node with no loans, **When** the operator invokes "create loan" in the UI with `loan_id = L-001`, **Then** a supervised loan actor exists, its diary contains a first entry of type `:spawned`, and the UI shows the loan's initial state.
2. **Given** loan `L-001` exists in state `:awaiting_documents`, **When** the operator sends a `:document_uploaded` event via the UI, **Then** the diary appends a `:document_received` entry and the UI reflects the new state within 1 second.
3. **Given** loan `L-001` is alive with N diary entries, **When** the operator refreshes the page, **Then** all N entries are re-displayed in order, identical to the live feed before refresh.

---

### User Story 2 — Survive a crash without losing state (Priority: P1)

When the underlying loan-actor process crashes (simulated failure, deployment, or runtime fault), its supervisor restarts it. The restarted actor rehydrates its full state by replaying its diary; no event is lost, no state is duplicated, and the UI does not show any discontinuity beyond a brief "reconnecting" indicator.

**Why this priority**: A 30-year mortgage cannot afford even one lost event. Crash-safety is what makes the actor model worth the architectural cost. Without it, the architecture is a worse version of a database.

**Independent Test**: Kill a loan-actor process while it has non-empty state; verify the supervisor restarts it within 1 second; verify the rehydrated state byte-identical to the pre-crash state; verify the UI reconnects automatically.

**Acceptance Scenarios**:

1. **Given** loan `L-002` is alive with M diary entries and state `S`, **When** the actor process is killed unexpectedly, **Then** within 1 second the supervisor restarts it, replay of the diary produces state `S`, and the next event after restart is processed normally.
2. **Given** the same loan, **When** an event is delivered twice with the same `event_id`, **Then** the diary appends exactly one entry — the second delivery is a no-op (idempotency).
3. **Given** a chain-linked diary, **When** any entry is tampered with offline, **Then** a verification check detects the tampering at next replay.

---

### User Story 3 — Loan asks the operator a question (HITL) (Priority: P2)

A loan in mid-process notices it cannot proceed without operator judgment (e.g., an ambiguous document). The loan emits an approval request that surfaces in the operator's CopilotKit UI as an interrupt card. The operator approves or rejects in the UI; the loan receives the answer, records it as a diary event, and resumes.

**Why this priority**: HITL is the seam where human judgment enters the loop. Foundation must support it, but the specific HITL workflows for compliance, doc-review, and exception handling are later intents. We need the *mechanism* now; not the *use cases*.

**Independent Test**: Trigger a synthetic "approval required" event on a live loan; verify the UI surfaces an interrupt card via the CopilotKit HITL hook; verify operator approval propagates back and a diary entry of type `:approval_received` appears.

**Acceptance Scenarios**:

1. **Given** loan `L-003` is in a state that triggers the HITL stub, **When** the loan emits an `:operator_approval_required` event, **Then** the UI renders an interrupt card and pauses the loan's planning loop.
2. **Given** the interrupt card is open, **When** the operator clicks "approve" with a comment, **Then** the loan receives the response, appends a diary entry `:approval_granted` with the comment, and resumes its planning loop.
3. **Given** the interrupt card is open, **When** the operator clicks "reject", **Then** the loan appends `:approval_denied` and transitions into the documented next state (e.g., back to `:awaiting_documents`).

---

### Edge Cases

- **Concurrent events**: Two events arrive at the same actor mailbox at the same instant. Both MUST be processed in mailbox FIFO order; both MUST produce ordered diary entries.
- **Heartbeat during crash**: A heartbeat fires while the actor is mid-handler. The heartbeat MUST be queued behind the in-flight handler, not interrupt it.
- **Empty diary on restart**: The actor restarts but its diary is empty (cold start). The replay MUST produce the documented initial state, identical to the spawn-time state.
- **Large diary replay**: An actor has 1,000,000 diary entries. Replay on restart MUST complete within a documented bound (see SC-007).
- **Out-of-order event delivery**: An event arrives with a `created_at` timestamp earlier than the most recent diary entry. Event MUST still be appended at the current tail; ordering is by *arrival*, not by *creation time*. The semantic discrepancy is logged.
- **AG-UI client disconnection mid-stream**: The CopilotKit client disconnects mid-event. The loan MUST continue processing; the client MUST reconnect with `MessagesSnapshot` to resync.
- **Operator never responds to HITL**: An interrupt card is opened and the operator closes the browser. The loan remains paused. A documented timeout MUST surface the stalled interrupt as a separate alert (specific timeout policy is a later intent; foundation must expose the hook).
- **Two operators answer the same HITL simultaneously**: First response wins (atomic); second response is rejected with a documented error and a diary entry of type `:approval_conflict`.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST allow spawning a new supervised loan actor identified by a `loan_id` (UUIDv7 for foundation).
- **FR-002**: System MUST accept typed events delivered to a loan by `loan_id`; events MUST carry an `event_id` for idempotency.
- **FR-003**: System MUST append every accepted event to the loan's diary atomically with any state transition the event causes.
- **FR-004**: System MUST reject duplicate events (same `event_id`) as no-ops without appending a second diary entry.
- **FR-005**: System MUST chain-link diary entries (each entry contains the hash of the previous entry) so that tampering is detectable.
- **FR-006**: System MUST run three explicit loops per loan actor: reactive (mailbox), periodic (heartbeat), planning (goal-driven). Each loop's responsibilities MUST be classified in code.
- **FR-007**: System MUST emit AG-UI events (`RunStarted`, `StateSnapshot`, `StateDelta`, `TextMessage*`, `CustomEvent`, and — per FR-018 — `ToolCallStart`, `ToolCallArgs`, `ToolCallEnd`, `ToolCallResult`) to subscribed clients reflecting the loan's lifecycle. *(Amended by 0004.)*
- **FR-008**: System MUST restart a crashed loan actor under OTP supervision within a bounded time and rehydrate state from diary replay.
- **FR-009**: System MUST expose a CopilotKit-driven web UI rendering, for a given `loan_id`: current state, pending goals, live diary feed, and a control to send synthetic events.
- **FR-010**: System MUST support a human-in-the-loop approval mechanism whereby a loan emits an interrupt event, the UI renders an approval card, and the operator's response resumes the loan and is recorded as a diary entry.
- **FR-011**: System MUST keep PII out of the diary; diary entries contain hashes/pointers and a separate vault stores the PII. (Vault implementation is out of scope; the diary's API MUST enforce the boundary.)
- **FR-012**: System MUST provide a property-based test harness for state-machine transitions.
- **FR-013**: System MUST support reproducible state via diary replay for every state-mutating handler; this MUST be exercised by automated tests.
- **FR-014**: System MUST log every LLM call site's *absence* — foundation contains zero LLM calls, and the test suite MUST assert this invariant.
- **FR-015**: System MUST surface operator authentication as an injected operator identity (env-configured for foundation); real auth is deferred.
- **FR-016** *(0004)*: Every **self-initiated** actor function (periodic/planning-loop actions, HITL emission) MUST be a **tool**: a registered module implementing the `LoanActor.Tool` behaviour with a name, description, and JSON-schema'd parameters (restricted subset: `type`/`required`/`enum`/`properties`). Tool invocation MUST validate args against the schema, MUST pass args through the PII guard **before** diary hashing and before any UI emission, MUST produce diary entries `:tool_invoked` then `:tool_completed` or `:tool_failed`, and MUST return effects that the Server applies through `State.transition/2` — tools never mutate state directly. Inbound event ingestion (the reactive pipeline) is NOT a tool call. The registry holds zero routing/trigger logic.
- **FR-017** *(0004)*: Operating knowledge MUST load as **skill packs**: directories under `priv/skills/<id>/` with a `SKILL.md` manifest (front-matter: `name`, `version`, `description` — the trigger, `tools_required`) plus optional reference files. The loader MUST validate every `tools_required` entry against the tool registry at load time (unresolvable pack → rejected with logged reason), MUST support reload without restart, and MUST trigger-match skills against the loan's `{status, event type, open goal descriptions}` (foundation: normalized substring matching). Skill activation appends a `:skill_activated` diary entry. Skill packs supersede the single-file Procedure stub.
- **FR-018** *(0004)*: **Every** tool invocation MUST stream to subscribed AG-UI clients as `ToolCallStart` → `ToolCallArgs` (single frame, PII-redacted args) → `ToolCallEnd` → `ToolCallResult`. The HITL tool defers its `ToolCallResult` until the operator responds (`respond_hitl`); all other foundation tools emit the full sequence atomically per invocation.
- **FR-019** *(0005)*: The reactive event pipeline's per-event storage work (duplicate-detection against `(loan_id, event_id, source)` plus the diary append it gates) MUST hold `NFR-001` at the full `SC-001` load profile. This MUST NOT weaken `FR-004` (duplicates still produce zero additional diary entries), `FR-005` (chain-link tamper detection), or `NFR-003` (crash-recovery correctness) — whichever storage-transaction shape achieves this (resolved in `clarifications.md` Q17 and pinned in `plan.md`) is an internal implementation detail, not a change to any externally observable contract in `contracts/loan-actor-api.md`.

### Non-Functional Requirements

- **NFR-001**: P95 event-to-diary latency MUST be < 100 ms at 100 concurrent loans / 10 events/sec/loan. *(0005: `FT-035`'s load test found this did not hold at full scale — 496.64 ms p95 measured; see FR-019.)*
- **NFR-002**: Resident memory MUST be < 256 MB under the NFR-001 load profile.
- **NFR-003**: Crash-recovery time (kill → restart → rehydrated) MUST be < 1 second for a loan with up to 10,000 diary entries.
- **NFR-004**: AG-UI event delivery from diary append to subscribed client MUST be < 250 ms p95 (LAN/loopback).
- **NFR-005**: The diary store MUST implement a `DiaryStore` behaviour/interface that admits at least two implementations (file-backed and Mnesia-backed) for foundation; switching MUST require zero changes outside the implementation module.

### Key Entities

- **Loan** — A supervised actor with: `loan_id`, current `state` (typed struct), `goals` (list), reference to its `diary`. Identity is stable for life.
- **DiaryEntry** — Append-only record: `entry_id`, `loan_id`, `timestamp`, `type`, `payload_hash`, `prev_hash`, `actor` (operator id or "system"). Holds NO PII.
- **Event** — Inbound message to a loan: `event_id` (idempotency key), `type`, `payload`, `source`, `created_at`.
- **HITLRequest** — Outbound interrupt: `request_id`, `loan_id`, `prompt`, `options`, `created_at`.
- **HITLResponse** — Inbound approval: `request_id`, `decision`, `comment`, `operator_id`, `responded_at`.
- **ToolSpec** *(0004)* — Typed description of a tool: `name`, `description`, `parameters` (JSON-schema subset). Implemented by modules under the `LoanActor.Tool` behaviour; enumerated by the config-driven registry.
- **Skill** *(0004; supersedes Procedure)* — Versioned markdown pack: `id`, `name`, `version`, `description` (trigger), `tools_required`, `body`, reference files, `path`. Foundation ships one demo pack (`priv/skills/0001-demo-document-request/`) proving load → trigger-match → tool-reference resolution.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Spawn 100 concurrent loan actors and deliver 10 events/sec/loan for 60 seconds with p95 event-to-diary latency < 100 ms. (Verifies User Story 1, FR-001..FR-007, NFR-001.)
- **SC-002**: Kill 10 loan actors simultaneously; supervisor restarts all 10 within 1 second; all 10 rehydrate to byte-identical state. (Verifies User Story 2, FR-008, NFR-003.)
- **SC-003**: Deliver every event in a 10,000-event corpus twice; verify each diary contains exactly one entry per event. (Verifies FR-004 idempotency.)
- **SC-004**: Property-based test runs 10,000 generated event sequences; for every sequence, replaying the diary produces the same final state and same diary as the original. (Verifies FR-013, User Story 2.)
- **SC-005**: Trigger an HITL request on a live loan from the UI; verify the interrupt card renders within 500 ms; approve from a second browser tab; verify the loan resumes and the approval is in the diary. (Verifies User Story 3, FR-010.)
- **SC-006**: Tamper with any single diary entry's payload; verify the chain-link verification reports the tampering at next replay. (Verifies FR-005.)
- **SC-007**: A loan with 1,000,000 synthetic diary entries replays in under 30 seconds on the reference hardware. (Verifies NFR-003 at scale.)
- **SC-008**: Coverage taxonomy — happy / boundary / error / race / replay / security — each category has at least one test, mapped in the PR description. (Verifies Constitution Principle V.)
- **SC-009**: A grep across the source tree for `LLM`, `OpenAI`, `Anthropic`, or `completion` returns zero hits in production code paths; a test in `test/llm_absence_test.exs` asserts the same. (Verifies FR-014, Constitution Principle III.)
- **SC-010**: No diary entry contains a value matching the operator-supplied PII patterns (regex-based test against a synthetic PII corpus injected through events). (Verifies FR-011.)
- **SC-011**: Configure heartbeat interval to 1 second; over 10 seconds observe ≥ 9 and ≤ 11 `:heartbeat` diary entries on a single loan. (Verifies FR-006 periodic loop.)
- **SC-012** *(rewritten by 0004)*: Given a loan with goal `:require_document(:income)`, when the goal is set, the planning loop within one heartbeat invokes the `request_document` **tool**, producing the diary pair (`:tool_invoked`, `:tool_completed`) and the `ToolCallStart → ToolCallArgs → ToolCallEnd → ToolCallResult` sequence over AG-UI, with the request payload carried in `ToolCallResult`. (Verifies planning loop semantics independent of HITL.)
- **SC-013** *(0004)*: Invoking any registered tool on a live loan produces `:tool_invoked` + terminal (`:tool_completed`/`:tool_failed`) diary entries and the four ToolCall events observed by a subscribed client within 250 ms p95. A synthetic-PII argument injected into a tool call appears in **neither** the diary payload nor any ToolCall frame. (Verifies FR-016/FR-018, PII rule.)
- **SC-014** *(0004)*: The demo skill pack trigger-matches a loan in `:awaiting_documents` with an open document goal, appends `:skill_activated`, resolves `tools_required` against the registry, and its named tool executes; a loan in a non-matching state activates zero skills; a pack naming a nonexistent tool is rejected at load with a logged reason. (Verifies FR-017.)
- **SC-015** *(0005)*: Re-running `FT-035`'s load test (`mix test.load`) at its default `LOAN_LOAD_*` scale (100 concurrent loans, 10 events/sec/loan, 60 seconds) shows p95 event-to-diary latency < 100 ms, with `NFR-002`/`NFR-003`/`NFR-004` continuing to pass in the same run. (Verifies FR-019, NFR-001.)

## Assumptions

- Single-node BEAM runtime is sufficient for foundation. Multi-node clustering, distribution, and dynamic supervision are deferred to a later intent.
- The reference hardware for performance budgets is a modern developer laptop (8 cores, 16 GB RAM, NVMe SSD). Production hardware targets are a separate intent.
- The CopilotKit frontend runs as a single SPA against a single BEAM backend over LAN/loopback during foundation development. CDN delivery, multi-tenancy, and edge deployment are deferred.
- Operator authentication is stubbed: an `OPERATOR_ID` env var or query string parameter identifies the operator. Real auth (OIDC, role-based) is a separate intent.
- One demo skill pack is bundled to prove the load → trigger → tool path; foundation does not implement compliance/escalation skill semantics. *(Amended by 0004; formerly a single no-op Procedure file.)*
- The diary backing store for foundation is Mnesia (transactional, single-node, ships with OTP). The `DiaryStore` behaviour permits swapping to file-backed or a future external store.
- LLM integration is intentionally absent in foundation. Hooks/abstractions for LLM escalation are introduced only when a later intent requires them.

## Out of Scope (recap from intent 0001)

- Business-domain capabilities: compliance rules, valuation, document extraction, underwriting.
- Secondary-market sale flow and MISMO identity overlay.
- Portfolio-level (multi-loan) UI.
- Production-grade persistence beyond Mnesia.
- LLM-escalation policies.
- Real operator authentication.

## Open Questions (carried from intent 0001 — to be resolved in `/speckit-clarify`)

- **Q1**: Elixir or pure Erlang? (Recommendation in intent: Elixir.)
- **Q2**: Diary backing store for foundation — file, Mnesia, or DETS? (Recommendation: Mnesia.)
- **Q3**: AG-UI endpoint host — direct from BEAM (Plug/Bandit), or behind a Node CopilotRuntime? (Recommendation: direct.)
- **Q4**: State shape — plain map or typed struct + behavior contract? (Recommendation: typed struct.)
- **Q5**: Three loops — one GenServer with three handlers, or three GenServers under a supervisor? (Recommendation: single GenServer with explicit handlers.)
- **Q6**: Idempotency key — `event_id` only or `(event_id, source)`? (Open.)
- **Q7**: Operator auth for foundation — env-injected stub or query param? (Recommendation: env-injected; auth is a separate intent.)
