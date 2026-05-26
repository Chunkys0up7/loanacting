# Intents

Every change to Loan-as-Actor starts here. An **intent spec** is the human-authored statement of *why* a change should happen and *what* it should achieve, before spec-kit turns it into a formal execution spec.

## The pipeline

```
You write           Spec-kit derives                       Spec-kit derives
intents/NNNN.md ──► specs/<feature>/spec.md (via         ─►plan.md ─► tasks.md ─► code
                    /speckit-specify)
```

The intent file is **the source of truth for the WHY**. The execution spec answers *what* and *how*. They are both committed; neither replaces the other.

## Numbering

`NNNN-<kebab-slug>.md` where `NNNN` is a zero-padded sequential integer. Once assigned, never reuse — even if the intent is abandoned (mark it `Status: Abandoned` instead).

## What goes in an intent

Use [`TEMPLATE.md`](TEMPLATE.md). The required sections:

1. **Problem** — what's broken or missing, in plain language. No solution words.
2. **Outcome** — what "done" looks like from the user's perspective. Measurable.
3. **Non-goals** — things people might assume are in scope but aren't.
4. **Constraints** — invariants from the architecture (BEAM, immutable diary, deterministic-first, etc.) that this intent must not violate.
5. **Success criteria** — testable conditions. These become the basis for `/speckit-checklist`.
6. **Open questions** — unknowns to resolve in `/speckit-clarify`.
7. **Dependencies** — other intents this depends on, plus any new external dependencies (treat new deps as a flag for review).

## Lifecycle

| Status | Meaning |
|---|---|
| `Draft` | Being written. Not yet fed to spec-kit. |
| `Ready` | Author considers it complete enough to feed to `/speckit-specify`. |
| `Specified` | Execution spec exists at `specs/<feature>/spec.md`. Intent is frozen. |
| `Implemented` | All tasks closed, tests green, merged. |
| `Abandoned` | Decided not to do. Keep the file; document why. |
| `Superseded` | Replaced by a later intent. Link to it. |

Once an intent moves past `Ready`, **don't edit it** — write an amendment intent that references it.

## Why bother

Without intent specs, "why are we doing this" gets lost the moment the conversation that produced the spec ends. The intent is the artifact the spec-kit workflow can't generate for you — it requires human judgment about purpose.
