# Order Tracking Pack — Plugin Manifest

A bundled plugin that activates the full Order Tracking agent toolkit in one step.
This is the project-specific equivalent of a reusable Claude plugin pack.

## What this pack includes

| Component | Path | Purpose |
|---|---|---|
| Hook: PostToolUse | `.claude/hooks/PostToolUse.sh` | Auto-lint Python on every save |
| Hook: SessionStart | `.claude/hooks/SessionStart.sh` | Load project context on startup |
| Hook: PreCompact | `.claude/hooks/PreCompact.sh` | Persist state before compaction |
| Hook: pre-commit | `.claude/hooks/pre-commit.sh` | Block secrets, run unit tests |
| Agent: code-reviewer | `.claude/agents/code-reviewer.md` | FastAPI architecture review |
| Agent: debugger | `.claude/agents/debugger.md` | FastAPI/SQLAlchemy debug playbook |
| Agent: security-auditor | `.claude/agents/security-auditor.md` | OWASP + HMAC + IDOR checks |
| Agent: test-writer | `.claude/agents/test-writer.md` | pytest + httpx test generation |
| Agent: researcher | `.claude/agents/researcher.md` | Carrier API + payment provider research |
| Agent: log-analyzer | `.claude/agents/log-analyzer.md` | FastAPI/Celery log parsing |
| Skill: order-flow | `.claude/skills/order-flow/` | Order state machine patterns |
| Skill: api-scaffold | `.claude/skills/api-scaffold/` | FastAPI endpoint scaffolding |
| Skill: db-migrations | `.claude/skills/db-migrations/` | Alembic migration patterns |
| Skill: carrier-integration | `.claude/skills/carrier-integration/` | Carrier webhook patterns |
| Rule: api | `.claude/rules/api.md` | Route naming + response envelope |
| Rule: database | `.claude/rules/database.md` | SQLAlchemy async + repository pattern |
| Rule: frontend | `.claude/rules/frontend.md` | React + Zustand + React Query |
| Output style: terse | `.claude/output-styles/terse.md` | Code-only output format |
| Command: deploy | `.claude/commands/deploy.md` | Pre-deploy checklist + release |
| Command: audit | `.claude/commands/audit.md` | Security + quality audit |
| Command: fix-issue | `.claude/commands/fix-issue.md` | gh issue → fix → PR workflow |
| Command: pr-review | `.claude/commands/pr-review.md` | Architecture + security PR review |

## How to activate the full pack

In any Claude session with this project, say:
> "Load the order-tracking pack"

Claude will read this manifest and load all relevant skills, agents, and rules into context.

## Version
Pack version: 1.0.0
Last updated: 2026-05-07
Stack: Python 3.12 + FastAPI + SQLAlchemy 2.x async + React 18 + TypeScript
