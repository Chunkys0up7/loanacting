# Test Evidence — Loan-Actor Foundation

Companion to `audit.md`. `test-guardian` and `test-data-forge` disciplines both invoked in
producing this document (taxonomy review + factory inventory below).

## 1. Coverage taxonomy → SCs → test files

Per-task taxonomy declarations are pinned in `tasks.md` itself (each task's own "Taxonomy:"
line) and, for most files, restated in the test file's own moduledoc. This table maps each
category to its Success Criteria and representative files — not exhaustive per file, but every
category has multiple independent, real (not vacuous) instances.

| Category | SCs it proves | Representative test files |
|---|---|---|
| **Happy** | All | Every test file below has a happy-path describe block; too many to list individually — this is the default case for every FT task. |
| **Boundary** | SC-007, SC-008 | `diary/entry_test.exs` (zero prev_hash for entry 0), `state_test.exs` (every status enum value), `event_test.exs`/`goal_test.exs` (field boundaries), `ag_ui/encoder_test.exs`/`ag_ui/subscriber_test.exs` (empty patch, slow-consumer resync), `tool/spec_test.exs` (empty schema/args), `skill/loader_test.exs` (empty skills dir), `large_diary_replay_test.exs` (1,000,000-entry scale). |
| **Error** | SC-008 | `state_transition_test.exs` (every illegal edge), `event_test.exs`/`goal_test.exs` (bad enums), `credo/*_test.exs` (each check's own violation fixtures), `web/router_test.exs`/`web/operator_plug_test.exs` (documented HTTP error codes), `hitl_test.exs` (respond to nonexistent request), `mix/tasks/*_test.exs` (each task's error path). |
| **Race** | SC-003 (concurrency angle) | `diary/mnesia_test.exs` (concurrent write), `idempotency_test.exs` (two-writers), `ag_ui/subscriber_test.exs`, `server_subscribe_test.exs`, `server_planning_test.exs` (planning-loop tool vs. inbound reactive event), `hitl_test.exs` (double-respond, first-wins). |
| **Replay** | SC-004, SC-007 | `replay_test.exs` (FT-009, pure fold, both stores), `server_property_test.exs` (FT-034, full live pipeline, 10,000 CI runs — **goal-content caveat, see audit.md §5**), `large_diary_replay_test.exs` (FT-036, 1M scale), `tools/set_goal_test.exs` (determinism), `server_heartbeat_test.exs`'s new crash-recovery regression test (the `:goal_set`/rehydrate fix from this audit). |
| **Security** | SC-009, SC-010 | `pii_guard_test.exs` (200-case corpus), `tool/pii_integration_test.exs`, `llm_absence_test.exs`, `credo/no_llm_test.exs`, `diary/file_test.exs`/`web/router_test.exs` (path-traversal/injection rejection), `tools/*` (PII order-of-operations), `mix/tasks/loan_actor.verify_chain_test.exs` (tamper detection). |
| **Contract** | SC-013, SC-014 | `diary/shared_behaviour_test.exs`, `tool/spec_test.exs`, `tool/registry_test.exs`, `tool/echo_shared_test.exs`, `skill/loader_test.exs`, `ag_ui/encoder_test.exs` (15 pinned snapshots), `apps/web/test/ag-ui-client.test.ts` (strict frontend rejection), `apps/web/test/e2e/contract.spec.ts` (live wire diff). |
| **Performance** | SC-001, SC-002, SC-007, SC-015 | `load/nfr_load_test.exs` (NFR-001/002 fail at full scale — see audit.md; NFR-003/004 pass), `load/large_diary_replay_test.exs` (SC-007, passes: 3.4s replay at 1M entries, 30s budget). |

Every applicable category has ≥1 real, executed test → **SC-008 holds.**

## 2. Factory inventory (`apps/loan_actor/test/support/factory.ex`)

Every entity in `data-model.md` has a factory, per test-data-forge discipline:

| Entity | Attrs builder | Validated builder | Invalid-variant catalog | Notes |
|---|---|---|---|---|
| `Diary.Entry` | `entry_attrs/1` | `entry/1`, `next_entry/2`, `chain/2` | `invalid_entry_variants/0` | Landed FT-006; `chain_with_event_types/2` + `legal_event_walk_gen/2` (StreamData) for replay properties. |
| `Goal` | `goal_attrs/1` | `goal/1` | `invalid_goal_variants/0` | |
| `State` | `state_attrs/1` | `state/1`, `state_at/2` | `invalid_state_variants/0` | |
| `Event` | `event_attrs/1` | `event/1` | `invalid_event_variants/0` | |
| `HITLRequest` | `hitl_request_attrs/1` | `hitl_request/1` | `invalid_hitl_request_variants/0` | |
| `HITLResponse` | `hitl_response_attrs/1` | `hitl_response/1` | `invalid_hitl_response_variants/0` | |
| `ToolSpec` *(0004)* | `tool_spec_attrs/1` | `tool_spec/1` | `invalid_tool_args_variants/0`, `invalid_tool_schema_variants/0` | Plus `valid_tool_args/1` (`:minimal`/`:full`), `tool_context/1`. |
| `Skill` *(0004)* | `skill_attrs/1` | `skill/1` | — (rejection paths covered by real on-disk fixture packs, `test/fixtures/skills/`, not a struct-level invalid-variant catalog) | Plus `write_skill_pack!/2` — the on-disk pack writer FT-037 asks for, used by `skill/loader_test.exs`, `server_heartbeat_test.exs`, and this audit's new regression test. |
| Tool-invocation diary pair *(0004)* | — | `tool_invocation_diary_pair/2` | — | Builds a linked `(:tool_invoked, :tool_completed\|:tool_failed)` entry pair for replay/contract tests without hand-rolling the chain. |

StreamData generators: `pii_clean_value_gen/0`, `pii_dirty_value_gen/0`, `legal_event_walk_gen/2`,
`entry_type_gen/0`, `chain_gen/1` — power the property-based tests (`state_transition_test.exs`,
`server_property_test.exs`, `replay_test.exs`, `pii_guard_test.exs`).

Every non-trivial test-data need across all 47 backend test files and 13 frontend test files
flows through this module or its frontend counterparts (component-level fixtures in each
`.test.tsx` file) — no hand-rolled fixtures found during this review.

## 3. Load-test actuals vs. NFR budgets

**Three measurements exist for the same test, same code, on three environments — reported all
three rather than picking one, since the divergence between Windows and both Linux environments
is itself the headline finding (`audit.md` §4 item 1):**

| NFR | Budget | Local (Windows dev machine) | CI (GitHub Linux runner, run `30020074937`) | Docker on same physical hardware (`hexpm/elixir:1.17.3-erlang-27.3.4.7`, exact `.tool-versions` match) |
|---|---|---|---|---|
| NFR-001 | p95 < 100ms @ 100 loans/10 ev-s/60s | **496.64ms p95 — fails** (`clarifications.md` Q17 Addendum 2) | **7.3ms p95 — passes**, ~68x faster (`total_events=57994, max_ms=367.06`) | **10.23ms p95 — passes**, ~48x faster than Windows on the SAME hardware (`total_events=57676, max_ms=359.7`) |
| NFR-002 | < 256MB @ same profile | Not independently measured (test aborts on NFR-001 first) | **179.59MB — passes** | **384,559,344 bytes (366.74MB) — FAILS**, `max_cases: 32` (this host's full core count) vs. CI's likely 2-4 — see audit.md Deviation 2, a new, separate, genuinely open question about whether NFR-002's flat budget is core-count-sensitive |
| NFR-003 | Crash-recovery < 1s @ ≤10,000 entries | Passes (elapsed_ms logged, always well under budget) | **6ms — passes** | **6ms — passes** |
| NFR-004 | AG-UI delivery < 250ms p95 | Passes | **0.0ms p95 — passes** (970 deliveries, 10 loans, 5s) | **0.0ms p95 — passes** |
| NFR-005 | ≥2 `DiaryStore` impls, zero external changes to swap | Passes (structural claim, not load-tested — correct, not a performance budget) | Same | Same |
| SC-007 | 1,000,000-entry replay < 30s | **3.4s measured, passes** (Mnesia backend; ~102s including seeding, not counted against the budget — see `large_diary_replay_test.exs`'s own moduledoc for why File was measured first and rejected) | Not yet re-run in CI (tagged `:slow`, nightly-only — `ci-nightly.yml`) | Not run (out of scope for this specific investigation) |

The Docker-on-same-hardware column is the decisive one: identical CPU, RAM, disks, and
Elixir/OTP patch version as the failing local run — the only variable is Windows-native vs.
Linux-in-a-container. A ~48x gap under those conditions isolates the cause to the OS/filesystem
layer, not hardware or architecture. Windows Defender's real-time monitoring was confirmed
active on this machine with no exclusion configured for the repo path during this investigation
— consistent with (not proven as) AV-scanning overhead on Mnesia's `disc_copies` writes being
the dominant cost.

Attempted fix for the local NFR-001 gap (`FT-046`/`FT-047`, collapsing three Mnesia transactions
into one) measured 300.03ms p95 at a REDUCED scale the unfixed code passes at 95.33ms — a
regression on the SAME local machine, hence reverted. That comparison's *relative* validity is
unaffected by the local/CI absolute-number gap found here. See `audit.md` §4 item 1 for the full
reasoning and recommended next step (re-measure on representative target hardware before
resuming any transaction-redesign work).

## 4. CI run cited

**`.github/workflows/ci.yml` run [30020074937](https://github.com/Chunkys0up7/loanacting/actions/runs/30020074937),
commit `939be9a1cad69c312ac61716ff6f8a16f098d018` — fully green, all three jobs:**

- **`backend` (8m9s)**: `mix deps.get`, `mix compile --warnings-as-errors`, `mix test` (455
  tests, 6 properties, 0 failures — including the full 10,000-run CI-scale property test, ~520s
  of that total), `mix credo --strict` (684 mods/funs, 0 issues), `mix dialyzer` (0 errors, `MIX_ENV=test` —
  see audit.md Deviation 8 for why this differs from every local run before this audit), `mix
  test.smoke` (1 test), **`mix test.load`** (see below — genuinely passed, not expected to).
- **`frontend` (38s)**: `npm run lint`, `npm run typecheck`, `npm test` — all green.
- **`e2e` (1m50s)**: backend booted for real, `npm run e2e` (Playwright: spawn-and-event, smoke,
  hitl, contract specs) — all green, against a live backend in CI for the first time.

**This is also the FIRST run in this repository's history to schedule any jobs at all** — every
prior push (since `ci.yml`'s introduction at FT-004) failed at the workflow-parse stage with
zero jobs scheduled (`Invalid workflow file ... Unrecognized function: 'hashFiles'`), a bug this
same audit found and fixed. See `audit.md` Deviation 5.

**`mix test.load` passing was NOT the expected outcome** going into this run — `tasks.md`'s own
Definition of Done and this project's own `clarifications.md` both document NFR-001 as a known,
unmet gap (496.64ms p95 measured locally). It passed anyway, at 7.3ms p95, a ~68x difference from
the local number for the identical test and code. A follow-up same-hardware Docker run (§3 above)
confirmed this wasn't a fluke of CI's own runner: 10.23ms p95, ~48x faster than Windows-native on
the identical machine. This is documented as the audit's headline finding (`audit.md` §4 item 1)
— resolved with high confidence as a Windows-local-development-machine artifact, not a production
architectural gap, not a rubber-stamped "the gap is now closed" on the strength of one lucky run.
