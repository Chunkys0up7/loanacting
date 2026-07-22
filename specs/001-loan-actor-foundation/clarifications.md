# Clarifications — Loan-Actor Foundation

**Spec**: [`spec.md`](spec.md) · **Intent**: [`intents/0001-foundation-loan-as-actor.md`](../../intents/0001-foundation-loan-as-actor.md)
**Resolves**: Q1–Q7 listed in spec.md and intent 0001; Q8–Q11 from amendment intent 0004; Q12 from FT-014 implementation.
**Date**: 2026-05-26 (Q1–Q7) · 2026-07-21 (Q8–Q12)

Each resolution below is now binding for `/speckit-plan` and downstream. Reopening a resolved question requires an amendment intent.

---

## Q1 — Language: Elixir or pure Erlang?

**Resolution: Elixir 1.16+ on Erlang/OTP 26+.**

**Rationale.**
- Equivalent runtime semantics; Elixir is a strict superset of "what's possible" via OTP.
- Better tooling (Mix, ExUnit, StreamData, Credo, Dialyxir) reduces test-discipline friction.
- Phoenix/Bandit gives us a clean HTTP path for AG-UI without bringing a heavyweight web framework if we don't want LiveView.
- Larger talent pool than pure Erlang.
- The constitution mandates a `DiaryStore` behaviour; Elixir's `@behaviour` and `defprotocol` make this ergonomic.

**Trade-off accepted.** Elixir's macro layer adds compile-time complexity; team must read Elixir without leaning on macros that obscure runtime behavior. We will not invent project-specific macros in foundation.

**Locked decisions.**
- `mix new apps/loan_actor --sup` for the supervised application.
- `Elixir 1.16` / `OTP 26` as floor. CI pins these. Upgrades require an amendment.

---

## Q2 — Diary backing store for foundation

**Resolution: Mnesia, behind a `DiaryStore` behaviour with one alternative implementation.**

**Rationale.**
- Mnesia ships with OTP, supports atomic transactions, and gives us indexed access by `loan_id`.
- Constitution Principle IV demands an append-only, chain-linked store. Mnesia tables marked `type: :ordered_set` with `disc_copies` satisfy ordering and durability.
- The `DiaryStore` behaviour decouples future moves (object store, append-only log like Bookkeeper) without disturbing the loan actor.

**Implementations required in foundation.**
1. `LoanActor.Diary.Mnesia` (primary) — durable, ordered, transactional.
2. `LoanActor.Diary.File` (alternative) — newline-delimited JSON in a per-loan file. Slower; used in tests to prove the abstraction is real and to support hermetic CI runs.

Both implementations MUST pass the same property-based test suite.

**Locked decisions.**
- Diary entries are written within the same Mnesia transaction as the state mutation they cause. (No two-phase write.)
- `prev_hash` is computed at write time from the previous entry's `entry_id || payload_hash`.
- PII never enters the diary; the `payload_hash` covers a payload that has already passed through the PII-stripping layer (foundation: a stub that asserts allowed types).

---

## Q3 — AG-UI endpoint host

**Resolution: Served directly from BEAM via Bandit + Plug. No Node CopilotRuntime layer in foundation.**

**Rationale.**
- One fewer process to operate, deploy, and version.
- AG-UI is well-specified (17 events, SSE); implementing the producer in Elixir is bounded — the `copilotkit` skill at `.claude/skills/copilotkit/references/ag-ui-protocol.md` is the reference.
- A future intent can introduce CopilotRuntime if/when its features (e.g., multi-agent fan-out, thread persistence) become necessary. Foundation does not need them.

**Locked decisions.**
- Bandit (not Cowboy) for the HTTP server. Bandit is the modern default and the recommended fit for SSE.
- Plug.Router for the AG-UI endpoint(s). No Phoenix in foundation — adding it later is a separate intent.
- Endpoint shape: `POST /loans/:loan_id/ag-ui` returns `text/event-stream`.

---

## Q4 — Loan state shape

**Resolution: Typed Elixir struct `LoanActor.State` with an explicit `transition/2` function gating mutations.**

**Rationale.**
- A typed struct makes diary replay deterministic and `Dialyxir`-checkable.
- A central `transition/2` enforces that every mutation is paired with a diary append (Constitution Principle IV) — invariant enforced by the type signature, not by reviewer discipline.

**Locked decisions.**
- `defstruct [:loan_id, :status, :goals, :context, :version]` (initial set; expandable via amendment).
- `status` is an atom drawn from a fixed enum documented in `data-model.md`.
- `goals` is a list of `LoanActor.Goal` structs (also typed).
- `version` is a monotonic counter for optimistic concurrency on snapshots — incremented on every transition.
- `transition/2` is the **only** public mutation entrypoint. Any direct struct update outside `transition/2` is a constitution violation and is detected by a custom Credo check.

---

## Q5 — Loop topology: one GenServer or three?

**Resolution: Single GenServer per loan with three explicit responsibilities (`handle_call`/`handle_cast` for reactive, `handle_info` for periodic, and an internal `:plan` self-message for planning). Revisit if profiling shows a bottleneck.**

**Rationale.**
- Simpler ownership of the loan's state — one process, one truth.
- Three processes would multiply the surface area for race conditions and complicate diary atomicity.
- Performance budget (NFR-001) is well within single-GenServer capacity per loan; bottleneck would have to come from shared resources (Mnesia), not the actor itself.

**Locked decisions.**
- The single GenServer is `LoanActor.Server`. Its supervisor is `LoanActor.Supervisor` (one-for-one).
- The "three loops" are documented as code conventions in the module docs and enforced by a Credo check that prohibits adding additional `handle_*` clauses without a comment tagging the loop.

**Kill criterion.** If load testing (SC-001) shows the actor exhibits mailbox backpressure or planning starves reactive handlers, we revisit via amendment intent.

---

## Q6 — Idempotency key

**Resolution: `(event_id, source)` composite key.**

**Rationale.**
- `event_id` alone risks collisions between independent sources (e.g., two integrators generating the same UUID by accident or by replay across vendors).
- `(event_id, source)` accepts re-delivery from a given source as a no-op while admitting legitimate events that happen to share an `event_id` from a different source.
- Storage cost is negligible; `source` is a short atom.

**Locked decisions.**
- The Event struct gains `source` as a required field with a fixed enum (foundation: `:operator`, `:system`, `:test`). Adding new sources requires an amendment.
- The idempotency check is a Mnesia `read` keyed on `{loan_id, event_id, source}` within the transaction that would append the diary entry. Hit → no-op + return `:duplicate`.

---

## Q7 — Operator authentication for foundation

**Resolution: Env-injected `OPERATOR_ID` (no real auth). Implementations MUST be structured to make a future auth-intent change minimal.**

**Rationale.**
- Intent 0001 explicitly defers real auth.
- An env-injected ID supports the foundational diary-attribution requirement (Constitution Principle VII: every actor that mutates state has identity in the diary).
- Real auth (OIDC, role-based, possibly per-tenant) is a non-trivial intent and must not be conflated with the runtime foundation.

**Locked decisions.**
- HTTP middleware reads `x-operator-id` header (preferred) or `OPERATOR_ID` env var (fallback for local dev).
- Every state-mutating endpoint requires the header in production builds (controlled by `Application.get_env(:loan_actor, :require_operator_id, true)`); tests can disable.
- A future amendment will replace the middleware with a real auth plug. The interface (`Plug.Conn.assigns[:operator_id]`) MUST remain stable.

---

## Q8 — Public `invoke_tool/3` on the Server API? *(0004)*

**Resolution: No. Tool invocation is internal-only.**

**Rationale.** Constitution Principle I: capabilities are summoned **by** the loan, never
orchestrated over it. A public invoke API would be an orchestration seam — external systems
would drive the loan instead of the loan driving itself. External influence flows through
`send_event/2` (facts) and `respond_hitl/3` (answers).

**Locked decisions.** `contracts/loan-actor-api.md` carries the normative internal-only
note; the public surface is unchanged by 0004.

---

## Q9 — Args-schema validation depth *(0004)*

**Resolution: Hand-rolled JSON-schema subset — `type`, `properties`, `required`, `enum`. No new dependency.**

**Rationale.** Foundation tools have small, flat argument maps; a full validator
(`ex_json_schema`) is a dependency and an attack surface we don't need yet. The subset is a
HARD CAP pinned in `contracts/tool-behaviour.md`; extending it requires an amendment
(mirrors 0003's rule-DSL cap).

---

## Q10 — Skill trigger-match semantics for foundation *(0004)*

**Resolution: Normalized substring/keyword match of the pack's `description` against the loan's match-text `{status, latest event type, open goal descriptions}`.**

**Rationale.** Foundation must prove the load → trigger → tool path, not build a retrieval
system. The naive matcher is deterministic, testable, and explicitly documented as such in
`contracts/skill-format.md`. Intent 0003 owns assessment-driven selection.

**Locked decisions.** A non-matching state activates zero skills (test-pinned);
over-matching at foundation scale (one demo pack) is accepted.

---

## Q11 — Is inbound event ingestion a tool call? *(0004)*

**Resolution: No. The reactive pipeline (PIIGuard → idempotency → transition → diary append) stays as specced; tools are the actor's SELF-INITIATED functions only (periodic/planning loops + HITL emission).**

**Rationale.** Making ingestion a tool call would double-log every event (event entry + tool
pair), blur `NoDirectStateMutation` semantics, and add ceremony to the hottest path
(NFR-001). The glass-box value of ToolCall streaming is in what the loan chooses to do, not
in what happens to it.

---

## Q12 — PIIGuard.apply/1: hard gate or redact-and-continue? *(FT-014, 2026-07-21)*

**Resolution: Hard gate.** Any value anywhere in the payload matching a configured PII
pattern → `{:error, :pii_violation, paths}`, the whole event rejected. No match →
`{:ok, payload, []}`. `redacted_paths` is always `[]` in foundation.

**Rationale.** `tasks.md` FT-014 documents `apply/1` returning one of two distinct shapes
(`{:ok, stripped_payload, redacted_paths}` or `{:error, :pii_violation, paths}`) without
stating what distinguishes them; `data-model.md`'s narrative ("reject... replace flagged
values with `<redacted>`...") reads ambiguously between the two. Per PD-1 (no invention —
stop and resolve rather than guess), this was raised to the operator directly rather than
silently decided. Confirmed: hard gate is simplest, safest, and consistent with
data-model.md's closing note that vault-backed redact-and-substitute is a **future** intent
— foundation's `PIIGuard` only gates; `redacted_paths` is a forward-compatible field, not
yet exercised with non-empty values.

**Locked decisions.**
- `priv/pii_patterns.yml` holds four value-pattern categories (ssn, account_number,
  routing_number, date_of_birth) in a restricted hand-parsed grammar — **not** general YAML
  (no yaml dependency is declared in any intent's Dependencies section; adding one would be
  an undeclared-dependency anti-vibe violation, so a minimal reader was written instead,
  mirroring the skill-format front-matter cap).
- `paths` in the `:error` tuple are root-relative key-paths (string map keys and/or list
  indices) to every offending value, collected across the whole payload (not short-circuited
  on first match).

---

## Q13 — send_event/2's {:duplicate, sequence} vs. loan_idem's bare received_at *(FT-017, 2026-07-21)*

**Resolution: extend the `loan_idem` record to carry the sequence.** Value becomes
`{received_at, sequence}`; `Idempotency.check_and_record/3` returns `{:duplicate, sequence}`
(the ORIGINAL sequence) instead of bare `:duplicate`. `data-model.md`'s Mnesia schema line
updated to match.

**Rationale.** `contracts/loan-actor-api.md` documents `send_event/2` returning
`{:duplicate, sequence}`, but `data-model.md`'s `loan_idem` schema only stored
`received_at` — no way to source `sequence` as specified. Two candidate fixes existed
(extend the record; or simplify the contract to bare `:duplicate` for foundation); per
PD-1 this was raised directly rather than guessed. Confirmed: extend the record.

**Locked decisions.**
- Two-phase reserve-then-fill: `check_and_record/3` atomically reserves the key
  (`sequence: nil`) so the exactly-one-`:fresh`-winner guarantee (proven under raw
  concurrency, FT-015's race test) still holds even though the sequence isn't known until
  after the diary append. `record_sequence/4` fills it in once the caller (the Server,
  FT-017 — a single serialized GenServer mailbox per loan) knows the real sequence.
- Known, accepted limitation: if the diary append fails after a successful reservation,
  the key stays reserved with `sequence: nil` forever (no rollback). Out of scope — an
  extremely narrow failure mode neither source document addresses; not building
  compensating-transaction logic for it.

---

## Q14 — Where do a skill-triggered tool's arguments come from? *(FT-018, 2026-07-21)*

**Resolution: the skill's own `description` becomes the tool's args.** When a matched skill
names `set_goal` in `tools_required`, the periodic loop invokes it with
`{"description" => skill.description}`. `verify_diary_chain` (no required args) runs
unconditionally every heartbeat as a housekeeping self-check, independent of skill matching.

**Rationale.** `contracts/skill-format.md` specifies that a skill *names* required tools
(`tools_required: [String.t]`) but nowhere specifies how a skill supplies a named tool's
actual arguments — a whole missing mechanism, not a small gap. Raised directly (PD-1).
Confirmed: reuse the skill's own trigger text rather than inventing a new per-tool argument
binding scheme. No new mechanism was added; `description` already exists on every skill.

**Locked decisions.**
- `verify_diary_chain` is NOT skill-gated — it is a periodic loop self-check that fires
  every heartbeat regardless of which (if any) skill matches.
- Diary discipline for periodic tool invocations (constitution Principle VIII): every
  invocation appends `:tool_invoked` then `:tool_completed`/`:tool_failed`, payload carrying
  the tool name, invocation id, and a **hash** of the (PII-guarded) args/result — never the
  raw values, per `contracts/tool-behaviour.md` invariant 4.
- `LoanActor.State` gained `add_goal/2`, `satisfy_goal/2`, `record_heartbeat/2` — mutation
  helpers for the state surface `transition/2` deliberately does not cover (goals and
  `last_heartbeat_at` are not part of the status state-machine graph). All three use the
  same bare `%{state | ...}` form `transition/2` already uses, keeping every legal mutation
  centralized in this one module.

---

## Q15 — Where does request_document's doc_type argument come from? *(FT-019, 2026-07-21)*

**Resolution: keyword-match open goals' descriptions for one of "income"/"identity"/
"appraisal"; default "income" if none mention one.**

**Rationale.** `request_document`'s schema requires `doc_type` as one of a fixed enum —
unlike `set_goal`'s free-text `description` (Q14's resolution doesn't transfer directly).
Neither the `Goal` struct nor `contracts/skill-format.md` carries a structured `doc_type`
field. Raised directly (PD-1) rather than silently defaulting. Confirmed: the planning loop
scans `state.goals` (open ones only), keyword-matching each description against the three
enum words; first match wins; `"income"` if none match — documented as the foundation
placeholder, not a real business rule.

**Locked decisions.**
- `LoanActor.Server.infer_doc_type/1` is exposed (not part of `contracts/loan-actor-api.md`)
  specifically so this pure decision is directly unit-testable — diary entries carry only a
  **hash** of tool args/results (Principle VIII), so which `doc_type` was actually chosen can
  never be recovered by reading the diary from outside.
- `LoanActor.Server.maybe_trigger_planning/1` is exposed for the same reason: an
  integration-level "did NOT trigger planning again" assertion is confounded by the periodic
  loop's own independent `verify_diary_chain` invocation, since diary entries can't reveal
  *which* tool a `:tool_invoked` entry is for.
- `:plan` fires specifically after a successful `:goal_set` reactive transition — a literal
  reading of "when goals are set" (FT-019's task text), not "any state change re-plans".
- `run_planning/1` diary-logs `:skill_activated` for every match, regardless of which tool
  (if any) it acts on — mirrors `run_matched_skills/1`'s (FT-018) established behavior;
  consistency, not a new rule.

---

## Q16 — Subscriber backpressure signal *(FT-024, 2026-07-21, no answer returned — proceeded with the flagged recommendation)*

**Resolution: `Process.info(self(), :message_queue_len)`** — the Subscriber's OWN Erlang
process mailbox depth, checked at the start of each `:deliver` cast.

**Rationale.** `research.md` R-2 says resync mode engages when "the subscriber's mailbox
exceeds the bound", but `send/2` never blocks or reveals whether a receiver is keeping up —
some concrete signal has to stand in for "mailbox". A clarifying question was raised (two
options: read `message_queue_len` literally, or invent an explicit ack protocol between
subscriber and owner) but no answer came back; proceeded with the flagged recommendation
rather than blocking indefinitely, and recorded here for easy revisit.

**Locked decision.** `message_queue_len` is simple and needs no new protocol, but is
strictly weaker than an ack-based design: a slow HTTP/SSE *owner* process holding its own
mailbox full of undelivered `:ag_ui_event` messages does not show up in the *subscriber's*
mailbox unless the loan actor is also casting in a tight burst. Revisit once FT-027 (the
HTTP layer, the actual "slow client" scenario) exists and can prove whether this is
sufficient in practice.

---

## Summary of locked architectural decisions

| Concern | Decision |
|---|---|
| Language | Elixir 1.16+ / OTP 26+ |
| Web layer | Bandit + Plug.Router (no Phoenix in foundation) |
| Diary store | Mnesia primary; File alternative; both behind `DiaryStore` behaviour |
| State shape | Typed struct `LoanActor.State` with single mutation gate `transition/2` |
| Loop topology | Single GenServer with documented three-loop handler convention |
| Idempotency | Composite `(event_id, source)` key |
| Auth | Env/header-injected operator id (real auth deferred) |
| Build system | Mix umbrella (frontend lives at `apps/web/`, backend at `apps/loan_actor/`) |
| AG-UI endpoint | `POST /loans/:loan_id/ag-ui` returning `text/event-stream` |
| HITL mechanism | `request_operator_approval` tool (deferred ToolCallResult) + AG-UI `CustomEvent` + CopilotKit `useHumanInTheLoop` *(0004)* |
| Agent functions | Tools (typed, registry-listed, effects-returning) + skill packs (`priv/skills/`, trigger = `description`) *(0004)* |
| Tool invocation surface | Internal-only; no public invoke API *(0004, Q8)* |

These decisions become inputs to `/speckit-plan`.
