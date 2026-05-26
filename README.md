# Loan-as-Actor

The loan is the agent. A long-running supervised process on the BEAM with its own diary, goals, and 30-year lifespan — surfaced through CopilotKit over AG-UI.

## Start here

1. **Read [`CLAUDE.md`](CLAUDE.md)** — the standing operating contract for every session.
2. **Read [`loan-as-actor.html`](loan-as-actor.html)** — the long-form architectural rationale.
3. **Read [`.specify/memory/constitution.md`](.specify/memory/constitution.md)** — the non-negotiable principles.
4. **Run [`SETUP.md`](SETUP.md)** — installs `uv`, `specify-cli`, runs `specify init`, authors the constitution.

## Then build

5. **Open the foundation spec**: [`specs/001-loan-actor-foundation/`](specs/001-loan-actor-foundation/)
6. **Follow [`specs/001-loan-actor-foundation/quickstart.md`](specs/001-loan-actor-foundation/quickstart.md)** for the developer onboarding path.
7. **Execute tasks from [`specs/001-loan-actor-foundation/tasks.md`](specs/001-loan-actor-foundation/tasks.md)** — FT-001 onward.

## Repository layout

```
apps/
  loan_actor/      Elixir/OTP application — the loan actor, diary, AG-UI endpoint
  web/             Vite + React + CopilotKit SPA
config/            Mix env configs (config / dev / test / prod)
intents/           Human-authored intent specs (the WHY)
specs/             Spec-kit execution specs (the WHAT/HOW)
.specify/          Spec-kit working files (constitution, templates)
.claude/skills/    Installed skills (copilotkit, speckit, test-guardian, test-data-forge)
```

## Discipline

- **No code without specs. No specs without intent.** See CLAUDE.md §2.
- **Tests are part of the deliverable.** See CLAUDE.md §3 and the constitution Principle V.
- **No LLM calls in foundation.** Enforced by a Credo check and a grep test.
- **PII never enters the diary.** Enforced by `LoanActor.PIIGuard`.
- **CopilotKit is the only UI layer.** See `.claude/skills/copilotkit/` for the playbook.
