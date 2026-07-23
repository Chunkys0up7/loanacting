# Loan-as-Actor

The loan is the agent. A long-running supervised process on the BEAM with its own diary, goals, and 30-year lifespan — surfaced through CopilotKit over AG-UI.

## Run it

The foundation (spec 001) is implemented. **Follow
[`specs/001-loan-actor-foundation/quickstart.md`](specs/001-loan-actor-foundation/quickstart.md)**
to install dependencies, boot the backend + frontend, and run the test suite —
it's the single source of truth for local setup, and its own "Useful commands"
and "Smoke checklist" sections are what CI checks (`mix test.smoke`) mirror.

## Understand it first

1. **Read [`CLAUDE.md`](CLAUDE.md)** — the standing operating contract for every session.
2. **Read [`loan-as-actor.html`](loan-as-actor.html)** — the long-form architectural rationale.
3. **Read [`.specify/memory/constitution.md`](.specify/memory/constitution.md)** — the non-negotiable principles.

## Extending the spec

Every change — however small — is an intent through the full spec-kit pipeline
(CLAUDE.md §3), not a direct code edit:

4. **Run [`SETUP.md`](SETUP.md)** if spec-kit itself isn't installed yet (`uv`, `specify-cli`, `specify init`).
5. **Open the foundation spec**: [`specs/001-loan-actor-foundation/`](specs/001-loan-actor-foundation/)
6. **Check the status ledger in [`specs/001-loan-actor-foundation/tasks.md`](specs/001-loan-actor-foundation/tasks.md)** for what's done and what's next.
7. New requirements start at `intents/NNNN-<slug>.md`, then `/speckit-specify` onward (CLAUDE.md §3).

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

The three prime directives (CLAUDE.md §0):

- **PD-1 — Specs only, no vibe coding.** No code without a spec, no spec without an intent. See CLAUDE.md §3.
- **PD-2 — Test-driven.** Tests first or same commit; taxonomic coverage; factories only. See CLAUDE.md §4 and constitution Principle V.
- **PD-3 — Tools + skills execution.** Every self-initiated agent function is a registered tool; when-to-use knowledge is skill-pack content. See CLAUDE.md §5 and constitution Principle VIII.

Also load-bearing:

- **No LLM calls in foundation.** Enforced by a Credo check and a grep test.
- **PII never enters the diary or the UI stream.** Enforced by `LoanActor.PIIGuard` before hashing and before emission.
- **CopilotKit is the only UI layer.** See `.claude/skills/copilotkit/` for the playbook.
