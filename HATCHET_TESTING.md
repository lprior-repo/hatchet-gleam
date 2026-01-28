# Hatchet Server Testing

This document describes how to test the Gleam Hatchet SDK against a local Hatchet server.

## Local Hatchet Server Setup

### Using Docker Compose (Recommended)

The project includes a `docker-compose.yml` file for easy setup:

```bash
# Start all Hatchet services
docker compose up -d

# View logs
docker compose logs -f

# Stop services
docker compose down
```

Services exposed:
- **gRPC Engine**: `localhost:7077` (container: 7070 → host: 7077)
- **Dashboard**: `http://localhost:8080`
- **RabbitMQ**: `localhost:5672`
- **RabbitMQ UI**: `http://localhost:15672`
- **PostgreSQL**: `localhost:5432`

### Using All-in-One Image

If you prefer the all-in-one image:

```bash
docker run -p 7070:7070 -p 7071:7071 ghcr.io/hatchet-dev/hatchet/hatchet-all-in-one:latest
```

### Verifying Server Connection

Test that the Hatchet server is running and accessible:

```bash
# Check gRPC engine health
curl http://localhost:7077/health

# Or check dashboard
open http://localhost:8080
```

## Running Live Integration Tests

The SDK includes live integration tests that verify end-to-end workflow execution against a real Hatchet server.

### Run Live Tests

```bash
# 1. Start Hatchet server
docker compose up -d

# 2. Wait for services to be ready (30-60 seconds)
docker compose ps

# 3. Run live integration tests
HATCHET_LIVE_TEST=1 gleam test

# Only specific test:
HATCHET_LIVE_TEST=1 gleam test --target test/integration/live_test
```

### Live Test Coverage

- **Worker registration**: Verify workers can connect and register with gRPC
- **Workflow execution**: Test multi-step workflows with task dependencies
- **Task execution**: Verify tasks receive input and produce output
- **Context handling**: Test TaskContext API with real data

## Unit Testing

The SDK includes comprehensive unit tests that verify:
- Client creation and configuration
- Workflow definition with dependencies
- Task configuration (retries, timeouts, backoff)
- JSON serialization for wire protocol
- Worker configuration
- gRPC protocol encoding/decoding

Run all tests (excludes live tests unless `HATCHET_LIVE_TEST=1`):
```bash
gleam test
```

## Example Usage

```gleam
import hatchet
import hatchet/workflow
import hatchet/run
import gleam/dynamic
import gleam/io

pub fn main() {
  // Create client
  let assert Ok(client) = hatchet.new("localhost:7070", "your-api-token")

  // Define workflow
  let my_workflow =
    workflow.new("order-processing")
    |> workflow.with_description("Process customer orders")
    |> workflow.task("validate", fn(ctx) {
      let input = ctx.input
      io.println("Validating order...")
      Ok(dynamic.from(True))
    })
    |> workflow.task_after("charge", ["validate"], fn(ctx) {
      io.println("Charging payment...")
      Ok(dynamic.from("charge_id_123"))
    })
    |> workflow.task_after("fulfill", ["charge"], fn(ctx) {
      io.println("Fulfilling order...")
      Ok(dynamic.from("shipped"))
    })
    |> workflow.with_retries(3)
    |> workflow.on_failure(fn(ctx) {
      io.println("Order failed: " <> ctx.error)
      Ok(Nil)
    })

  // Create and start worker
  let config = hatchet.worker_config()
    |> hatchet.with_slots(10)

  let assert Ok(worker) = hatchet.new_worker(client, config, [my_workflow])
  let assert Ok(_) = hatchet.start_worker_blocking(worker)
}
```

## Test Coverage

The SDK tests cover:

1. **Client Management** (`test/hatchet/client_test.gleam`)
   - Client creation with host, port, token, and namespace
   - Worker configuration and slots
   - Labels and metadata

2. **Workflow Definition** (`test/hatchet/workflow_test.gleam`)
   - Workflow creation with name, description, version
   - Task addition with dependencies
   - Triggers (cron, events)
   - Concurrency settings
   - Failure handlers

3. **Task Configuration** (`test/hatchet/task_test.gleam`)
   - Task retries and backoff strategies
   - Execution and schedule timeouts
   - Rate limits
   - Concurrency configuration
   - Wait conditions

4. **Standalone Tasks** (`test/hatchet/standalone_test.gleam`)
   - Single-task workflow creation
   - Standalone task configuration

5. **JSON Serialization** (`test/hatchet/internal/json_test.gleam`)
   - Workflow encoding for API requests
   - Task encoding with all options
   - Backoff strategy encoding
   - Concurrency and rate limit encoding
   - Wait condition encoding

6. **Integration** (`test/hatchet/integration_test.gleam`)
   - End-to-end workflow creation
   - Multi-task workflows with dependencies
   - Client configuration
   - JSON encoding verification

## Known Issues

If you encounter database connection issues with Hatchet:

1. Ensure PostgreSQL is running and healthy:
   ```bash
   docker ps | grep postgres
   ```

2. Check Hatchet logs for connection errors:
   ```bash
   docker logs <hatchet-container>
   ```

3. Restart the Hatchet containers:
   ```bash
   docker compose restart
   ```

4. Verify network connectivity between containers:
   ```bash
   docker network inspect <network-name>
   ```

## Manual Testing Checklist

When testing against a live Hatchet server, verify:

- [ ] Client can connect to Hatchet server
- [ ] Workflow can be registered with the server
- [ ] Worker can listen for and execute tasks
- [ ] Workflow runs can be triggered
- [ ] Task outputs are properly passed between dependent tasks
- [ ] Retries work as configured
- [ ] Timeouts are enforced
- [ ] Workflow failures are handled correctly
- [ ] Event triggers work (cron and event-based)
- [ ] Concurrency limits are respected
