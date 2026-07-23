# Report — Loan-Actor Foundation Implementation Closeout

**Audience**: anyone who wasn't in the room while this was built — a future operator, a new
contributor, or a reviewer deciding whether intent 0001 can close.

## What shipped

The foundation inverts the usual mortgage-tech pattern: instead of a loan being a row in a
database that workflow engines push between stations, **the loan is a live, supervised process**
on the BEAM (Erlang/OTP) with its own memory, its own append-only history, and its own ability to
notice things and ask for help. This spec built that runtime, end to end, plus the web UI that
lets an operator watch and interact with a live loan.

Concretely, by track:

- **Diary** (Track 2): every event, decision, and tool call a loan experiences is recorded as a
  tamper-evident, chain-linked entry — cryptographically, not just "we didn't change the log."
  Two interchangeable storage backends (a plain file and Mnesia, OTP's built-in database) both
  pass the exact same test suite, proving the abstraction is real, not aspirational.
- **State machine** (Track 3): a loan's status can only change through one gate function, and a
  custom linter (Credo check) makes it a compile-time-adjacent violation to bypass it anywhere
  in the codebase.
- **The actor itself** (Track 5): a loan runs three distinct "loops" — react to things that
  happen to it, check in periodically on its own schedule, and make its own plans — all
  explicitly labeled in the code (another custom linter enforces the labels aren't skipped).
- **Crash safety** (Tracks 5, 10): kill a loan's process mid-flight, on purpose, and it comes back
  with the exact same state, rebuilt purely by replaying its own history. Proven at small scale
  (a handful of events), at large scale (10 loans crashing simultaneously with 10,000 history
  entries each), and via 10,000 randomly-generated scenarios in CI.
- **Tools and skills** (Track 12, added mid-build by intent 0004): anything the loan does on its
  own initiative — asking for a document, setting a goal, requesting an operator's approval — goes
  through a typed, registered "tool" the same way a modern AI agent's function-calling works, and
  which knowledge to apply is content (a markdown pack), not code. Every tool call streams live to
  the UI in four stages (started → arguments → finished → result), so an operator watching the
  screen sees exactly what the loan is doing and why, in real time.
- **Human-in-the-loop** (Track 8): a loan can pause and ask an operator a yes/no question; the
  answer comes back through the same live UI and the loan resumes.
- **The web UI** (Track 9): a React app (CopilotKit) showing a loan's current state, its diary
  feed live-updating over a persistent connection, its in-flight tool calls, and any pending
  approval requests — built and manually verified against the real running backend in a real
  browser at three separate points during this build, not just automated headless tests.
- **PII stays out of the history** (cross-cutting): every event and every tool's arguments pass
  through a guard that rejects anything matching a configured sensitive-data pattern before it
  ever reaches the diary or the screen.
- **Command-line tools** (Track 11): `mix loan_actor.spawn`, `.replay`, `.verify_chain`, and
  `.dump_diary` — the same operations quickstart.md documents for a new developer, each backed by
  its own test.

## What's honestly still open

- **Throughput at full production scale (NFR-001) — turned out to be a local development-machine
  problem, not a real limit, confirmed three ways.** On the Windows machine this whole project
  was built on, the load test runs about 5x over budget (496ms vs. a 100ms target at the 95th
  percentile). A fix was attempted (collapsing three database transactions per event into one),
  passed every test cleanly, and was then proven — by the same load test, at the literal scale
  that matters — to make things *worse* on that same machine, so it was reverted. Running that
  identical test on GitHub's own CI hardware, it passed at 7.3ms. To rule out "maybe CI just got
  lucky," it was run a third time in a Linux container on this exact same physical Windows
  machine, using the exact Elixir/database version this project is pinned to — same CPU, same
  disk, same everything except the operating system. It passed there too, at 10.23ms, about 48
  times faster than the Windows-native result. Three measurements, one variable changing (the
  operating system), the same dramatic result each time on Linux: **this is very likely not an
  architectural problem at all** — it's specific to something about running on Windows during
  local development (this session separately flagged Windows security-scanning software slowing
  down other file-heavy operations, which lines up with what would explain this). Practically:
  anywhere this actually gets deployed (Linux, same as this project's own CI target) very likely
  never had this problem. The honest caveat is "very likely," not "proven beyond doubt" — but
  three independent measurements pointing the same direction, one of them a controlled same-
  hardware comparison, is strong evidence, not a guess.
- **A loan's open goals do not survive a crash.** Found while auditing this closeout, not during
  original development: the diary only ever stores a one-way hash of what a goal actually says
  (by design — that's how PII is kept out of the permanent record), which means there's no way
  to reconstruct the goal's actual text after a restart. The loan itself keeps running correctly
  and its *status* survives perfectly; it's specifically the goal descriptions that are lost.
  This needs its own follow-up decision: either goal text isn't sensitive enough to need this
  protection and can be stored more directly, or a separate secure-but-recoverable store is
  needed for it.
- **Two real bugs were found and fixed during this same closeout audit**, both because this was
  the first time this project's CI actually ran successfully (see below): a loan whose automatic
  goal-setting fired while it wasn't in its very first state would crash-loop forever on any
  future restart (now fixed, with a test proving it), and a slow-timing test that only ever
  passed by luck on the original developer's machine (now fixed the same way three similar,
  later-written tests already handle it correctly).

## A surprising find: CI had never actually run

While preparing this closeout, "cite a green CI run" turned out to be impossible — every single
push to this repository, going all the way back to the very first commit that added a CI
workflow, had failed instantly with zero tests ever run. The cause was a workflow-file syntax
issue GitHub's own system rejected outright (not a code problem, a CI-configuration problem).
Once fixed, the very first real CI run immediately caught three more real issues local testing
had never surfaced (a test that needed more time than its default allowance under the much
heavier CI-scale run, the timing-luck test mentioned above, and three intentionally "broken" test
fixtures that a stricter local command would have also caught, had it been run the same way CI
runs it). All four are fixed and verified. This is a good outcome from the process working as
intended — it's also a reminder that "the tests pass on my machine" and "CI is green" are
different claims, and only one of them had ever actually been checked here before now.

## Where to look

- Every commit SHA per task is in `tasks.md`'s own status ledger (front matter of this repo's
  spec folder) — one commit per `FT-NNN` task, tests included in the same commit.
- The exact requirement-by-requirement mapping (which test proves which spec line) is in
  `audit.md`.
- Coverage taxonomy, factory inventory, and load-test numbers are in `test-evidence.md`.
- The architectural rationale for why a loan is a process instead of a database row is in
  `loan-as-actor.html` at the repo root.

## Follow-ups (each needs its own intent, not a quick patch here)

1. Close intent 0005 as "investigated: root cause was the local Windows development machine, not
   the database transaction design" rather than pursuing the batching/tuning work it originally
   proposed — three independent measurements (CI + a same-hardware Linux container) now say that
   work is very likely unnecessary.
2. Goal content survivability across a crash — resolve the tension between "diary entries are
   hash-only" and "every state-mutating handler must be replay-reproducible."
3. The load test's memory budget (NFR-002) turned out to swing the OPPOSITE way this
   investigation surfaced: it passes on a small CI machine (179MB) but fails on this powerful
   32-core development machine (366MB) — likely because the runtime's own default overhead
   scales with core count, not because 100 loans actually use more memory there. Worth deciding
   whether the budget should scale with the deployment's core count instead of being a flat
   number.
4. A second reviewer for `audit.md`, per this project's own preference for a different author
   than the implementer where practical (this closeout was self-attested — no second reviewer
   was available).

## UI — what was actually seen working

Verified live against the real backend + a real browser at three points during this build (not
just automated tests): spawning a loan and watching its first diary entry and state render;
sending an event through the UI and watching the diary feed and state card update from the live
stream in under a second; and a tool call rendering as a correlated card from "started" through
"result." Screenshots were not captured/retained as separate artifacts during those sessions;
the same flows are what `apps/web/test/e2e/spawn-and-event.spec.ts` and `smoke.spec.ts` assert
programmatically today, and can be re-run live at any time via `apps/web`'s own `npm run e2e`
against a booted backend (`specs/001-loan-actor-foundation/quickstart.md`).
