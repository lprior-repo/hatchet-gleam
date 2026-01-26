# Build Hatchet SDK for Gleam

You are building a Gleam SDK for Hatchet (https://hatchet.run), an open-source workflow orchestration platform. The SDK must allow Gleam applications to connect to a Hatchet server, define workflows with tasks and dependencies, run workers that execute tasks, and trigger/monitor workflow runs.

## Reference
- Hatchet Go SDK: https://github.com/hatchet-dev/hatchet/tree/main/sdks/go
- Hatchet docs: https://docs.hatchet.run
- License: MIT (fully open source)

## Core Types (src/hatchet/types.gleam)

```gleam
import gleam/dict.{type Dict}
import gleam/option.{type Option}
import gleam/dynamic.{type Dynamic}

/// Opaque client connection
pub opaque type Client {
  Client(
    host: String,
    port: Int,
    token: String,
    namespace: Option(String),
  )
}

/// Workflow definition
pub type Workflow {
  Workflow(
    name: String,
    description: Option(String),
    version: Option(String),
    tasks: List(TaskDef),
    on_failure: Option(fn(FailureContext) -> Result(Nil, String)),
    cron: Option(String),
    events: List(String),
    concurrency: Option(ConcurrencyConfig),
  )
}

/// Task definition within a workflow
pub type TaskDef {
  TaskDef(
    name: String,
    handler: fn(TaskContext) -> Result(Dynamic, String),
    parents: List(String),
    retries: Int,
    retry_backoff: Option(BackoffConfig),
    execution_timeout_ms: Option(Int),
    schedule_timeout_ms: Option(Int),
    rate_limits: List(RateLimitConfig),
    concurrency: Option(ConcurrencyConfig),
    skip_if: Option(fn(TaskContext) -> Bool),
    wait_for: Option(WaitCondition),
  )
}

/// Durable task (survives worker restarts)
pub type DurableTaskDef {
  DurableTaskDef(task: TaskDef, checkpoint_key: String)
}

/// Standalone task (single-task workflow)
pub type StandaloneTask {
  StandaloneTask(
    name: String,
    handler: fn(TaskContext) -> Result(Dynamic, String),
    retries: Int,
    cron: Option(String),
    events: List(String),
  )
}

/// Context passed to task handlers
pub type TaskContext {
  TaskContext(
    workflow_run_id: String,
    task_run_id: String,
    input: Dynamic,
    parent_outputs: Dict(String, Dynamic),
    metadata: Dict(String, String),
    logger: fn(String) -> Nil,
  )
}

/// Context passed to failure handlers
pub type FailureContext {
  FailureContext(
    workflow_run_id: String,
    failed_task: String,
    error: String,
    input: Dynamic,
  )
}

/// Reference to a running workflow
pub opaque type WorkflowRunRef {
  WorkflowRunRef(run_id: String, client: Client)
}

/// Workflow run result
pub type WorkflowResult(a) {
  WorkflowResult(output: a, run_id: String)
}

/// Task result wrapper
pub type TaskResult(a) {
  TaskResult(output: a)
}

/// Concurrency configuration
pub type ConcurrencyConfig {
  ConcurrencyConfig(
    max_concurrent: Int,
    limit_strategy: LimitStrategy,
  )
}

pub type LimitStrategy {
  CancelInProgress
  QueueNew
  DropNew
}

/// Backoff configuration for retries
pub type BackoffConfig {
  Exponential(base_ms: Int, max_ms: Int)
  Linear(step_ms: Int, max_ms: Int)
  Constant(delay_ms: Int)
}

/// Rate limit configuration
pub type RateLimitConfig {
  RateLimitConfig(key: String, units: Int, duration_ms: Int)
}

/// Wait condition for task execution
pub type WaitCondition {
  WaitForEvent(event: String, timeout_ms: Int)
  WaitForTime(duration_ms: Int)
  WaitForExpression(cel: String)
}

/// Worker configuration
pub type WorkerConfig {
  WorkerConfig(
    name: Option(String),
    slots: Int,
    durable_slots: Int,
    labels: Dict(String, String),
  )
}

/// Run options when triggering workflows
pub type RunOptions {
  RunOptions(
    metadata: Dict(String, String),
    priority: Option(Int),
    sticky: Bool,
    run_key: Option(String),
  )
}
```

## Client Module (src/hatchet/client.gleam)

```gleam
import hatchet/types.{type Client, type WorkerConfig, type Workflow}
import gleam/result

/// Create a new Hatchet client
pub fn new(host: String, token: String) -> Result(Client, String)

/// With custom port
pub fn with_port(client: Client, port: Int) -> Client

/// With namespace
pub fn with_namespace(client: Client, namespace: String) -> Client

/// Create a worker from the client
pub fn new_worker(
  client: Client,
  config: WorkerConfig,
  workflows: List(Workflow),
) -> Result(Worker, String)

/// Start worker (blocking)
pub fn start_worker_blocking(worker: Worker) -> Result(Nil, String)

/// Start worker (returns cleanup function)
pub fn start_worker(worker: Worker) -> Result(fn() -> Nil, String)
```

## Workflow Builder (src/hatchet/workflow.gleam)

```gleam
import hatchet/types.{type Workflow, type TaskDef, type TaskContext, type FailureContext, type LimitStrategy}
import gleam/dynamic.{type Dynamic}

/// Create a new workflow
pub fn new(name: String) -> Workflow

/// Add description
pub fn with_description(wf: Workflow, desc: String) -> Workflow

/// Add version
pub fn with_version(wf: Workflow, version: String) -> Workflow

/// Add cron trigger
pub fn with_cron(wf: Workflow, cron: String) -> Workflow

/// Add event triggers
pub fn with_events(wf: Workflow, events: List(String)) -> Workflow

/// Add concurrency config
pub fn with_concurrency(wf: Workflow, max: Int, strategy: LimitStrategy) -> Workflow

/// Add a task to the workflow
pub fn task(
  wf: Workflow,
  name: String,
  handler: fn(TaskContext) -> Result(Dynamic, String),
) -> Workflow

/// Add task with dependencies (parents)
pub fn task_after(
  wf: Workflow,
  name: String,
  parents: List(String),
  handler: fn(TaskContext) -> Result(Dynamic, String),
) -> Workflow

/// Configure retries for last added task
pub fn with_retries(wf: Workflow, retries: Int) -> Workflow

/// Configure timeout for last added task
pub fn with_timeout(wf: Workflow, timeout_ms: Int) -> Workflow

/// Add failure handler
pub fn on_failure(
  wf: Workflow,
  handler: fn(FailureContext) -> Result(Nil, String),
) -> Workflow
```

## Execution Module (src/hatchet/run.gleam)

```gleam
import hatchet/types.{type Client, type Workflow, type WorkflowRunRef, type RunOptions}
import gleam/dynamic.{type Dynamic}

/// Run a workflow and wait for result
pub fn run(client: Client, workflow: Workflow, input: Dynamic) -> Result(Dynamic, String)

/// Run with options
pub fn run_with_options(
  client: Client,
  workflow: Workflow,
  input: Dynamic,
  options: RunOptions,
) -> Result(Dynamic, String)

/// Run without waiting (async)
pub fn run_no_wait(
  client: Client,
  workflow: Workflow,
  input: Dynamic,
) -> Result(WorkflowRunRef, String)

/// Run many workflows in batch
pub fn run_many(
  client: Client,
  workflow: Workflow,
  inputs: List(Dynamic),
) -> Result(List(WorkflowRunRef), String)

/// Get result from a run reference
pub fn await_result(ref: WorkflowRunRef) -> Result(Dynamic, String)

/// Get run status
pub fn get_status(ref: WorkflowRunRef) -> Result(RunStatus, String)

pub type RunStatus {
  Pending
  Running
  Succeeded
  Failed(error: String)
  Cancelled
}

/// Cancel a running workflow
pub fn cancel(ref: WorkflowRunRef) -> Result(Nil, String)
```

## Module Structure

```
src/
├── hatchet.gleam            # Re-exports, convenience functions
├── hatchet/
│   ├── types.gleam          # All types above
│   ├── client.gleam         # Client creation, worker management
│   ├── workflow.gleam       # Workflow builder DSL
│   ├── task.gleam           # Task builder DSL
│   ├── run.gleam            # Execution and monitoring
│   ├── standalone.gleam     # Standalone task helpers
│   ├── events.gleam         # Event publishing
│   └── internal/
│       ├── grpc.gleam       # gRPC client (or HTTP)
│       ├── protocol.gleam   # Wire protocol types
│       └── json.gleam       # JSON serialization
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
  let assert Ok(client) = hatchet.new("localhost:7070", "my-token")

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
    |> workflow.with_retries(3)
    |> workflow.task_after("fulfill", ["charge"], fn(ctx) {
      io.println("Fulfilling order...")
      Ok(dynamic.from("shipped"))
    })
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

## Dependencies (gleam.toml)

```toml
[dependencies]
gleam_stdlib = ">= 0.44.0"
gleam_otp = ">= 0.16.0"
gleam_erlang = ">= 0.34.0"
gleam_json = ">= 2.0.0"
gleam_http = ">= 3.7.0"
gleam_httpc = ">= 3.0.0"
birl = ">= 1.7.0"
```

## Transport Options

Hatchet server uses gRPC. Two options:

1. **HTTP REST API** (simpler): If Hatchet exposes HTTP endpoints, use gleam_httpc
2. **gRPC via Erlang FFI**: Use grpcbox Erlang library via FFI

Start with HTTP if available, add gRPC later.

## Implementation Order

1. types.gleam - All types first
2. internal/json.gleam - JSON encoding/decoding for wire format
3. internal/protocol.gleam - Request/response types
4. client.gleam - Connection management
5. workflow.gleam - Workflow builder DSL
6. task.gleam - Task configuration
7. run.gleam - Execution
8. standalone.gleam - Standalone tasks
9. events.gleam - Event publishing
10. hatchet.gleam - Public API re-exports

## Constraints

1. All functions return Result - no panics, no unwraps
2. Use opaque types for Client, WorkflowRunRef
3. Builder pattern with |> pipes for workflow/task DSL
4. OTP actor for worker (long-running, supervised)
5. Keep handlers typed as `fn(TaskContext) -> Result(Dynamic, String)`
6. Support both sync (run) and async (run_no_wait) execution
7. Functions < 30 lines
8. Pattern matching over conditionals

## Test Against Hatchet Server

Run local Hatchet:
```bash
docker run -p 7070:7070 -p 7071:7071 hatchet/hatchet:latest
```

## Completion Promise

When the SDK can:
1. Connect to Hatchet server
2. Define a multi-task workflow with dependencies
3. Run a worker that executes tasks
4. Trigger a workflow run and get results
5. All tests pass with `gleam test`

Then emit:
<promise>HATCHET_GLEAM_SDK_COMPLETE</promise>
