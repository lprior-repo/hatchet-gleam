# Moonrepo Configuration

This project uses [Moonrepo](https://moonrepo.dev) for task running, caching, and CI/CD orchestration.

> **Default branch:** `main`

## Overview

Moonrepo is configured with:
- **Local caching** in `.moon/cache/`
- **Remote caching** via Bazel Remote at `http://127.0.0.1:9090`
- **Smart hashing** for incremental builds
- **Pre-push hooks** for quality gates

## Bazel Remote Setup

The project connects to a local [Bazel Remote](https://github.com/buchgr/bazel-remote) cache server:

```bash
# Current configuration
/home/lewis/.local/bin/bazel-remote \
  --dir /home/lewis/.cache/bazel-remote \
  --max_size 100 \
  --storage_mode zstd \
  --grpc_address 127.0.0.1:9092 \
  --http_address 127.0.0.1:9090
```

### Endpoints

| Protocol | Address | Usage |
|----------|---------|-------|
| HTTP | `http://127.0.0.1:9090` | Cache API (used by moon) |
| gRPC | `http://127.0.0.1:9092` | Remote Execution API (future) |

### To Enable Remote Caching

Edit `.moon/workspace.yml`:

```yaml
unstable_remote:
  host: 'http://127.0.0.1:9090'
  api: 'http'
  cache:
    instanceName: 'hatchet-gleam'
    compression: 'zstd'
```

## Available Tasks

Run all tasks with `moon run <task>`:

| Task | Description | Command |
|------|-------------|---------|
| `quick` | Check formatting | `gleam format --check` |
| `fmt-fix` | Fix formatting | `gleam format` |
| `check` | Type check | `gleam check` |
| `build` | Build project | `gleam build` |
| `test` | Run tests | `gleam test` |
| `ci` | Full CI pipeline | Runs quick, check, test |

## Pre-push Quality Gates

The pre-push hook (from `~/.git-hooks/pre-push`) enforces:

1. **Format check** - `moon run :quick`
2. **Compilation check** - `moon run :check`
3. **Tests** - `moon run :test`
4. **Full CI** - `moon run :ci`

To bypass in emergencies: `git push --no-verify`

## Configuration Files

- `.moon/workspace.yml` - Workspace-level configuration
- `moon.yml` - Project-level tasks and settings
- `.gitignore` - Excludes `.moon/cache/` and `.moon/hydrated/`

## References

- [Moonrepo Docs](https://moonrepo.dev/docs)
- [Workspace Config](https://moonrepo.dev/docs/config/workspace)
- [Project Config](https://moonrepo.dev/docs/config/project)
- [Tasks Config](https://moonrepo.dev/docs/config/tasks)
- [Remote Caching](https://moonrepo.dev/docs/guides/remote-caching)
