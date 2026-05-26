# Setup

Run these once, in order, before any other work in this repo. Subsequent sessions assume the setup is done.

## 0. Prerequisites

- Windows 11 (this machine) with PowerShell 7+
- Git (`git --version`)
- Python 3.11+ (`python --version`)
- Node 20+ (`node --version`)
- Erlang/OTP 26+ and Elixir 1.16+ — install via [asdf](https://asdf-vm.com/) or the [Erlang Solutions installer](https://www.erlang-solutions.com/downloads/) (defer until intent 0001 actually starts implementing)

## 1. Install `uv` (Python package/tool manager)

```powershell
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
```

Verify: `uv --version`

## 2. Install spec-kit CLI

```powershell
uv tool install specify-cli --from git+https://github.com/github/spec-kit.git
```

Verify: `specify --help`

## 3. Initialize spec-kit in this repo

```powershell
specify init . --here --integration claude --force
```

This creates `.specify/memory/`, `.specify/scripts/`, `.specify/templates/`, and registers the `/speckit-*` slash commands inside Claude Code.

**Do not edit `.specify/templates/` directly** — drop project-local customizations in `.specify/templates/overrides/` so they survive `specify` upgrades.

## 4. Author the constitution

In Claude Code, run:

```
/speckit-constitution
```

When it prompts for principles, **paste or summarize sections 1, 2, 3, 5, and 7 of CLAUDE.md** (architecture invariants, spec-driven discipline, testing discipline, anti-vibe rules, artifact discipline). The constitution at `.specify/memory/constitution.md` should mirror CLAUDE.md's load-bearing rules in spec-kit's format. Commit both.

## 5. Process the foundational intent

```
/speckit-specify  intents/0001-foundation-loan-as-actor.md
```

Produces `specs/foundation-loan-as-actor/spec.md`. Review it against the intent.

Then in order:

```
/speckit-clarify          # resolves Q1–Q7 from the intent
/speckit-plan             # produces plan.md, data-model.md, research.md, quickstart.md
/speckit-analyze          # consistency check across constitution + spec + plan
/speckit-tasks            # produces tasks.md
/speckit-checklist        # quality gates BEFORE implementation
```

Only then:

```
/speckit-implement
```

## 6. Scaffold the CopilotKit frontend (defer until plan.md says so)

When the plan calls for it:

```powershell
npx copilotkit@latest create
```

Drop the resulting app into `apps/web/` (or whatever path `plan.md` specifies).

## 7. Scaffold the BEAM backend (defer until plan.md says so)

When the plan calls for it:

```powershell
mix new apps/loan_actor --sup
```

(`--sup` because everything is supervised.)

## Verification checklist

After steps 1–5, this repo should contain:

```
CLAUDE.md
SETUP.md
loan-as-actor.html
.claude/
  settings.json
  skills/ (copilotkit, speckit, test-data-forge, test-guardian)
.specify/
  memory/constitution.md
  scripts/bash/
  templates/
intents/
  README.md
  TEMPLATE.md
  0001-foundation-loan-as-actor.md
specs/
  foundation-loan-as-actor/
    spec.md
    plan.md          (after /speckit-plan)
    tasks.md         (after /speckit-tasks)
    checklists/*.md  (after /speckit-checklist)
    data-model.md
    research.md
    quickstart.md
```

If any of those are missing after the corresponding step, do not proceed — fix the gap first.
