# Usage Guide: Spec Kit Input Template Package

## Overview

This guide walks you through using the template package to produce input artifacts that GitHub Spec Kit consumes. The goal is a seamless pipeline from product intent to agent-executable tasks.

---

## Step 0: Initialize Spec Kit

```bash
# Install Specify CLI
uv tool install specify-cli --from git+https://github.com/github/spec-kit.git@vX.Y.Z

# Initialize your project
specify init my-project --integration claude-code
cd my-project
```

---

## Step 1: Write the Constitution

**Template**: `01-constitution-template.md`
**Destination**: `.specify/memory/constitution.md`

```bash
cp 01-constitution-template.md .specify/memory/constitution.md
```

Fill in every section. The most critical sections are:

1. **Immutable Principles (§2)** — These are the rails that prevent the agent from going off-piste. The three-tier boundary system (Always / Ask First / Never) is the single highest-leverage thing you can write.

2. **Approved Technology Stack (§3)** — Be exhaustive. If it's not listed, the agent will either guess (bad) or ask (slow). Include version numbers.

3. **Commands (§4.2)** — Provide the exact, copy-paste-able commands. Not "run tests" but `npm test -- --coverage --watchAll=false`.

4. **Code Style (§4.4)** — One real code snippet that shows your style is worth more than any description.

**Tip**: Run `/speckit.constitution` after placing this file to let the agent validate and refine it.

---

## Step 2: Write the Product Spec

**Template**: `02-product-spec-template.md`
**Spec Kit command**: `/speckit.specify`

Two approaches:

### Approach A: Use the template directly as your `/speckit.specify` input

Paste the filled-in template content as your input to `/speckit.specify`. The agent will restructure it into Spec Kit's internal `spec.md` format.

### Approach B: Use the template to brief the agent

Use the template structure to write a comprehensive brief, then hand the brief to `/speckit.specify`:

```
/speckit.specify [paste your filled-in product spec content here]
```

The agent will generate `specs/[feature-name]/spec.md` from your input.

**Key discipline**: Keep it tech-free. The template has explicit reminders, but the biggest trap is "innocent" tech bleed like "store in a table" or "API returns JSON." Describe behaviors, not implementations.

### After writing: Run `/speckit.clarify`

This surfaces underspecified areas. It generates up to 5 targeted questions about ambiguous requirements. Answer them, and the agent updates the spec.

```
/speckit.clarify
```

Run it at least once. Twice is better.

---

## Step 3: Run the Validation Gate

**Template**: `04-spec-to-plan-gate.md`

Before moving to the plan phase, run through all 7 gates:

1. **Structural Completeness** — All sections present with real content
2. **Tech-Free Verification** — Zero implementation details in the spec
3. **Requirement Quality** — No vague language, every requirement testable
4. **Acceptance Criteria Coverage** — Every story has Given/When/Then criteria
5. **Domain Model Coherence** — Model supports all user stories
6. **Constitution Alignment** — Spec respects all constitution constraints
7. **Completeness Self-Test** — Edge cases, empty states, concurrency addressed

You can run this manually or ask the agent:

```
Review my spec against the validation gate checklist in 04-spec-to-plan-gate.md 
and report any failures.
```

**Do not proceed to `/speckit.plan` until all 7 gates pass.** This is the single most important quality control point in the entire workflow. A vague spec produces a vague plan produces broken tasks.

---

## Step 4: Write the Tech Spec

**Template**: `03-tech-spec-template.md`
**Spec Kit command**: `/speckit.plan`

Now you add the technical layer. Use the template to provide your tech stack and architecture choices as input to `/speckit.plan`:

```
/speckit.plan [paste your tech spec content — stack, architecture, 
constraints, file layout, testing strategy, etc.]
```

The agent will generate:
- `specs/[feature-name]/plan.md` — Technical implementation plan
- `specs/[feature-name]/research.md` — Research phase output
- `specs/[feature-name]/data-model.md` — Data model details
- `specs/[feature-name]/quickstart.md` — Key validation scenarios
- `specs/[feature-name]/contracts/` — API contract definitions

**Key discipline**: Every technology choice must reference the constitution. If you pick something not on the approved list, flag it explicitly.

---

## Step 5: Generate Tasks

**Spec Kit command**: `/speckit.tasks`

```
/speckit.tasks
```

No additional input needed — the agent reads `plan.md` and any generated design documents to produce `tasks.md` with:
- Tasks organized by user story
- Dependency ordering (models → services → endpoints)
- Parallel execution markers `[P]`
- File path specifications
- Checkpoint validation between phases

---

## Step 6: Create Task Instructions (Optional but Recommended)

**Template**: `05-task-instruction-template.md`

For complex or high-stakes tasks, create per-task instruction files:

```bash
mkdir -p docs/specs/task-instructions/
```

Create one file per complex task:
```
docs/specs/task-instructions/
├── task-1.2.1-db-schema.md
├── task-1.3.1-user-service.md
├── task-2.1.1-auth-endpoint.md
└── ...
```

Then update `tasks.md` to reference them:
```markdown
- [ ] Task 1.2.1: Set up database schema 
  → Instructions: `task-instructions/task-1.2.1-db-schema.md`
```

**When to create task instructions**:
- Any task tagged `[SECURITY-CRITICAL]`
- Any task that touches external integrations
- Any task with 3+ dependencies
- Any task that requires specific tools (MCPs, sub-agents, skills)
- Any task in a multi-repository project

**When you can skip them**:
- Simple scaffolding tasks
- Config-only tasks
- Tasks with < 2 files to create

---

## Step 7: Execute

**Spec Kit command**: `/speckit.implement`

```
/speckit.implement
```

The agent works through `tasks.md` sequentially (or in parallel where marked `[P]`), referencing task instructions where they exist.

---

## Context Management Between Phases

One of the most critical findings from the Spec Kit community: **clear the context window between phases.** The agent performs better when each phase gets a fresh start with only the relevant artifacts loaded.

| Phase Transition | What to Load | What to Clear |
|-----------------|-------------|--------------|
| Constitution → Specify | Constitution only | Everything else |
| Specify → Gate | Spec + constitution | Prior conversation |
| Gate → Plan | Spec + constitution | Gate results (they're pass/fail) |
| Plan → Tasks | Plan + spec + constitution | Prior conversation |
| Tasks → Implement | Tasks + task instructions + constitution | Spec + plan (already encoded in tasks) |

In practice, this means starting a new agent session (or at minimum, compacting context) at each phase transition.

---

## Anti-Patterns to Avoid

1. **Skipping the gate** — "The spec looks fine, let's just plan." This is how vague specs produce broken implementations. Always run the gate.

2. **Tech in the product spec** — Every time "PostgreSQL" appears in the product spec, the agent anchors on it prematurely and may ignore better alternatives during planning.

3. **One mega-prompt** — Don't try to do specify + plan + tasks in one shot. The "curse of instructions" means the agent will follow early instructions well and gradually ignore later ones.

4. **Empty constitution** — A missing or boilerplate constitution means the agent makes its own decisions about security, testing, and code style. Those decisions will be inconsistent across tasks.

5. **Skipping `/speckit.clarify`** — The biggest risk in any spec is unknown unknowns. `/speckit.clarify` surfaces them. Run it.

6. **Modifying the spec during implementation** — If you discover the spec is wrong during implementation, stop. Update the spec, re-run the gate, regenerate the plan and tasks. Don't patch around a broken spec.

---

## File Organization Summary

```
my-project/
├── .specify/
│   ├── memory/
│   │   └── constitution.md            ← From 01-constitution-template.md
│   ├── scripts/
│   └── templates/
├── specs/
│   └── [feature-name]/
│       ├── spec.md                    ← Generated by /speckit.specify
│       ├── plan.md                    ← Generated by /speckit.plan  
│       ├── tasks.md                   ← Generated by /speckit.tasks
│       ├── research.md                ← Generated by /speckit.plan
│       ├── data-model.md              ← Generated by /speckit.plan
│       ├── quickstart.md              ← Generated by /speckit.plan
│       ├── contracts/                 ← Generated by /speckit.plan
│       ├── checklists/
│       │   └── requirements.md        ← Generated by /speckit.specify
│       └── task-instructions/         ← From 05-task-instruction-template.md
│           ├── task-1.2.1-db-schema.md
│           ├── task-1.3.1-user-service.md
│           └── ...
└── src/
    └── ...                            ← Generated by /speckit.implement
```
