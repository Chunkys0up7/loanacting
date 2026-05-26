# Checklist — AG-UI Contract Discipline

Applies to any PR that touches the AG-UI emission path (backend) or consumes it (frontend).

## Source of truth

- [ ] `specs/001-loan-actor-foundation/contracts/ag-ui-events.md` is updated FIRST when an event shape changes; code follows.
- [ ] Versioning rule respected: any breaking change to an existing event's shape requires a MAJOR bump in `spec.md`'s SC list and an amendment intent.

## Backend (`apps/loan_actor/lib/loan_actor/ag_ui/`)

- [ ] Every event the encoder produces is listed in `contracts/ag-ui-events.md`.
- [ ] No event type emitted that isn't in the "events emitted" table.
- [ ] Snapshot tests in `apps/loan_actor/test/ag_ui/encoder_test.exs` updated when an event's JSON shape changes.
- [ ] Ordering guarantee preserved: `CustomEvent diary_entry` precedes `StateDelta` for the same sequence.

## Frontend (`apps/web/src/`)

- [ ] `apps/web/src/types.ts` mirrors the contract document; no extra fields, no missing fields.
- [ ] `apps/web/src/lib/ag-ui-client.ts` rejects any event with an unknown `type` (strict by default).
- [ ] No code branches on event shapes that aren't documented in the contract.

## Cross-stack

- [ ] Cross-stack contract test (`apps/web/test/e2e/contract.spec.ts`) green.
- [ ] If the backend snapshot changes, the frontend types and the cross-stack test change in the same PR.

## HITL specifics

- [ ] HITL request and response shapes match `data-model.md` `HITLRequest` / `HITLResponse`.
- [ ] First-response-wins enforcement tested (FT-028 race test).
- [ ] Conflict surfaces as `CustomEvent name="hitl_conflict"`, not as a `RunError`.

## Subscriber resync

- [ ] Slow-consumer test (per research.md R-2) still green.
- [ ] On resync, the subscriber emits only `StateSnapshot` (NOT `MessagesSnapshot` — foundation has no message history).
