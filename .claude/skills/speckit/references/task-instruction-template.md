# Task Instruction: [TASK_ID] — [TASK_TITLE]

> **Purpose**: A focused execution playbook for a single task from `tasks.md`. This document scopes the agent's context to exactly what it needs for THIS task — no more, no less. It prevents context drift, ensures required tools are used, and defines unambiguous completion criteria.
>
> **When to create**: After `/speckit.tasks` generates the task breakdown. Create one instruction file per task (or per complex task — simple tasks may not need one).
>
> **How to use**: Reference this file in `tasks.md` alongside the task entry:
> ```
> - [ ] Task 1.2.1: Set up database schema → See `task-instructions/task-1.2.1-db-schema.md`
> ```

---

## Task Metadata

| Field | Value |
|-------|-------|
| **Task ID** | [e.g., 1.2.1] |
| **Title** | [e.g., "Set up PostgreSQL schema and migrations"] |
| **Phase** | [e.g., Phase 1 — Data Layer] |
| **Classification** | [Tag(s): `[DATABASE]`, `[SECURITY-CRITICAL]`, `[API]`, `[UI]`, `[INTEGRATION]`, `[INFRASTRUCTURE]`, `[TEST]`] |
| **Estimated complexity** | [Simple / Medium / Complex] |
| **Parallel-safe** | [Yes — can run alongside tasks X, Y / No — blocks or is blocked] |

---

## Dependencies

### Requires (must be complete before starting)

| Task ID | Title | Status |
|---------|-------|--------|
| [e.g., 1.1.1] | [e.g., Project scaffolding] | [ ] Complete |
| [e.g., 1.1.2] | [e.g., Config and env setup] | [ ] Complete |

### Blocks (cannot start until this task completes)

| Task ID | Title |
|---------|-------|
| [e.g., 1.3.1] | [e.g., Service layer for users] |
| [e.g., 2.1.1] | [e.g., API route for user creation] |

### Dependency Diagram

```
[1.1.1 Scaffolding] ──▶ [THIS TASK: 1.2.1] ──▶ [1.3.1 Service Layer]
[1.1.2 Config]      ──▶                    ──▶ [2.1.1 API Routes]
```

---

## Required Tools & Skills

> The agent MUST use these tools. A task cannot be marked complete if any required tool was skipped.

### Mandatory Tools

| Tool Type | Name | Purpose | When to Use |
|-----------|------|---------|-------------|
| [e.g., MCP] | [e.g., prisma-local] | [e.g., Run migrations] | [e.g., After schema changes] |
| [e.g., Skill] | [e.g., database-expert] | [e.g., Validate RLS patterns] | [e.g., Before writing any RLS policy] |
| [e.g., Sub-agent] | [e.g., security-reviewer] | [e.g., Scan for SQL injection] | [e.g., After all queries are written] |
| [e.g., CLI] | [e.g., `npm test`] | [e.g., Run tests] | [e.g., After implementation, before commit] |

### Optional Tools

| Tool Type | Name | Purpose | Use If |
|-----------|------|---------|--------|
| [e.g., MCP] | [e.g., memory-store] | [e.g., Record decisions] | [e.g., If a design decision was made during implementation] |

---

## Execution Workflow

### BEFORE — Context Loading

> Do these steps before writing any code.

1. [ ] Read the relevant sections of the product spec:
   - Section(s): [e.g., "§3 User Stories: US-001, US-002", "§4.1 Data Retrieval requirements"]
2. [ ] Read the relevant sections of the tech spec:
   - Section(s): [e.g., "§3 Data Model", "§5 Security Design"]
3. [ ] Read the constitution:
   - Section(s): [e.g., "§2.2 Quality", "§3.2 Approved Packages"]
4. [ ] Check dependency tasks are complete:
   - [ ] [Task ID] — verified [how]
5. [ ] [Optional] Query memory/context for prior decisions relevant to this task

### DURING — Implementation

> Step-by-step instructions. Each step has a verification checkpoint.

**Step 1: [ACTION]**
- Do: [Specific instruction]
- Verify: [How to confirm this step succeeded]
- If it fails: [What to do]

**Step 2: [ACTION]**
- Do: [Specific instruction]
- Verify: [How to confirm this step succeeded]
- If it fails: [What to do]

**Step 3: [ACTION]**
- Do: [Specific instruction]
- Verify: [How to confirm this step succeeded]
- If it fails: [What to do]

**Step 4: [ACTION]**
- Do: [Specific instruction]
- Verify: [How to confirm this step succeeded]
- If it fails: [What to do]

### AFTER — Validation & Cleanup

> Do these steps after implementation, before marking the task complete.

1. [ ] Run tests: `[COMMAND]`
   - Expected: All pass, coverage ≥ [TARGET]
2. [ ] Run linter: `[COMMAND]`
   - Expected: Zero violations
3. [ ] Run type checker (if applicable): `[COMMAND]`
   - Expected: Zero errors
4. [ ] Run security scan (if `[SECURITY-CRITICAL]`): `[COMMAND or TOOL]`
   - Expected: No critical or high findings
5. [ ] [Optional] Store decisions in memory MCP
6. [ ] Commit with message following convention: `[e.g., "feat(db): add user schema and initial migration"]`

---

## Files Touched

> Exactly which files this task creates or modifies. The agent must not touch files outside this list without justification.

### Created

| File Path | Purpose |
|-----------|---------|
| [e.g., `src/models/user.py`] | [e.g., User model definition] |
| [e.g., `migrations/001_create_users.py`] | [e.g., Initial migration] |
| [e.g., `tests/unit/test_user_model.py`] | [e.g., Model unit tests] |

### Modified

| File Path | What Changes |
|-----------|-------------|
| [e.g., `src/main.py`] | [e.g., Import and register user model] |
| [e.g., `src/core/config.py`] | [e.g., Add database connection string] |

### Must Not Touch

- [e.g., `src/core/auth.py` — owned by Task 2.1.3]
- [e.g., `.github/workflows/` — constitution §2.4 prohibits CI changes]
- [e.g., Any files in `src/[other_module]/` — out of scope for this task]

---

## Acceptance Criteria

> Every box must be checked to mark this task complete. These map to the product spec's acceptance criteria where applicable.

### Functional

- [ ] [e.g., User model has all required fields from domain model (product spec §6.1)]
- [ ] [e.g., Migration runs successfully on empty database]
- [ ] [e.g., Migration is reversible (down migration works)]
- [ ] [e.g., Seed data loads without errors]

### Quality

- [ ] Tests pass: `[COMMAND]` returns exit code 0
- [ ] Coverage: ≥ [TARGET]% for new code
- [ ] Linter: zero violations
- [ ] Type check: zero errors

### Security (if `[SECURITY-CRITICAL]`)

- [ ] [e.g., No raw SQL queries — all queries use ORM/parameterized statements]
- [ ] [e.g., PII fields are marked and excluded from default serialization]
- [ ] [e.g., Security scan passes with no critical findings]

### Documentation

- [ ] [e.g., Schema is documented in data-model.md]
- [ ] [e.g., Any design decisions are recorded in ADR format]

---

## Troubleshooting

> Common issues the agent might hit during this task and how to resolve them.

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| [e.g., "Migration fails with permission error"] | [e.g., DB user lacks CREATE permission] | [e.g., Run `GRANT CREATE ON DATABASE...`] |
| [e.g., "Import error for new model"] | [e.g., Missing `__init__.py` export] | [e.g., Add model to `__init__.py`] |
| [e.g., "Tests can't connect to DB"] | [e.g., Test DB not running] | [e.g., Start testcontainer or check DATABASE_URL] |

---

## Notes

> Any additional context, constraints, or decisions relevant to this task.

- [e.g., "The user table must support soft deletes — use `deleted_at` column, not physical DELETE"]
- [e.g., "This schema must be compatible with the existing auth service's user ID format (UUID v4)"]
- [e.g., "Migration must be idempotent — safe to run multiple times"]
