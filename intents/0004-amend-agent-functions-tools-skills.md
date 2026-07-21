---
id: "0004"
slug: amend-agent-functions-tools-skills
title: Agent functions are tool calls and skills — typed tools, content skill packs, glass-box ToolCall streaming
status: Specified
author: cameron
created: 2026-07-21
specified: 2026-07-21
supersedes: []
depends_on: ["0001"]
amends: "specs/001-loan-actor-foundation/* + .specify/memory/constitution.md"
execution_spec: "specs/001-loan-actor-foundation/ (amended in place)"
---

# Intent 0004 — Agent functions are tools and skills

## Problem

The foundation gives the loan actor loops, a diary, and a UI — but its *functions* have no
uniform shape. As currently specced, the planning loop emits an ad-hoc `CustomEvent
name="document_request"` (SC-012), HITL requests are a bespoke mechanism (FT-028), goal
operations are implicit Server internals, and operating knowledge is a single-file
`%Procedure{}` stub that cannot carry multi-file content (references, rule tables, linked
tests). Each future function would invent its own shape, its own diary convention, and its
own UI surfacing — or worse, none.

Meanwhile the AG-UI contract *forbids* the four ToolCall events
(`contracts/ag-ui-events.md`: "Adding any requires an amendment intent"), so tool activity
is invisible to the operator UI by construction, and the frontend contract test rejects the
event types that would carry it.

The operator directive (2026-07-21): **"the agent functions must be tool calls and skills."**

## Outcome

Every **self-initiated** function of the loan actor is a **tool**: a typed, JSON-schema'd,
individually invokable, deterministic function. Every invocation is diary-logged
(`:tool_invoked` → `:tool_completed`/`:tool_failed`) and streamed to the UI as the four
AG-UI ToolCall events (`ToolCallStart/Args/End/Result`) — a glass-box operator view of
everything the loan does on its own initiative.

Operating knowledge becomes **skills**: versioned markdown *packs* — a directory with a
`SKILL.md` manifest (front-matter: `name`, `version`, `description` acting as the trigger,
`tools_required`) plus optional reference files. The actor trigger-matches skills at
runtime; skills name the tools they need; the loader validates `tools_required` against the
registry at load time. Skill packs supersede the single-file `%Procedure{}` stub (never
built — FT-018b had not started).

Vocabulary is fixed project-wide:

- **tool** — typed invocable function (deterministic code; LLM tools arrive in 0003 behind
  the escalation gate).
- **skill** — versioned markdown content pack declaring its own trigger and required tools.
- **capability** — a future sub-agent process, spawned *via* a tool call (reconciles
  `loan-as-actor.html`'s "recruits capability" language with this model).

## Non-goals

- **No LLM tool selection.** Foundation stays zero-LLM (SC-009 intact). Skill matching is
  deterministic string matching; intent 0003 owns real assessment/escalation.
- **No semantic/embedding trigger matching.** Exact/substring matching only; documented as
  intentionally naive.
- **No dynamic loading of tool *code*.** Tools are compiled modules listed in config;
  only skill *content* is hot-reloadable.
- **No revision of merged work.** FT-001..FT-008 (diary track) are untouched;
  `Diary.Entry` already accepts the new entry types (open atom validation).
- **No public tool-invocation API.** See constraints.

## Constraints

- **Constitution bump is MINOR** (v1.1.0 → v1.2.0): a new Principle VIII is *added*;
  Principle VI's wording survives (skill packs are its satisfying mechanism); the four
  ToolCall events are *within* the "17 canonical events" architectural invariant, so no
  invariant changes → no MAJOR. Precedent: 0002 (v1.0.0 → v1.1.0, MINOR, added section).
- **PII rule (load-bearing).** `ToolCallArgs` streams cleartext to the browser. Tool args
  MUST pass `PIIGuard` **before** both diary hashing and AG-UI emission; only the redacted
  form leaves the actor. Without this, all-tools-in-UI violates the PII invariant.
- **The reactive event-ingestion pipeline is NOT a tool call.** Tools are the actor's
  self-initiated functions (periodic/planning loops + HITL emission). Inbound event
  processing stays the reactive pipeline (else every event double-logs and
  `NoDirectStateMutation` semantics blur). Encoded as a clarification.
- **Tools return effects; the Server applies them** through `State.transition/2` and the
  diary pipeline. Tools never mutate state directly.
- **Which-tools-exist = code; when-to-use = content.** The registry holds zero
  routing/trigger logic (Principle VI). Any matching logic in registry code is a
  constitution violation.
- **No new hex dependencies.** Hand-rolled JSON-schema subset (`type`, `required`, `enum`,
  `properties`) and a restricted `key: value` front-matter grammar; both caps pinned in the
  new contract docs — extending either requires an amendment.
- **One spec commit, no code** (§6a). Constitution and CLAUDE.md change together.

## Success criteria

- [ ] Constitution v1.2.0 committed: new Principle VIII (Agent Functions Are Tools and
      Skills, NON-NEGOTIABLE), closeout wording `priv/procedures/` → `priv/skills/`,
      Sync Impact Report updated; CLAUDE.md mirrored in the same commit.
- [ ] `spec.md` amended: FR-016 (tool registry + invocation logging), FR-017 (skill packs +
      trigger matching + load-time tools_required validation), FR-018 (all invocations
      stream as ToolCall events); FR-007 + SC-012 rewritten onto the `request_document`
      tool; SC-013 (tool → diary pair + 4 events, subscriber-observed < 250ms) and SC-014
      (demo pack trigger→load→tool executes) added.
- [ ] `data-model.md` amended: `%Tool.Spec{}` + `%Skill{}` replace `%Procedure{}`; diary
      entry types extended with `:tool_invoked`, `:tool_completed`, `:tool_failed`,
      `:skill_activated`.
- [ ] `contracts/ag-ui-events.md` amended: 4 ToolCall events specified (single-frame
      `ToolCallArgs`; HITL's deferred `ToolCallResult` documented); not-emitted list
      shrinks to `StepStarted, StepFinished, MessagesSnapshot, RawEvent`.
- [ ] `contracts/loan-actor-api.md` amended: tool invocation is internal-only; public
      surface unchanged.
- [ ] New `contracts/tool-behaviour.md` and `contracts/skill-format.md` authored
      (test-pinned like `diary-store-behaviour.md`).
- [ ] `plan.md` structure tree + Principle VIII constitution-check row updated.
- [ ] `tasks.md` amended: FT-041..FT-045 added; FT-018b superseded; FT-017/018/019/023/028/
      030/031/032/034/035/037/038 deltas applied; FT-019's wrong dep (FT-024 → FT-023) fixed;
      status ledger updated.
- [ ] All four checklists updated (ag-ui-contract +4 events; constitution-compliance
      +Principle VIII; definition-of-done path fix + tool/skill gates; test-coverage
      +tool/skill rows).
- [ ] `clarifications.md` records Q1–Q4 answers; `analysis.md` re-run records consistency.
- [ ] Uncommitted intent 0003 draft revised to tools+skills vocabulary (`depends_on` += 0004).

## Open questions

- **Q1**: Public `invoke_tool/3` on the Server API? *Recommendation: no — Principle I says
  capabilities are summoned BY the loan; external callers send events, not tool calls.*
- **Q2**: Args-schema validation depth — hand-rolled subset vs `ex_json_schema` dep?
  *Recommendation: hand-rolled subset (`type/required/enum/properties`), cap pinned in
  contract; no new dep for foundation.*
- **Q3**: Skill trigger-match semantics for foundation? *Recommendation: normalized
  substring/keyword match of `description` against `{status, event_type, open goal
  descriptions}`; intentionally naive, superseded by 0003.*
- **Q4**: Is inbound event ingestion a tool call? *Recommendation: no — reactive pipeline
  stays as specced; tools are self-initiated functions only.*

## Dependencies

### Intent dependencies
- **0001** — amends its execution spec in place; merged diary track (FT-001..008) is the
  substrate and is untouched.

### External dependencies (new)
- None. (Hand-rolled schema subset + front-matter grammar avoid `ex_json_schema` /
  `yaml_elixir`; if /speckit-clarify overturns Q2, the dep MUST be added here first.)

## Risks

- **Risk**: Tool ceremony (≥2 diary entries + 4 SSE frames per invocation) erodes NFR
  budgets on the hot path. *Mitigation*: FT-035 load test re-proves NFR-001/004 with tool
  logging on; it is the early-warning gate.
- **Risk**: The hand-rolled schema/front-matter subsets drift toward full parsers.
  *Mitigation*: caps pinned in `tool-behaviour.md` / `skill-format.md`; extension requires
  an amendment (mirrors 0003's DSL cap).
- **Risk**: Deferred HITL `ToolCallResult` breaks strict AG-UI clients. *Mitigation*:
  explicit contract wording + Playwright contract test exercises the deferred sequence.
- **Risk**: Naive trigger matching over-activates skills. *Mitigation*: acceptable at one
  demo pack; loader test asserts non-matching states activate nothing; 0003 owns real
  matching.

## Notes

Authored from the operator's 2026-07-21 plan-mode session (plan approved). This amendment
has no separate audit cycle: its tasks are spec 001's tasks, and the eventual `audit(0001)`
closeout verifies the amended spec at its amended version.
