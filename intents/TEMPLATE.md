---
id: NNNN
slug: short-kebab-slug
title: One-sentence title in plain language
status: Draft           # Draft | Ready | Specified | Implemented | Closed | Abandoned | Superseded
author: <name>
created: YYYY-MM-DD
supersedes: []          # list of intent ids, if any
depends_on: []          # list of intent ids
execution_spec: null    # path to specs/<feature>/spec.md once /speckit.specify has run
---

# Intent NNNN — <title>

## Problem

> What is broken, missing, or suboptimal *today*? Plain language. Describe symptoms, not solutions. If you find yourself naming a technology, library, or design pattern in this section — stop and rewrite.

## Outcome

> What does "done" look like from the perspective of the user (loan officer, borrower, regulator, secondary-market buyer, etc.)? Be concrete and measurable. Avoid implementation detail.

Example shape: *"A loan in underwriting can detect a missing income document, request it from the borrower via the CopilotKit interface, and resume processing autonomously when the document arrives — without an operator queue entry."*

## Non-goals

> Things people might reasonably assume are in scope but explicitly are not. Each non-goal is a "no" in writing, which is more valuable than the corresponding "yes".

- Non-goal 1
- Non-goal 2

## Constraints

> Architectural invariants this intent must not violate. Quote the relevant rule from CLAUDE.md or a prior intent.

- **Loan-is-the-actor**: the loan itself drives this behavior; no orchestrator agent dispatches it.
- **Deterministic-first**: any LLM use is an escalation with documented cause.
- **Immutable diary**: every decision/input/output is appended to the loan's diary.
- **Three-loop harness**: classify which loop this work lives in (reactive / periodic / planning).
- *...add others as needed.*

## Success criteria

> Testable conditions. Phrase as "Given … When … Then …" or as assertions. These will become `/speckit.checklist` items.

- [ ] Criterion 1 (testable)
- [ ] Criterion 2 (testable)
- [ ] Criterion 3 (testable)

## Open questions

> Unknowns the author cannot resolve alone. `/speckit.clarify` will work through these.

- Q1: …
- Q2: …

## Dependencies

### Intent dependencies
- (intent ids this depends on, with one-line "why")

### External dependencies (new)
> Any new package, service, or vendor that did not exist in the repo before. New deps are a yellow flag — justify each.

- Package/service: justification

### External dependencies (existing)
> Existing deps this intent leans on heavily. Listed so reviewers see the surface area.

- …

## Risks

> What could go wrong if we build this and we're wrong? What's the cheapest way to learn we're wrong before we commit?

- Risk: mitigation / kill-criterion

## Notes

> Free-form. Discussion log, links to conversations, sketches. Cleaned up before moving to `Ready`.
