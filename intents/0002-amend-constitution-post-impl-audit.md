---
id: "0002"
slug: amend-constitution-post-impl-audit
title: Add a mandatory post-implementation audit cycle to the constitution
status: Specified
author: cameron
created: 2026-05-26
specified: 2026-05-26
supersedes: []
depends_on: ["0001"]
execution_spec: "(constitution diff — amendments are their own spec)"
amends: ".specify/memory/constitution.md"
---

# Intent 0002 — Amend constitution with post-implementation audit cycle

## Problem

The current constitution and CLAUDE.md describe the **authoring** workflow (intent → spec → plan → tasks → checklist → implement) but do not formalize what happens **after** `/speckit-implement` finishes. In practice, the discipline I want for every closed spec is:

1. **Audit** — independent verification that the code does what the spec claimed.
2. **Spec report** — a written, committed record of what was implemented, deviations from the spec, follow-ups.
3. **Test creation closure** — confirmation that every applicable taxonomy category has a test, mapped to spec SCs.
4. **Test data generation closure** — confirmation that factories cover every entity/scenario the spec introduced.

Today these happen ad-hoc or implicitly inside PR reviews, which means they slip when pressure rises — exactly when discipline matters most. Without formalization, "spec complete" means different things to different sessions.

## Outcome

Every spec has a **closeout phase** that produces three new committed artifacts in its `specs/NNN-slug/` directory and one updated checklist. After closeout:

- An auditor (human or agent) can verify spec → code in under one sitting by reading `audit.md`.
- A future operator can read `report.md` and understand what shipped, what changed mid-flight, and what was deferred.
- The factories + tests can be inspected without spelunking through PRs.
- The spec's status moves from `Specified` → `Implemented` → **`Closed`** (new status).

## Non-goals

- Not introducing a new CI tool. The audit and report are markdown artifacts; CI continues to enforce tests and checklists as before.
- Not gating individual `FT-*` task PRs on the closeout artifacts. Those land first; closeout happens once all tasks for the spec are merged.
- Not changing the test taxonomy or anti-vibe rules — only formalizing when their evidence gets reported.
- Not amending intent 0001 (foundation) retroactively; this rule applies prospectively. Foundation gets the closeout cycle when intent 0001's implementation completes.

## Constraints

- **Constitution amendment**: MINOR semver bump (v1.0.0 → v1.1.0). New section added; no existing principle redefined.
- **One-spec-one-commit (§6a) still holds**: this amendment is itself one commit.
- **The closeout produces ITS OWN commit** distinct from both the spec-authoring commit and the implementation PRs. Format: `audit(NNNN): <slug> — implementation closeout (v<spec-version>)`.
- **No code in the closeout commit** — only the three artifacts and the intent status change.

## Success criteria

- [ ] Constitution at `.specify/memory/constitution.md` bumped to v1.1.0 with a new section "Post-Implementation Audit Cycle" and an updated Sync Impact Report.
- [ ] CLAUDE.md gains a new section §6b mirroring the constitution change, with the same closeout phase definition and commit format.
- [ ] `intents/TEMPLATE.md` lifecycle table gains `Closed` as a status after `Implemented`.
- [ ] `intents/README.md` lifecycle table likewise.
- [ ] `specs/001-loan-actor-foundation/checklists/definition-of-done.md` gains a "Closeout" section listing the three artifacts the closeout commit must contain.
- [ ] Both the constitution and CLAUDE.md specify exactly three closeout artifacts: `audit.md`, `report.md`, `test-evidence.md`. Naming is fixed; not configurable per spec.
- [ ] The amendment is committed as one commit per §6a.

## Open questions

- **Q1**: Should `audit.md` be authored by a different operator/agent than the implementer? **Recommendation: yes, but not enforced by the constitution — recorded as a "should" not a "must" so solo work is still possible.**
- **Q2**: Should the closeout commit also create the next intent (e.g., a follow-up improvements intent)? **Recommendation: no — closeout is closeout. Follow-up intents are separate.**

(Q1, Q2 carry into the constitution wording as "SHOULD" clauses.)

## Dependencies

### Intent dependencies
- Depends on 0001 only because the closeout cycle will first be applied to 0001's implementation. The amendment itself is independent.

### External dependencies
- None.

## Risks

- **Risk**: Closeout artifacts become rubber-stamps copying spec.md verbatim. *Mitigation*: the constitution wording requires `audit.md` to list *deviations* and `report.md` to list *follow-ups* — both are useless if filled with boilerplate, which is detectable by review.
- **Risk**: Solo operators skip `audit.md` because there's no second party. *Mitigation*: the "SHOULD have a different author" wording lets a solo operator self-audit explicitly, but the artifact must still exist. An empty `audit.md` is a fail.

## Notes

The amendment is intentionally narrow: one new section, three named artifacts, one new commit format, one new lifecycle status. Not trying to design a full QA framework. Discipline through specificity.
