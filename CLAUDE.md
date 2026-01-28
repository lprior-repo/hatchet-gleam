# Claude AI Agent Instructions

## ⚠️ CRITICAL: Use Existing Hatchet Docker Installation

**DO NOT create new docker-compose.yml or start new Hatchet containers.**

The project ALREADY has a running Hatchet installation. See `docs/LOCAL_SETUP.md` for details.

### Hatchet Server Access

| Service | URL/Port |
|---------|----------|
| gRPC Engine | `localhost:7077` |
| Dashboard | `http://localhost:8080` |
| RabbitMQ | `localhost:5673` |
| RabbitMQ UI | `http://localhost:15673` |

### Live Integration Testing

To run live integration tests (requires existing Hatchet server):

```bash
# 1. Verify Hatchet server is running
docker ps | grep hatchet

# 2. Run live tests
HATCHET_LIVE_TEST=1 HATCHET_CLIENT_TOKEN=<token> gleam test

# 3. View test execution in dashboard
open http://localhost:8080
```

**NEVER** run `docker compose up` or `docker run` commands. Use existing setup only.

## Project Overview

Gleam SDK for Hatchet distributed task orchestration.

### Quick Start

```bash
# Work
bd ready                           # Available issues
bd show <id>                       # Acceptance criteria
bd update <id> --status in_progress

# Quality gates
gleam test                         # Run tests
gleam format src test              # Format code
gleam build                        # Check for warnings

# Complete
git commit -m "feat: description"
bd close <id> --reason "Done"
bd sync && git push                # MANDATORY
```

## Session Completion

**Work is NOT complete until `git push` succeeds.**

1. `gleam test && gleam format src test`
2. `git commit` changes
3. `bd close` finished beads
4. `bd sync && git push`
5. Verify: `git status` shows clean
