# hatchet_port

[![Package Version](https://img.shields.io/hexpm/v/hatchet_port)](https://hex.pm/packages/hatchet_port)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/hatchet_port/)

Gleam SDK for [Hatchet](https://github.com/hatchet-labs/hatchet) - a distributed task orchestration system.

## Features

- **Workflow Definition**: Define workflows with tasks, dependencies, and concurrency controls
- **Task Execution**: Run tasks with automatic retries, backoff strategies, and timeouts
- **Event-Driven**: Trigger workflows from events with cron schedules
- **Standalone Tasks**: Run single tasks as workflows with minimal boilerplate
- **Worker Management**: Create and manage workers with configurable concurrency
- **Context Access**: Access task inputs, outputs, metadata, and logs
- **Child Workflows**: Spawn child workflows from task handlers
- **Streaming Support**: Push streaming data from tasks
- **Durable Tasks**: Checkpoint task state for long-running operations

## Installation

```sh
gleam add hatchet_port@1
```

## Quick Start

```gleam
import gleam/io
import gleam/dynamic
import gleam/option
import hatchet/client
import hatchet/workflow
import hatchet/task
import hatchet/events

pub fn main() -> Nil {
  // Create a client from environment variables
  let assert Ok(cli) = client.from_environment()

  // Define a simple workflow
  let wf = workflow.new("hello-workflow")
    |> workflow.task("greet", fn(ctx) {
      let name = task.get_input(ctx)
        |> dynamic.decode(dynamic.string)
        |> result.unwrap("World")
      task.log(ctx, "Hello, " <> name <> "!")
      task.succeed(dynamic.from(name))
    })

  // Register the workflow
  let assert Ok(_) = client.register_workflow(cli, wf)

  // Create and start a worker
  let cfg = client.worker_config(Some("my-worker"), 5)
  let assert Ok(worker) = client.new_worker(cli, cfg, [wf])
  
  let assert Ok(_) = client.start_worker_blocking(worker)
}
```

## Workflows

Workflows define a series of tasks with dependencies, retries, and timeouts.

```gleam
// Create a workflow with multiple tasks
let wf = workflow.new("data-processing")
  |> workflow.task("fetch", fn(ctx) {
    // Fetch data
    task.succeed(dynamic.from("data"))
  })
  |> workflow.task_after("process", ["fetch"], fn(ctx) {
    // Process data after fetch completes
    case task.get_parent_output(ctx, "fetch") {
      Some(data) -> {
        let result = process_data(data)
        task.succeed(dynamic.from(result))
      }
      None -> task.fail("No data from fetch")
    }
  })
  |> workflow.task_after("save", ["process"], fn(ctx) {
    // Save results
    task.succeed(dynamic.from("saved"))
  })

// Configure workflow behavior
let wf = workflow.new("configured-workflow")
  |> workflow.with_description("Processes and saves data")
  |> workflow.with_version("1.0.0")
  |> workflow.with_cron("0 * * * *") // Run every hour
  |> workflow.with_events(["data.ready", "user.created"])
  |> workflow.task("process", fn(ctx) {
    task.succeed(dynamic.from("done"))
  })
  |> workflow.with_retries(3)
  |> workflow.with_timeout(30_000) // 30 second timeout
```

## Task Configuration

Configure individual tasks with retries, backoff, rate limits, and more.

```gleam
import hatchet/task

let wf = workflow.new("advanced-task")
  |> workflow.task("work", fn(ctx) {
    // Task logic here
    task.succeed(dynamic.from("done"))
  })
  |> workflow.with_retry_backoff(task.exponential_backoff(1000, 60_000))
  |> workflow.with_rate_limit("api", 10, 60_000) // 10 requests per minute
  |> workflow.with_task_concurrency(5, task.GrantInFlight)
  |> workflow.with_skip_if(fn(ctx) {
    // Skip condition
    False
  })
  |> workflow.with_wait_for(task.wait_for_event("external.trigger", 30_000))
```

## Standalone Tasks

Create single-task workflows with minimal setup.

```gleam
import hatchet/task

let standalone_task = task.standalone("simple-task", fn(ctx) {
  task.succeed(dynamic.from("done"))
})

let with_retries = task.standalone_with_retries(
  "retry-task",
  fn(ctx) { task.succeed(dynamic.from("done")) },
  3
)

let with_schedule = task.standalone_with_cron(
  "scheduled-task",
  fn(ctx) { task.succeed(dynamic.from("done")) },
  "0 9 * * 1" // Every Monday at 9 AM
)

let with_events = task.standalone_with_events(
  "event-task",
  fn(ctx) { task.succeed(dynamic.from("done")) },
  ["user.created", "order.placed"]
)
```

## Context Access

Access task inputs, outputs, metadata, and workflow information.

```gleam
fn my_task(ctx: task.TaskContext) -> Result(dynamic.Dynamic, String) {
  // Get input data
  let input = task.get_input(ctx)
  
  // Get parent task output
  let parent_output = task.get_parent_output(ctx, "previous-task")
  
  // Get metadata
  let user_id = task.get_metadata(ctx, "user_id")
  let all_metadata = task.get_all_metadata(ctx)
  
  // Log messages
  task.log(ctx, "Starting task")
  
  // Get IDs
  let workflow_run_id = task.get_workflow_run_id(ctx)
  let task_run_id = task.get_task_run_id(ctx)
  
  task.succeed(dynamic.from("done"))
}
```

## Task Control

Control task execution with timeouts, cancellation, and child workflows.

```gleam
fn advanced_task(ctx: task.TaskContext) -> Result(dynamic.Dynamic, String) {
  // Extend timeout
  let assert Ok(_) = task.refresh_timeout(ctx, 60_000)
  
  // Release worker slot while waiting
  let assert Ok(_) = task.release_slot(ctx)
  
  // Spawn child workflow
  let assert Ok(child_run_id) = task.spawn_workflow(
    ctx,
    "child-workflow",
    dynamic.from("{\"key\":\"value\"}")
  )
  
  // Spawn with custom metadata
  let assert Ok(child_id) = task.spawn_workflow_with_metadata(
    ctx,
    "child-workflow",
    dynamic.from("{}"),
    dict.from_list([#("trace_id", "12345")])
  )
  
  // Cancel workflow if needed
  let assert Ok(_) = task.cancel(ctx)
  
  task.succeed(dynamic.from("done"))
}
```

## Backoff Strategies

Configure retry behavior with different backoff strategies.

```gleam
// Constant backoff: 5 seconds between retries
task.constant_backoff(5_000)

// Linear backoff: +2 seconds each retry, max 60 seconds
task.linear_backoff(2_000, 60_000)

// Exponential backoff: 1 second base, max 60 seconds
task.exponential_backoff(1_000, 60_000)

// Use defaults
task.constant_backoff_default()
task.linear_backoff_default()
task.exponential_backoff_default()
```

## Rate Limiting

Limit task execution rate.

```gleam
let limit = task.rate_limit("api", 10, 60_000)
// 10 requests per 60,000ms (1 minute)

let wf = workflow.new("rate-limited")
  |> workflow.task("api-call", fn(ctx) {
    task.succeed(dynamic.from("done"))
  })
  |> workflow.with_rate_limit("api", 10, 60_000)
```

## Wait Conditions

Configure task to wait for events, time delays, or expressions.

```gleam
// Wait for event
task.wait_for_event("data.ready", 30_000)

// Wait for time
task.wait_for_time(5_000)

// Wait for CEL expression
task.wait_for_expression("input.status == 'ready'")

let wf = workflow.new("waiting-workflow")
  |> workflow.task("poll", fn(ctx) {
    task.succeed(dynamic.from("done"))
  })
  |> workflow.with_wait_for(task.wait_for_event("trigger", 60_000))
```

## Concurrency Control

Limit concurrent executions for workflows and tasks.

```gleam
import hatchet/types.{CancelInFlight, GroupConcurrency}

// Workflow-level concurrency
let wf = workflow.new("concurrent-workflow")
  |> workflow.with_concurrency(10, GroupConcurrency)

// Task-level concurrency
let wf = workflow.new("task-concurrency")
  |> workflow.task("work", fn(ctx) {
    task.succeed(dynamic.from("done"))
  })
  |> workflow.with_task_concurrency(5, CancelInFlight)
```

## Events

Publish events to trigger workflows.

```gleam
import hatchet/events

// Publish simple event
let assert Ok(_) = events.publish(cli, "user.created", dynamic.from("{\"id\":123}"))

// Publish with metadata
let assert Ok(_) = events.publish_with_metadata(
  cli,
  "user.created",
  dynamic.from("{\"id\":123}"),
  dict.from_list([#("source", "web"), #("version", "1.0")])
)

// Create event using builder
let event = events.event("order.placed", dynamic.from("{\"order_id\":456}"))
  |> events.with_metadata(dict.from_list([#("region", "us-west")]))
  |> events.put_metadata("priority", "high")

let assert Ok(_) = events.publish(cli, event.key, event.data)

// Publish multiple events
let events_list = [
  events.event("event1", dynamic.from("{}")),
  events.event("event2", dynamic.from("{}")),
]
let assert Ok(_) = events.publish_many(cli, events_list)
```

## Worker Configuration

Configure and manage workers.

```gleam
// Create worker with custom config
let cfg = client.worker_config(Some("my-worker"), 5)
  |> client.with_worker_labels(dict.from_list([
    #("env", "production"),
    #("zone", "us-west-1")
  ]))

let assert Ok(worker) = client.new_worker(cli, cfg, [workflow1, workflow2])

// Start worker blocking
let assert Ok(_) = client.start_worker_blocking(worker)

// Start worker in background
let assert Ok(shutdown_fn) = client.start_worker(worker)
// Do other work...
shutdown_fn() // Stop worker

// Stop worker explicitly
client.stop_worker(worker)
```

## Client Configuration

Configure clients from environment or programmatically.

```gleam
// From environment variables
let assert Ok(cli) = client.from_environment()

// HATCHET_HOST=localhost
// HATCHET_PORT=7070
// HATCHET_TOKEN=your-token
// HATCHET_NAMESPACE=tenant-id

// Custom client
let assert Ok(cli) = client.new("localhost", "my-token")

// With custom port
let cli = client.with_port(cli, 8080)

// With namespace
let cli = client.with_namespace(cli, "tenant-123")

// From Config record
import hatchet/internal/config

let cfg = config.Config(
  host: "localhost",
  port: 7070,
  grpc_port: 7077,
  token: option.Some("my-token"),
  namespace: option.Some("tenant-123"),
  tls_ca: option.None,
  tls_cert: option.None,
  tls_key: option.None,
)
let assert Ok(cli) = client.with_config(cfg)
```

## Error Handling

All functions return `Result` types for explicit error handling.

```gleam
case client.register_workflow(cli, workflow) {
  Ok(_) -> io.println("Workflow registered")
  Error(err) -> io.println("Failed: " <> err)
}

case task.get_parent_output(ctx, "previous-task") {
  Some(data) -> {
    // Process data
    task.succeed(dynamic.from("done"))
  }
  None -> {
    // Handle missing data
    task.fail("No output from previous task")
  }
}
```

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
gleam format src test  # Format code
gleam build  # Check for warnings
```

## Live Integration Testing

This project includes live integration tests that require a running Hatchet server.

See `docs/LOCAL_SETUP.md` for setup instructions.

```sh
# Run live tests with local Hatchet server
HATCHET_LIVE_TEST=1 HATCHET_CLIENT_TOKEN=<token> gleam test
```

## Further Documentation

Complete API documentation can be found at <https://hexdocs.pm/hatchet_port>.

## License

[MIT](LICENSE)
