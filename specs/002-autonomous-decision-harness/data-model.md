# Data Model — Autonomous Decision Harness

Phase 1 output of `/speckit-plan`. Defines every new entity this feature adds on top of
`001-loan-actor-foundation/data-model.md`, which this document does not repeat or restate except
where a foundation type is directly extended.

---

## Entities

### `%LoanActor.Assessment{}`

A point-in-time, typed summary of a loan's situation. Not persisted as a struct — only the
diary entry that records an assessment happened is durable; the struct itself is reproducible by
re-running `assess_loan` against the same state (FR-001).

| Field | Type | Notes |
|---|---|---|
| `loan_id` | `String.t` | The loan this assessment is about. |
| `document_completeness` | `:complete \| :incomplete \| :unknown` | Derived from `state.goals`' document-related entries + `state.context`. |
| `goal_ages` | `%{goal_id => non_neg_integer}` | Milliseconds since each open goal's creation, derived from `last_heartbeat_at`/diary-derived timing facts (R-3), not wall-clock at assessment time — replay-reproducible. |
| `sla_state` | `:on_track \| :at_risk \| :breached \| :n_a` | Derived from goal ages against any `due_at` present. |
| `data_quality_flags` | `[atom]` | Open, extensible set of named quality issues a gate may reference (e.g. `:missing_source_field`); closed enum lives in code, not invented ad hoc by gate packs. |
| `computed_at_version` | `non_neg_integer` | The `state.version` this assessment was derived from — pins it to an exact replay position. |

**Purity invariant (FR-001)**: `assess_loan(state) == assess_loan(state)` for the same `state`,
always — no wall-clock reads, no diary I/O (R-5).

### `%LoanActor.Gate{}`

The parsed, in-memory form of one rule from a gate pack. Built by `evaluate_gate` at evaluation
time from the gate pack's front-matter (loaded via the existing `Skill.Loader` mechanism,
extended per `contracts/gate-pack-format.md`) — not a separately-persisted entity.

| Field | Type | Notes |
|---|---|---|
| `id` | `String.t` | Stable identity across versions of the "same" gate. |
| `version` | `String.t` | The gate pack's own version (semver-style string, per skill-format precedent). |
| `combinator` | `:all \| :any` | Top-level predicate combinator (R-2). |
| `predicates` | `[%{field: String.t, op: atom, value: term}]` | The restricted predicate list — grammar hard-capped per `contracts/gate-behaviour.md`. |
| `pack_id` | `String.t` | The originating skill-format pack's own `id` (mirrors `%Skill{}.id`). |

### `%LoanActor.Decision{}`

Not a separately-stored struct — this row documents the SHAPE of the `:decision` diary entry's
payload (hashed per Principle VIII, like every other tool-driven diary entry; see the entry-type
table below). Listed as an entity because the spec's Key Entities section names it and because
its field set is a contract other code (and future audits) rely on.

| Field | Type | Notes |
|---|---|---|
| `gate_id` | `String.t` | Which gate produced this decision. |
| `gate_version` | `String.t` | Pinned per-loan per FR-011 — the version THIS loan evaluated this gate under, not necessarily the currently-loaded latest. |
| `input_digest` | `String.t` (hex hash) | Hash of exactly the `%Assessment{}` struct the gate was evaluated against — nothing else (clarified during `/speckit-checklist`, finding CHK007; "any other inputs" in an earlier draft of this row was itself the ambiguity being fixed). Since `evaluate_gate` per `gate-behaviour.md` reads ONLY `assessment.*`/`state.*` fields, the assessment alone fully captures what the gate saw. |
| `outcome` | `:pass \| :fail` | `:indeterminate` never reaches a `%Decision{}` — it produces an `%Escalation{}` instead (FR-004). |

### `%LoanActor.Escalation{}`

| Field | Type | Notes |
|---|---|---|
| `escalation_id` | `String.t` (UUIDv7) | Stable identity, mirrors `%HITLRequest{}.request_id`'s shape. |
| `gate_id` | `String.t` | Which gate's `:indeterminate` outcome raised this. |
| `gate_version` | `String.t` | Same pinning rule as `%Decision{}` (FR-011). |
| `trigger` | `String.t` | Machine-readable cause — WHY the gate couldn't decide (e.g. `"missing_required_field:appraisal_date"`). |
| `target` | `:operator \| :llm` | Which escalation path this went to. **Clarified during `/speckit-checklist`, finding CHK009**: a `:operator` target invokes the EXISTING `request_operator_approval` tool completely unchanged — it is not routed through, wrapped by, or in any sense "inside" `contracts/llm-escalation-port.md`'s adapter port. That port has exactly one caller (`assess_via_llm`) and exists ONLY for the `:llm` target; `:operator` is a structurally separate path that happens to share the same `%Escalation{}` bookkeeping struct. |
| `resolution` | `{:answered, term} \| {:fallback, atom} \| nil` | `nil` while pending; `{:fallback, mode}` for one of the four defined LLM failure modes (FR-006) when the target was `:llm` and it failed; `{:answered, decision}` otherwise. |

**Multiple simultaneous pending escalations per loan are allowed** (resolved during
`/speckit-checklist`, finding CHK016) — FR-004's "raises an escalation" is per-gate, and a
single loop pass may match and evaluate several gates, more than one of which may independently
resolve `:indeterminate`. This mirrors foundation's own existing design exactly:
`LoanActor.Server`'s `gen_state.hitl_requests` is already a map keyed by `invocation_id`, not a
single slot — foundation already supports multiple concurrent pending HITL requests structurally,
even though no foundation scenario happened to exercise more than one at a time. This feature's
escalations reuse that same shape; each `%Escalation{}` is independently tracked and resolved by
its own `escalation_id`, with no ordering or mutual-exclusion constraint between them.

---

## Diary entry types (extends foundation's open-atom `Entry.type`)

Per intent 0004's own precedent (confirmed in its retrospective: `Entry.validate_type/1` accepts
any atom, so new diary types touch zero merged code), these are pure additions:

| Type | Payload shape | Hashing rule |
|---|---|---|
| `:assessment` | `{"loan_id", "computed_at_version", "assessment_hash"}` | Standard Principle VIII hash-only — an assessment is a pure derivation, not user-facing output an auditor needs verbatim. |
| `:gate_evaluated` | `{"gate_id", "gate_version", "outcome", "cause_hash"}` | Standard hash-only. `outcome` itself (`pass`/`fail`/`indeterminate`) is a closed enum, not sensitive — stored in clear; only free-text `cause` detail is hashed. |
| `:decision` | `{"gate_id", "gate_version", "input_digest", "outcome"}` | Standard hash-only (`input_digest` IS already a hash by definition — see `%Decision{}` above). |
| `:escalated` | `{"escalation_id", "gate_id", "gate_version", "trigger", "target", "input_hash"}` | Standard hash-only for `trigger`'s free text; `target` is a closed enum, stored in clear. `input_hash` (clarified during `/speckit-checklist`, finding CHK007 — resolving Principle III's own "full input hash" wording precisely) is a hash of exactly the `situation` map `contracts/llm-escalation-port.md`'s adapter behaviour receives (which is itself derived from the triggering `%Assessment{}` + the gate's own `cause`) — the same value, whether `target` is `:operator` or `:llm`, so the diary carries one consistent notion of "what was escalated" regardless of which target eventually resolves it. |
| `:escalation_resolved` | `{"escalation_id", "target", "resolution_kind", "output", "prompt_id", "model", "model_version", "decision_delta_hash"}` | **Named exception (R-4)**: when `target == :llm` and `resolution_kind == :answered`, `output` is the ACTUAL LLM output value, in cleartext, after passing `PIIGuard` — not a hash. Every other combination (operator-answered, or any `:fallback` case) is standard hash-only, and `prompt_id`/`model`/`model_version` are `nil` (only meaningful for an LLM target — resolved during `/speckit-checklist`, finding CHK007's own broader prompt: the constitution's full itemized list — trigger, prompt id, model, version, full input hash, full output, decision delta — is now fully accounted for: `trigger`/`input_hash` live on the `:escalated` entry above, since they're known before either target resolves; `prompt_id`/`model`/`model_version`/`output`/`decision_delta_hash` live here, since they're only known once an LLM target actually answers). `decision_delta_hash` hashes the diff between the loan's state immediately before and after this resolution's follow-on `:decision` is applied. This is the ONE diary entry type in the entire system that ever stores non-hashed tool-adjacent content (`output`), and it exists precisely so a human auditor can read what an LLM actually said without needing a separate vault lookup — a deliberate, narrow, documented exception (see `research.md` R-4), not an inconsistency. **Scope, confirmed against the constitution's literal text (`/speckit-analyze` finding C1): `assess_via_llm`'s OWN `:tool_invoked`/`:tool_completed` diary pair (the standard tool-invocation bookkeeping `tool-behaviour.md` invariant 4 governs) stays hash-only, unchanged — this exception applies ONLY to this new, separate, domain-level `:escalation_resolved` entry. The constitution's actual hash-only text (Principle IV) is scoped to PII specifically ("the diary holds hashes/pointers, not the PII itself"), not to all non-PII content broadly; Principle VIII states no blanket hash-only rule at all — that convention lives in `tool-behaviour.md`, a spec-001 contract, and is left fully intact here.** |
| `:escalation_failed` | `{"escalation_id", "target", "failure_mode", "reason_hash", "prompt_id", "model", "model_version"}` | Standard hash-only. Used both for the four defined LLM failure modes AND for a PIIGuard rejection of what would have been cleartext output (R-4's fail-closed path) — `failure_mode` distinguishes `:timeout \| :malformed_output \| :refusal \| :low_confidence \| :pii_violation`. `prompt_id`/`model`/`model_version` are populated when known (e.g. a `:low_confidence` response DID come from a specific model) and `nil` when not (e.g. `:timeout` — no response ever arrived to attribute). |

## State extension

No new fields on `%LoanActor.State{}` itself. `state.context` (already open-ended, PII-free by
`PIIGuard`) gains conventionally-named keys for the incrementally-maintained facts R-3 adopted
(e.g. `context["goal_created_at"][goal_id]`) — these are ordinary `state.context` entries, using
the existing mutation surface (`State`'s own module, not a new one), not a schema change to the
struct itself.

## Relationships

```
Loop pass (reactive/periodic/planning)
  → assess_loan tool → %Assessment{} → :assessment diary entry
  → evaluate_gate tool (per matched gate pack) → %Gate{} evaluation → :gate_evaluated diary entry
      ├─ :pass/:fail  → %Decision{} → :decision diary entry → transition_state/satisfy_goal (existing tools)
      └─ :indeterminate → %Escalation{} → :escalated diary entry
            ├─ target :operator → request_operator_approval (existing tool, unchanged)
            └─ target :llm       → assess_via_llm (new tool)
                                       ├─ success → :escalation_resolved (cleartext output, R-4)
                                       └─ failure → :escalation_failed (one of 4 modes)
```

**Atomicity is inherited, not reinvented** (resolved during `/speckit-checklist`, finding
CHK003): every arrow in the diagram above executes inside the SAME atomicity boundary the
foundation's own reactive pipeline already provides (constitution Principle IV: every
state-mutating handler appends its diary entry within the same logical transaction). A crash
between `evaluate_gate` returning an outcome and the corresponding `:decision`/`:escalated`
entry being durably appended is not a new failure window this feature introduces — it is the
SAME window every foundation tool invocation already has, already covered by the existing
crash-recovery guarantee (rehydration replays only what was durably appended; anything not yet
appended when the crash happened simply did not happen, and the next loop pass re-derives it
fresh from the then-current state). No new transactional mechanism is needed here.
