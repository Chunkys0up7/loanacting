---
name: speckit
description: Spec-driven development with GitHub spec-kit. Use when the user wants to bootstrap a new feature or project from a spec; mentions "spec-kit", "speckit", or any /speckit.* slash command; wants to write a constitution / product spec / tech plan / task breakdown; or wants to run `specify init`, `/speckit.specify`, `/speckit.plan`, `/speckit.tasks`, `/speckit.implement`, `/speckit.clarify`, `/speckit.analyze`, `/speckit.checklist`, or `/speckit.taskstoissues`. Covers both driving the CLI/slash workflow AND writing the spec content itself.
---

# Spec-Kit (Speckit)

Spec-driven development: specifications are the **executable blueprint**, AI agents translate them into code. From GitHub: <https://github.com/github/spec-kit>.

## When to use which command

```
   specify init                      ← bootstrap a project (one-time)
        │
        ▼
   /speckit.constitution             ← define principles & guardrails (once per project)
        │
        ▼
   /speckit.specify "<feature>"      ← WHAT and WHY, no tech (per feature)
        │
        ├─► /speckit.clarify          ← resolve ambiguities (optional, recommended)
        ▼
   /speckit.plan                     ← HOW: architecture, stack, contracts
        │
        ├─► /speckit.analyze          ← cross-artifact consistency check (optional)
        ▼
   /speckit.tasks                    ← ordered, dependency-aware task list
        │
        ├─► /speckit.checklist        ← quality gates (optional)
        ├─► /speckit.taskstoissues    ← push to GitHub issues (optional)
        ▼
   /speckit.implement                ← agent executes the task list
```

## Phase 0 — Install & init

Prereqs: Python 3.11+, Git, [`uv`](https://docs.astral.sh/uv/).

```bash
# Install the CLI
uv tool install specify-cli --from git+https://github.com/github/spec-kit.git

# New project
specify init my-project --integration claude
cd my-project

# Existing project (current dir)
specify init . --here --integration claude
# Use --force if non-empty
```

`--integration` accepts `claude`, `copilot`, `gemini`, `cursor`, `codex`, `qwen`, etc. See `specify integration list`.

Skills-mode (puts commands as skills rather than slash commands): `--integration-options="--skills"`.

After init the project gains a `.specify/` directory and `/speckit.*` slash commands inside the configured AI agent.

## Phase 1 — Constitution

`/speckit.constitution` writes `.specify/memory/constitution.md`. It's the project's standing instructions for every future spec/plan: quality bar, testing, UX consistency, performance, security, dependencies.

**Good prompt shape:**
> Create principles focused on: code quality (typed, lint-clean), testing (real DB integration tests, no mocks at boundaries), UX consistency (design tokens, accessibility AA), performance (p95 < 300ms), and dependency hygiene (no copyleft).

See [references/constitution-template.md](references/constitution-template.md) for a full template.

## Phase 2 — Specify (the WHAT)

`/speckit.specify "<feature description>"` creates `specs/<feature-name>/spec.md`. **Focus on user value and behavior, not technology.** Mention frameworks only if the user already constrained them.

Prompt shape: domain → users → core flows → success criteria → out-of-scope.

See [references/product-spec-template.md](references/product-spec-template.md).

## Phase 2.5 — Clarify (optional but high-leverage)

`/speckit.clarify` re-reads `spec.md` and asks structured questions about ambiguities. Run it before `/speckit.plan` — fixing ambiguity at spec time is much cheaper than at task time.

## Phase 3 — Plan (the HOW)

`/speckit.plan` reads `spec.md` + `constitution.md` and produces:
- `plan.md` — architecture, key decisions, trade-offs
- `data-model.md` — entities, relationships
- `api-spec.json` — REST contracts (if applicable)
- `research.md` — investigation notes
- `quickstart.md` — minimal "hello world" of the feature

See [references/tech-spec-template.md](references/tech-spec-template.md).

**Audit step (recommended):** after `/speckit.plan` finishes, ask the agent to *audit* the plan — does the task order match the dependency graph? Are there hidden assumptions? Spec-kit's authors flag that Claude Code in particular tends to over-eagerly add components; push back on anything that wasn't asked for.

## Phase 3.5 — Analyze (optional)

`/speckit.analyze` cross-checks spec ↔ plan ↔ constitution for inconsistencies (spec says "no auth required" but plan adds OAuth, etc.).

## Phase 4 — Tasks

`/speckit.tasks` reads spec + plan and writes `tasks.md` with ordered, dependency-marked work items. Tasks tagged for parallel execution are marked `[P]` so `/speckit.implement` can fan them out.

See [references/task-instruction-template.md](references/task-instruction-template.md).

## Phase 4.5 — Checklist & Issues (optional)

- `/speckit.checklist` — quality-gate checklists tied to constitution principles (e.g., "every API has tests", "all forms have a11y labels").
- `/speckit.taskstoissues` — push the task list to GitHub Issues with milestones/labels.

## Phase 5 — Implement

`/speckit.implement` walks the task list in dependency order, parallelizing `[P]` tasks. Keep the constitution open; the agent rechecks it on each task.

**Operate it like a build:** review each task's diff before letting it proceed to dependents. Failing checklists are blockers, not warnings.

## Generated file layout

```
.specify/
├── memory/constitution.md
├── scripts/bash/                  # check-prerequisites, create-new-feature, setup-plan, setup-tasks
└── templates/
    ├── plan-template.md
    ├── spec-template.md
    ├── tasks-template.md
    └── overrides/                 # project-local customizations of any template
specs/<feature>/
├── spec.md
├── plan.md
├── tasks.md
├── data-model.md
├── api-spec.json
├── quickstart.md
└── research.md
```

To customize templates project-wide, drop files into `.specify/templates/overrides/` — they win over the defaults shipped by the CLI.

## Workflow heuristics

- **One feature per `specs/<name>/` folder.** Don't merge unrelated features.
- **Constitution is sacred** — edit it deliberately, never mid-feature without good reason. It's the contract.
- **Clarify before planning, analyze before tasks, checklist before implement.** Each phase catches a different class of error.
- **Don't skip `/speckit.tasks`** even for small changes — the dependency ordering is what makes `/speckit.implement` safe.
- **Brownfield**: run `specify init . --here` in an existing repo. Write a constitution that captures the *current* conventions (read the code first). Then spec features normally.

## Reference files

- [references/usage-guide.md](references/usage-guide.md) — Detailed walkthrough of each command with examples
- [references/constitution-template.md](references/constitution-template.md) — Skeleton for `/speckit.constitution`
- [references/product-spec-template.md](references/product-spec-template.md) — Skeleton for `/speckit.specify`
- [references/tech-spec-template.md](references/tech-spec-template.md) — Skeleton for `/speckit.plan`
- [references/task-instruction-template.md](references/task-instruction-template.md) — Task list format `/speckit.tasks` produces
- [references/spec-to-plan-gate.md](references/spec-to-plan-gate.md) — Quality bar a spec must clear before planning

## Authoritative URLs

- Spec-kit GitHub: <https://github.com/github/spec-kit>
- README (workflow, commands, integrations): <https://github.com/github/spec-kit/blob/main/README.md>
- `uv` installer docs: <https://docs.astral.sh/uv/>
