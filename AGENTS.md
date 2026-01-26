# Agent Instructions

Gleam SDK for Hatchet distributed task orchestration. Uses **bd** (beads) for issue tracking.

## Quick Start

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

## Documentation

| Topic | File |
|-------|------|
| Gleam conventions | `docs/GLEAM_CONVENTIONS.md` |
| Hatchet concepts | `docs/HATCHET.md` |
| Local testing | `docs/LOCAL_SETUP.md` |
| Project status | `SDK_VERIFICATION_REPORT.md` |

## Session Completion

**Work is NOT complete until `git push` succeeds.**

1. `gleam test && gleam format src test`
2. `git commit` changes
3. `bd close` finished beads
4. `bd sync && git push`
5. Verify: `git status` shows clean
