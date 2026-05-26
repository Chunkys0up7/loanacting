# Spec-to-Plan Validation Gate

> **Purpose**: This checklist blocks the transition from `/speckit.specify` (product spec) to `/speckit.plan` (tech spec). Every item must pass before the agent proceeds to technical planning. This prevents the #1 failure mode in SDD: vague specs producing vague plans producing broken task breakdowns.
>
> **When to run**: After the product spec is complete and `/speckit.clarify` has been run at least once.
>
> **How to run**: The agent (or a human reviewer) walks through each section and checks every item. Any ❌ blocks the gate. The spec must be revised until all items are ✅.

---

## Gate 1: Structural Completeness

> Does the spec have all required sections with real content (not just placeholders)?

- [ ] **Problem statement** exists and describes a real user pain (not a technical gap)
- [ ] **At least 2 user personas** defined with role, need, current pain, and success definition
- [ ] **At least 3 user stories** with acceptance criteria in Given/When/Then format
- [ ] **Functional requirements** table exists with IDs, priorities, and testability confirmation
- [ ] **Non-functional requirements** exist for performance, security, and at least one other dimension
- [ ] **Domain model** with entities, relationships, and any state transitions
- [ ] **At least 2 user scenarios** (one happy path, one error/edge case)
- [ ] **Success criteria** with measurable targets and measurement methods
- [ ] **Scope boundaries** — both in-scope and out-of-scope are explicitly stated
- [ ] **Assumptions** are listed with impact-if-wrong assessment

**Result**: [ ] PASS / [ ] FAIL — Revise sections: _______________

---

## Gate 2: Tech-Free Verification

> The product spec must contain ZERO implementation details. This gate catches tech bleed.

Scan the entire spec for violations. Any of the following found in the product spec is a ❌:

- [ ] No programming language names (Python, TypeScript, Java, etc.)
- [ ] No framework names (React, FastAPI, Django, Express, etc.)
- [ ] No database engine names (PostgreSQL, MongoDB, Redis, etc.)
- [ ] No cloud service names (AWS, S3, Lambda, ECS, etc.)
- [ ] No UI component library names (Salt DS, Material UI, Tailwind, etc.)
- [ ] No API design terminology (REST, GraphQL, gRPC, endpoint, route)
- [ ] No data type specifications (VARCHAR, INTEGER, JSON, UUID)
- [ ] No CSS/styling details (colors, fonts, pixel sizes, breakpoints)
- [ ] No architecture pattern names (microservices, monolith, CQRS, event-driven)
- [ ] No DevOps tooling (Docker, Kubernetes, Terraform, GitHub Actions)

**Common violations that look innocent but aren't**:
- "The system should store data in a table" → ❌ (implies relational DB)
- "Users click a button" → ✅ (describes user action, not implementation)
- "The API returns a JSON response" → ❌ (implementation detail)
- "The system responds with the requested information" → ✅

**Result**: [ ] PASS / [ ] FAIL — Violations found: _______________

---

## Gate 3: Requirement Quality

> Every requirement must be specific, testable, and unambiguous.

### 3.1 No Orphan Requirements

- [ ] Every functional requirement maps to at least one user story
- [ ] Every user story maps to at least one functional requirement
- [ ] No requirement exists without a clear user benefit

### 3.2 No Untestable Requirements

Scan for vague language that cannot be verified:

- [ ] No use of "should" (must be "must" or "may")
- [ ] No use of "intuitive" without measurable criteria (replace with specific usability metric)
- [ ] No use of "fast" or "responsive" without numeric targets
- [ ] No use of "user-friendly" without testable acceptance criteria
- [ ] No use of "seamless" without defined success/failure conditions
- [ ] No use of "secure" without specific security requirements
- [ ] No use of "scalable" without concrete load targets
- [ ] No use of "etc." or "and so on" (must enumerate explicitly)

### 3.3 No Ambiguous Scope

- [ ] Every `[NEEDS CLARIFICATION]` marker has been resolved (or explicitly deferred to plan phase with rationale)
- [ ] No requirement can be interpreted two different ways by two reasonable people
- [ ] Out-of-scope items have explicit reasons (not just "later")

**Result**: [ ] PASS / [ ] FAIL — Issues found: _______________

---

## Gate 4: Acceptance Criteria Coverage

> Can we build a test suite from the acceptance criteria alone?

- [ ] Every P1 user story has ≥ 2 acceptance criteria
- [ ] Every P2 user story has ≥ 1 acceptance criteria
- [ ] Acceptance criteria follow Given/When/Then format consistently
- [ ] At least one error/negative scenario exists per user story
- [ ] Each user story has an "independent test" description explaining how it can be verified in isolation
- [ ] Success criteria are quantified (specific numbers, not "improved" or "better")

**Result**: [ ] PASS / [ ] FAIL — Stories missing criteria: _______________

---

## Gate 5: Domain Model Coherence

> Does the domain model support all the user stories?

- [ ] Every entity mentioned in user stories appears in the domain model
- [ ] Every relationship in the domain model is needed by at least one user story
- [ ] State transitions (if any) cover all paths mentioned in user scenarios
- [ ] No entity has attributes that aren't referenced by any requirement
- [ ] Entity names are consistent throughout the document (no aliases without definition)

**Result**: [ ] PASS / [ ] FAIL — Gaps found: _______________

---

## Gate 6: Constitution Alignment

> Does the spec respect the project constitution?

- [ ] Security requirements in the spec are compatible with constitution §2.1
- [ ] Quality requirements are compatible with constitution §2.2
- [ ] No assumption in the spec contradicts a constitution principle
- [ ] Non-functional requirements meet or exceed constitution minimums
- [ ] Scope does not include anything in the constitution's "never" list (§2.4)

**Result**: [ ] PASS / [ ] FAIL — Conflicts found: _______________

---

## Gate 7: Completeness Self-Test

> The "unknown unknowns" check. Surface things the spec might be missing.

- [ ] **What happens when the system is empty?** (First-run experience is described or explicitly deferred)
- [ ] **What happens when two users do the same thing at the same time?** (Concurrency is addressed or explicitly deferred)
- [ ] **What happens when an external dependency is down?** (Failure modes are described)
- [ ] **What happens when the user does something unexpected?** (At least one error scenario per primary workflow)
- [ ] **What does the user see while waiting?** (Loading states are described or explicitly deferred)
- [ ] **What data is shown when there's no data?** (Empty states are described or explicitly deferred)
- [ ] **Who can see what?** (Access control is described, even if high-level)
- [ ] **What gets logged/audited?** (Audit requirements are addressed)

**Result**: [ ] PASS / [ ] FAIL — Missing areas: _______________

---

## Final Verdict

| Gate | Result |
|------|--------|
| 1. Structural Completeness | [ ] PASS / [ ] FAIL |
| 2. Tech-Free Verification | [ ] PASS / [ ] FAIL |
| 3. Requirement Quality | [ ] PASS / [ ] FAIL |
| 4. Acceptance Criteria Coverage | [ ] PASS / [ ] FAIL |
| 5. Domain Model Coherence | [ ] PASS / [ ] FAIL |
| 6. Constitution Alignment | [ ] PASS / [ ] FAIL |
| 7. Completeness Self-Test | [ ] PASS / [ ] FAIL |

### Decision

- [ ] **✅ GATE PASSED** — Proceed to `/speckit.plan` with `03-tech-spec-template.md`
- [ ] **❌ GATE FAILED** — Return to product spec. Specific revisions required:
  1. [Revision needed]
  2. [Revision needed]
  3. [Revision needed]

**Reviewed by**: [Name/Agent] | **Date**: [Date]
