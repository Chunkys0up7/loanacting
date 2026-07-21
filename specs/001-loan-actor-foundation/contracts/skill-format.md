# Contract — Skill pack format

*(Added by intent 0004; supersedes the single-file `%Procedure{}` stub.)* Operating
knowledge loads as versioned markdown **packs** the actor trigger-matches at runtime.
Which tools *exist* is code (the registry); when to *use* them is content (skills) —
constitution Principles VI and VIII.

## Layout

```
priv/skills/<id>/                  # id: NNNN-kebab-slug, e.g. 0001-demo-document-request
├── SKILL.md                       # manifest — REQUIRED
└── references/                    # optional supporting files (markdown), any depth
    └── *.md
```

## `SKILL.md` front-matter (restricted grammar — HARD CAP)

```markdown
---
name: demo-document-request
version: 1.0.0
description: When the loan is awaiting documents and has an open document goal, request the document from the operator.
tools_required: [request_document]
---

# Body: markdown the actor (and regulators) read. Foundation does not interpret the body.
```

- Grammar: `key: value` lines and `[a, b, c]` lists only, between `---` fences. No nested
  maps, no multi-line scalars, no YAML anchors. Extending the grammar requires an amendment
  intent (same discipline as the tool JSON-schema cap).
- Required keys: `name`, `version` (semver string), `description`, `tools_required`
  (may be `[]`).
- `description` **is the trigger** (loan-as-actor.html "every note declares its own
  trigger"): foundation matching is normalized substring/keyword matching against the
  loan's match-text `{status, latest event type, open goal descriptions}`. Intentionally
  naive; intent 0003 owns real assessment-driven selection.

## Loader invariants

1. **Load-time validation** — a pack missing required keys, with an unparsable
   front-matter, or whose `tools_required` names a tool absent from the registry is
   **rejected** (skipped with a logged reason). Rejected packs never trigger.
2. **Reload** — `Skill.Loader.reload/0` picks up added/changed/removed packs without a
   node restart (FT-044 test: add pack → reload → matches).
3. **Activation is diary-logged** — matching a skill during a loop pass appends
   `:skill_activated` (payload: skill id, version, trigger-text hash).
4. **Versioned in git** — packs live under `priv/skills/` in the repo; every pack change
   is reviewable content, linked to the test that proves it fires (Principle VI).
5. **No PII in packs** — packs are static content; the PII corpus test greps `priv/skills/`.

## Foundation demo pack

`priv/skills/0001-demo-document-request/` — triggers on `:awaiting_documents` + open
document goal; `tools_required: [request_document]`; includes one `references/` file to
prove multi-file loading. Exercised by SC-014.

## Test pins

- `apps/loan_actor/test/skill/loader_test.exs` — load/reload/match/reject cases against
  fixture packs in `apps/loan_actor/test/fixtures/skills/` (valid, bad front-matter,
  unresolvable `tools_required`, multi-file).
- Factory: `LoanActor.Factory.skill/1` + on-disk pack writer (test-data-forge).
