# Integration Testing Status

## Summary

The Hatchet Gleam SDK has been developed with full type safety and a fluent builder DSL. The following components are fully functional and tested.

## ✅ Complete and Tested Components

### Core Types (`src/hatchet/types.gleam`)
- Client, Workflow, TaskDef, WorkerConfig
- TaskContext, FailureContext, RunOptions
- ConcurrencyConfig, BackoffConfig, RateLimitConfig
- WaitCondition, Worker, WorkflowRunRef

### JSON Encoding/Decoding (`src/hatchet/internal/json.gleam`)
- Workflow create/encoding
- Workflow run requests
- Event publishing
- Worker registration
- Task completion/failure
- Workflow cancellation
- Status responses

### Protocol Types (`src/hatchet/internal/protocol.gleam`)
- HTTP request/response wrappers
- All Hatchet API request/response types
- Error types

### Workflow Builder DSL (`src/hatchet/workflow.gleam`)
```gleam
hatchet.new_workflow("workflow-name")
|> hatchet.task("task1", handler)
|> hatchet.task_after("task2", ["task1"], handler)
|> hatchet.with_retries(3)
|> hatchet.with_timeout(30_000)
|> hatchet.with_cron("0 * * * *")
|> hatchet.with_events(["user.created"])
|> hatchet.with_concurrency(10, hatchet.CancelInProgress)
```

### Task Configuration (`src/hatchet/task.gleam`)
- Retry backoff (exponential, linear, constant)
- Rate limits
- Concurrency settings
- Wait conditions (events, time, expressions)
- Skip conditions

### Standalone Tasks (`src/hatchet/standalone.gleam`)
```gleam
hatchet.standalone_task("task-name", handler)
```

### Worker Configuration (`src/hatchet/client.gleam`)
```gleam
hatchet.worker_config()
|> hatchet.with_slots(10)
|> hatchet.with_durable_slots(5)
|> hatchet.with_label("env", "production")
```

### Public API (`src/hatchet.gleam`)
- Re-exports of all public functions
- Single import point for SDK

### Unit Tests (`test/`)
- `test/hatchet/internal/json_test.gleam` - JSON encoding/decoding
- `test/hatchet/workflow_test.gleam` - Workflow builder
- `test/hatchet/task_test.gleam` - Task configuration
- `test/hatchet/client_test.gleam` - Client creation
- `test/hatchet/standalone_test.gleam` - Standalone tasks
- `test/hatchet/integration_test.gleam` - End-to-end workflow definitions

## ⚠️ Components Requiring Updates

### Client HTTP Connection (`src/hatchet/client.gleam`)
- Contains stubs for HTTP client functionality
- Worker process using gleam_otp needs API updates
- Once updated, will connect to Hatchet REST API

### Workflow Execution (`src/hatchet/run.gleam`)
- Contains function signatures for running workflows
- Needs HTTP client integration to trigger workflows
- Status polling implementation pending

### Event Publishing (`src/hatchet/events.gleam`)
- Contains function signatures for publishing events
- Needs HTTP client integration

## Testing Against Local Hatchet Server

### Start Local Hatchet Server
```bash
docker run -p 7070:7070 -p 7071:7071 hatchet/hatchet:latest
```

### Current Testing Capabilities

✅ **Workflow Definition** - Full support
```gleam
let workflow = hatchet.new_workflow("test")
  |> hatchet.task("step1", fn(ctx) { Ok(dynamic.from("done")) })
  |> hatchet.task_after("step2", ["step1"], fn(ctx) { Ok(dynamic.from("done2")) })
```

✅ **JSON Serialization** - Full support
```gleam
let json_str = hatchet.json.encode_workflow_create(req)
let assert Ok(decoded) = hatchet.json.decode_workflow_run_response(json_str)
```

✅ **Type Safety** - Full support
- All functions return Result types
- Opaque types for Client, Worker, WorkflowRunRef
- Compile-time type checking

⚠️ **Server Connection** - Blocked by client.gleam updates needed
```gleam
// This will work once client.gleam HTTP integration is complete
let assert Ok(client) = hatchet.new_client("localhost:7070", "token")
let assert Ok(worker) = hatchet.new_worker(client, config, [workflow])
let assert Ok(cleanup) = hatchet.start_worker(worker)
// ... trigger workflows, verify execution
cleanup()
```

## Manual Testing Without Server

You can test the SDK without a Hatchet server:

```bash
gleam test
```

This verifies all working components:
- Workflow builder DSL
- Task configuration
- JSON encoding/decoding
- Type system enforcement
- Builder pattern composition

## Example: Complete Workflow Definition

```gleam
import hatchet
import gleam/dynamic

pub fn main() {
  let order_workflow =
    hatchet.new_workflow("order-processing")
    |> hatchet.with_description("Process customer orders")
    |> hatchet.task("validate", fn(ctx) {
      let input = ctx.input
      // Validation logic here
      Ok(dynamic.from(True))
    })
    |> hatchet.task_after("charge", ["validate"], fn(ctx) {
      // Charge payment
      Ok(dynamic.from("charge_123"))
    })
    |> hatchet.task_after("fulfill", ["charge"], fn(ctx) {
      // Fulfill order
      Ok(dynamic.from("shipped"))
    })
    |> hatchet.with_retries(3)
    |> hatchet.with_timeout(30_000)
    |> hatchet.on_failure(fn(ctx) {
      io.println("Failed: " <> ctx.error)
      Ok(Nil)
    })

  // Inspect workflow
  io.println("Workflow: " <> order_workflow.name)
  io.println("Tasks: " <> int.to_string(list.length(order_workflow.tasks)))
}
```

## Next Steps for Full Integration

To enable testing against a running Hatchet server:

1. **Update client.gleam** - Fix gleam_otp/gleam_erlang API usage
2. **Implement HTTP client** - Connect to Hatchet REST endpoints
3. **Implement worker process** - Poll for and execute tasks
4. **Implement run module** - Trigger workflows and poll status
5. **Implement events module** - Publish events to Hatchet

Once complete, full integration test would be:
```gleam
let assert Ok(client) = hatchet.new_client("localhost:7070", "token")
let assert Ok(result) = hatchet.run(client, workflow, dynamic.from("input"))
// Verify result
```
