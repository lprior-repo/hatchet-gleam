# Local Hatchet Docker Setup

For integration testing against the local Hatchet Docker instance.

## Services

| Service | URL/Port | Description |
|---------|----------|-------------|
| gRPC Engine | `localhost:7077` | Hatchet gRPC API (container: 7070 → host: 7077) |
| Dashboard | `http://localhost:8080` | Web UI for monitoring workflows |
| RabbitMQ | `localhost:5673` | Message broker |
| RabbitMQ UI | `http://localhost:15673` | Management interface |

## Docker Status

```bash
# Check running containers
docker ps | grep hatchet

# Container names:
# - docker-hatchet-engine-1    (gRPC on 7077)
# - docker-hatchet-dashboard-1 (web UI on 8080)

# Check port mappings
docker port docker-hatchet-engine-1
# Output: 7070/tcp -> 0.0.0.0:7077
```

## Authentication

The Hatchet client token is stored in `HATCHET_CLIENT_TOKEN` environment variable.

**WARNING:** Never commit or log the actual token value.

## Configuration

When testing against Docker, port 7070 inside the container maps to 7077 on the host:

```gleam
import hatchet/internal/config

// From environment (recommended)
let assert Ok(cfg) = config.from_environment_checked()
// Set: HATCHET_HOST=localhost, HATCHET_PORT=7077, HATCHET_TOKEN=...

// Or direct config
let cfg = config.Config(
  host: "localhost",
  port: 7077,      // Host port (mapped from container 7070)
  grpc_port: 7077,
  token: option.Some(get_token_from_env()),
  namespace: option.None,
  tls_ca: option.None,
  tls_cert: option.None,
  tls_key: option.None,
)
```

## Dashboard

URL: http://localhost:8080

Use for visual verification of:
- Workflow registration
- Worker connections
- Task runs and execution

## See Also

- [AGENTS.md](../AGENTS.md) - Agent instructions
- [HATCHET.md](./HATCHET.md) - Hatchet concepts
