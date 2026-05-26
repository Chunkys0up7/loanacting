# Project Constitution

> **Purpose**: Non-negotiable principles and constraints that govern all specification, planning, and implementation phases. This document is read by the agent at every phase transition. It is the single source of truth for "what is always true" about this project.
>
> **Audience**: AI coding agents (Claude Code, Copilot, Cursor, etc.)
>
> **Instructions**: Replace all `[PLACEHOLDER]` values. Delete any section that does not apply. Do not add implementation-specific details here — those belong in the tech spec.

---

## 1. Project Identity

- **Project name**: [PROJECT_NAME]
- **One-line purpose**: [What this project does in one sentence]
- **Organization**: [Team or org name]
- **Domain**: [Industry/domain context, e.g., "mortgage servicing", "healthcare operations"]
- **Classification**: [Internal tool | Customer-facing | Platform | Library | API]

---

## 2. Immutable Principles

> These are hard constraints. The agent must never violate them, even if a spec or plan suggests otherwise.

### 2.1 Security

- [ ] All secrets must be stored in [SECRET_STORE, e.g., AWS Secrets Manager, Azure Key Vault, .env excluded from VCS]
- [ ] No credentials, API keys, or tokens in source code — ever
- [ ] [AUTH_REQUIREMENT, e.g., "All endpoints require JWT authentication"]
- [ ] [DATA_CLASSIFICATION, e.g., "PII must be encrypted at rest and in transit"]
- [ ] [COMPLIANCE_FRAMEWORK, e.g., "Must comply with SOC2 / HIPAA / PCI-DSS"]

### 2.2 Quality

- [ ] Minimum test coverage: [COVERAGE_TARGET, e.g., "80% line coverage"]
- [ ] All public interfaces must have tests before merge
- [ ] No warnings in production builds
- [ ] [LINT_STANDARD, e.g., "ESLint strict mode with no-any rule"]
- [ ] [TYPE_SAFETY, e.g., "TypeScript strict mode, no `any` types"]

### 2.3 Architecture

- [ ] [PATTERN, e.g., "Separation of concerns: models → services → controllers"]
- [ ] [DEPENDENCY_RULE, e.g., "No circular imports between modules"]
- [ ] [STATE_MANAGEMENT, e.g., "Server-side state of truth; client is a projection"]
- [ ] [API_STYLE, e.g., "REST with OpenAPI 3.1 contracts" or "GraphQL with schema-first"]

### 2.4 Boundaries — What the Agent Must Never Do

- 🚫 Never modify CI/CD pipeline configuration without explicit approval
- 🚫 Never install packages not on the approved list (see §4)
- 🚫 Never commit directly to `main` — all work goes through feature branches
- 🚫 Never disable security scanners, linters, or test suites
- 🚫 Never expose internal endpoints to public networks
- 🚫 [CUSTOM_BOUNDARY]

### 2.5 Boundaries — What the Agent Must Always Do

- ✅ Run the full test suite before marking any task complete
- ✅ Include error handling for all external service calls
- ✅ Log structured JSON for all operations (no `console.log` in production)
- ✅ Write meaningful commit messages following [COMMIT_CONVENTION, e.g., Conventional Commits]
- ✅ [CUSTOM_ALWAYS]

### 2.6 Boundaries — Ask First

- ⚠️ Adding a new dependency to package.json / requirements.txt
- ⚠️ Changing database schema (migrations)
- ⚠️ Modifying shared utility functions used by other features
- ⚠️ [CUSTOM_ASK_FIRST]

---

## 3. Approved Technology Stack

> Only technologies listed here may be used. If a spec requires something not on this list, the agent must flag it with `[NEEDS APPROVAL: technology not in constitution]`.

### 3.1 Languages & Runtimes

| Layer | Technology | Version | Notes |
|-------|-----------|---------|-------|
| Backend | [e.g., Python] | [e.g., 3.11+] | [e.g., "FastAPI preferred"] |
| Frontend | [e.g., TypeScript] | [e.g., 5.x] | [e.g., "React 18+ with hooks only"] |
| Infrastructure | [e.g., Terraform] | [e.g., 1.5+] | |
| Scripts | [e.g., Bash/Python] | | |

### 3.2 Approved Packages & Frameworks

| Category | Package | Version | Purpose |
|----------|---------|---------|---------|
| [e.g., Web framework] | [e.g., FastAPI] | [e.g., 0.100+] | [e.g., API layer] |
| [e.g., ORM] | [e.g., SQLAlchemy] | [e.g., 2.x] | [e.g., Database access] |
| [e.g., Testing] | [e.g., pytest] | [e.g., 7.x] | [e.g., Unit + integration] |
| [e.g., UI framework] | [e.g., Salt DS] | [e.g., 1.x] | [e.g., Component library] |

### 3.3 Infrastructure & Services

| Service | Provider | Notes |
|---------|----------|-------|
| [e.g., LLM] | [e.g., AWS Bedrock] | [e.g., "Claude via Bedrock only — no direct Anthropic API"] |
| [e.g., Database] | [e.g., PostgreSQL 15] | [e.g., "RDS, not self-hosted"] |
| [e.g., Vector store] | [e.g., pgvector] | |
| [e.g., Object storage] | [e.g., S3] | |
| [e.g., Auth] | [e.g., Cognito / Okta] | |

### 3.4 Prohibited Technologies

> Explicitly banned. If the agent encounters a suggestion to use these, it must refuse.

- [e.g., "No MongoDB — PostgreSQL only"]
- [e.g., "No direct OpenAI API calls — must route through internal gateway"]
- [e.g., "No jQuery — vanilla JS or React only"]

---

## 4. Development Workflow

### 4.1 Git Conventions

- **Branch naming**: `[PREFIX]/[SHORT_NAME]` (e.g., `feature/add-auth`, `fix/null-check`)
- **Commit format**: [e.g., Conventional Commits — `feat:`, `fix:`, `docs:`, `test:`, `chore:`]
- **PR requirements**: [e.g., "All PRs require 1 approval, passing CI, and no unresolved comments"]

### 4.2 Commands

> The agent must know how to build, test, lint, and deploy. Provide full commands with flags.

| Action | Command | Notes |
|--------|---------|-------|
| Install dependencies | [e.g., `npm install`] | |
| Build | [e.g., `npm run build`] | [e.g., "Must exit 0"] |
| Test | [e.g., `npm test -- --coverage`] | [e.g., "Must pass before commit"] |
| Lint | [e.g., `npm run lint`] | [e.g., "Auto-fix with `--fix`"] |
| Type check | [e.g., `npx tsc --noEmit`] | |
| Start dev | [e.g., `npm run dev`] | |

### 4.3 Project Structure

```
[PROJECT_ROOT]/
├── src/
│   ├── models/          # Data models and schemas
│   ├── services/        # Business logic
│   ├── api/             # Route handlers / controllers
│   ├── lib/             # Shared utilities
│   └── config/          # Configuration and environment
├── tests/
│   ├── unit/
│   ├── integration/
│   └── fixtures/
├── docs/
│   └── specs/           # Spec Kit artifacts live here
├── scripts/             # Build and deployment scripts
└── [OTHER_DIRS]
```

### 4.4 Code Style

> One real example is worth more than three paragraphs of description. Provide a canonical snippet.

```[language]
# Example of expected code style:
[PASTE_A_REPRESENTATIVE_CODE_SNIPPET_HERE]
```

**Naming conventions**:
- Files: [e.g., `kebab-case.ts`]
- Classes: [e.g., `PascalCase`]
- Functions: [e.g., `camelCase`]
- Constants: [e.g., `SCREAMING_SNAKE_CASE`]
- Database tables: [e.g., `snake_case`]

---

## 5. Environment & Network Constraints

> For enterprise environments with restricted network access, proxy requirements, or air-gapped systems.

- **Network egress**: [e.g., "Restricted — only allowlisted domains via corporate proxy"]
- **Package registries**: [e.g., "Internal Artifactory at https://artifactory.corp.example.com"]
- **LLM gateway**: [e.g., "Internal OpenAI-compatible endpoint at https://llm-gateway.corp.example.com"]
- **Development environment**: [e.g., "Coder Workspaces with reverse proxy at CODER_URL"]
- **Telemetry**: [e.g., "Disable all outbound telemetry — set SCARF_ANALYTICS=false, DO_NOT_TRACK=1"]

---

## 6. Definition of Done

> A task is not complete until ALL of the following are true:

- [ ] Code compiles / builds without warnings
- [ ] All existing tests pass
- [ ] New tests cover the new functionality (minimum: [COVERAGE_TARGET])
- [ ] Linter passes with zero violations
- [ ] Type checker passes (if applicable)
- [ ] No `[NEEDS CLARIFICATION]` markers remain in the spec
- [ ] Commit message follows convention (§4.1)
- [ ] [CUSTOM_DOD_ITEM]

---

## 7. Revision History

| Date | Author | Change |
|------|--------|--------|
| [DATE] | [AUTHOR] | Initial constitution |
