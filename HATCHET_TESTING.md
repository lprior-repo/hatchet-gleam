# Hatchet Server Testing

This document describes how to test the Gleam Hatchet SDK against a local Hatchet server.

## Local Hatchet Server Setup

The recommended way to run a local Hatchet server is using Docker:

```bash
docker run -p 7070:7070 -p 7071:7071 ghcr.io/hatchet-dev/hatchet/hatchet-all-in-one:latest
```

If the all-in-one image is not available, use Docker Compose with the official configuration:

```bash
git clone https://github.com/hatchet-dev/hatchet.git
cd hatchet/docker
docker compose up -d
```

## Verifying Server Connection

Test that the Hatchet server is running and accessible:

```bash
curl http://localhost:7070/health
```

## Integration Testing

The SDK includes comprehensive unit tests that verify:
- Client creation and configuration
- Workflow definition with dependencies
- Task configuration (retries, timeouts, backoff)
- JSON serialization for wire protocol
- Worker configuration

Run all tests:

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
