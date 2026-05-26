# Quickstart — Loan-Actor Foundation

Audience: a new developer joining the project after `/speckit-implement` has produced foundation code. This document is itself a CI artifact — the commands below run in CI and any drift fails the build.

## Prerequisites

- Erlang/OTP 26+ — `erl --version`
- Elixir 1.16+ — `elixir --version`
- Node 20+ — `node --version`
- npm 10+ — `npm --version`
- (Windows) PowerShell 7+

## One-time setup

```powershell
# Backend
mix local.hex --force
mix local.rebar --force
mix deps.get
mix deps.compile

# Database (single-node Mnesia)
mix loan_actor.init_mnesia

# Frontend
cd apps/web
npm ci
cd ../..
```

## Run the full test suite

```powershell
mix test --slowest 10            # backend (unit + integration + property-based)
mix dialyzer                     # static analysis
mix credo --strict               # linting + custom checks (loop tagging, no-LLM, no direct state mutation)
mix test.load                    # NFR load test (asserts NFR-001, NFR-002, NFR-003)
npm --prefix apps/web test       # frontend unit + contract tests
npm --prefix apps/web run e2e    # Playwright against a running backend (see below)
```

For e2e: start the backend in a separate shell first (`iex -S mix`), then run `npm run e2e`.

## Run the app

Shell A (backend):

```powershell
iex -S mix
# observe :ok = :mnesia.wait_for_tables([:loan_state, :loan_diary, :loan_idem], 5000)
```

Shell B (frontend):

```powershell
cd apps/web
npm run dev
```

Open <http://localhost:5173/loans/L-DEMO>. The first request spawns the demo loan.

## Smoke checklist (what "works" looks like)

1. Loan view renders within 1 second.
2. The diary feed shows a `:spawned` entry.
3. Click "Send :document_uploaded event"; within 1 second the diary feed shows the event and the state card updates to `documents_under_review`.
4. Refresh the browser; all diary entries reappear in order.
5. Click "Trigger HITL"; an approval card appears. Click "Approve"; diary shows `:operator_approval_granted` and state advances.
6. Stop the backend (`Ctrl-C` twice in shell A); the UI shows "reconnecting". Restart the backend; UI reconnects and shows the same diary.

If any step fails, the foundation is incomplete — open an intent describing the gap before patching.

## Useful commands

```powershell
mix loan_actor.spawn L-001                  # spawn a loan from the CLI
mix loan_actor.replay L-001                 # rebuild state from diary; assert byte-equal
mix loan_actor.verify_chain L-001           # tamper-detection scan
mix loan_actor.dump_diary L-001 --to dump.jsonl
```

## Project layout (TL;DR)

- `apps/loan_actor/` — the OTP application.
- `apps/web/` — the CopilotKit SPA.
- `specs/` — every feature spec; this foundation lives at `specs/001-loan-actor-foundation/`.
- `intents/` — every requirement as an intent doc; `intents/0001-…` is the foundation intent.
- `.specify/` — spec-kit working dir (constitution, templates, hooks).
- `.claude/skills/` — the four installed skills.

## What is *not* here (intentional)

- No business-domain rules (compliance, valuation, doc extraction, underwriting).
- No LLM calls. `mix test test/llm_absence_test.exs` proves this.
- No real authentication. `OPERATOR_ID` env or `x-operator-id` header.
- No multi-loan portfolio view. Single loan only.
- No Phoenix, no LiveView, no Next.js, no CopilotRuntime middle layer.

Anything missing? Write an intent.
