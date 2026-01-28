import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process
import gleam/option.{type Option, None, Some}
import hatchet/internal/tls.{type TLSConfig}

pub opaque type Client {
  Client(
    host: String,
    port: Int,
    token: String,
    namespace: Option(String),
    tls_config: TLSConfig,
  )
}

pub fn create_client(
  host: String,
  port: Int,
  token: String,
  namespace: Option(String),
) -> Client {
  Client(
    host: host,
    port: port,
    token: token,
    namespace: namespace,
    tls_config: tls.Insecure,
  )
}

pub fn create_client_with_tls(
  host: String,
  port: Int,
  token: String,
  namespace: Option(String),
  tls_config: TLSConfig,
) -> Client {
  Client(
    host: host,
    port: port,
    token: token,
    namespace: namespace,
    tls_config: tls_config,
  )
}

pub fn get_host(client: Client) -> String {
  client.host
}

pub fn get_port(client: Client) -> Int {
  client.port
}

pub fn get_token(client: Client) -> String {
  client.token
}

pub fn get_namespace(client: Client) -> Option(String) {
  client.namespace
}

pub fn get_tls_config(client: Client) -> TLSConfig {
  client.tls_config
}

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

pub type DurableTaskDef {
  DurableTaskDef(task: TaskDef, checkpoint_key: String)
}

pub type StandaloneTask {
  StandaloneTask(
    name: String,
    handler: fn(TaskContext) -> Result(Dynamic, String),
    retries: Int,
    cron: Option(String),
    events: List(String),
  )
}

pub type TaskContext {
  TaskContext(
    workflow_run_id: String,
    task_run_id: String,
    input: Dynamic,
    parent_outputs: Dict(String, Dynamic),
    metadata: Dict(String, String),
    logger: fn(String) -> Nil,
    // Callbacks to orchestrator
    stream_fn: fn(Dynamic) -> Result(Nil, String),
    release_slot_fn: fn() -> Result(Nil, String),
    refresh_timeout_fn: fn(Int) -> Result(Nil, String),
    cancel_fn: fn() -> Result(Nil, String),
    spawn_workflow_fn: fn(String, Dynamic, Dict(String, String)) ->
      Result(String, String),
  )
}

/// Durable context for tasks that can survive process restarts.
///
/// Extends TaskContext with checkpointing capabilities and
/// durable sleep operations.
pub type DurableContext {
  DurableContext(
    task_context: TaskContext,
    checkpoint_key: String,
    wait_key_counter: Int,
    register_durable_event_fn: fn(String, String, DurableEventConditions) ->
      Result(Nil, String),
    await_durable_event_fn: fn(String, String) -> Result(Dynamic, String),
  )
}

/// Durable event conditions for SleepFor and WaitForEvent operations.
pub type DurableEventConditions {
  DurableEventConditions(
    sleep_duration_ms: Option(Int),
    event_key: Option(String),
    event_expression: Option(String),
  )
}

pub type FailureContext {
  FailureContext(
    workflow_run_id: String,
    failed_task: String,
    error: String,
    input: Dynamic,
  )
}

pub opaque type WorkflowRunRef {
  WorkflowRunRef(run_id: String, client: Client)
}

pub fn create_workflow_run_ref(run_id: String, client: Client) -> WorkflowRunRef {
  WorkflowRunRef(run_id: run_id, client: client)
}

pub fn get_run_id(ref: WorkflowRunRef) -> String {
  ref.run_id
}

pub fn get_ref_client(ref: WorkflowRunRef) -> Client {
  ref.client
}

pub type WorkflowResult(a) {
  WorkflowResult(output: a, run_id: String)
}

pub type TaskResult(a) {
  TaskResult(output: a)
}

pub type ConcurrencyConfig {
  ConcurrencyConfig(max_concurrent: Int, limit_strategy: LimitStrategy)
}

pub type LimitStrategy {
  CancelInProgress
  QueueNew
  DropNew
}

pub type BackoffConfig {
  Exponential(base_ms: Int, max_ms: Int)
  Linear(step_ms: Int, max_ms: Int)
  Constant(delay_ms: Int)
}

pub type RateLimitConfig {
  RateLimitConfig(key: String, units: Int, duration_ms: Int)
}

pub type WaitCondition {
  WaitForEvent(event: String, timeout_ms: Int)
  WaitForTime(duration_ms: Int)
  WaitForExpression(cel: String)
}

pub type WorkerConfig {
  WorkerConfig(
    name: Option(String),
    slots: Int,
    durable_slots: Int,
    labels: Dict(String, String),
  )
}

pub type RunOptions {
  RunOptions(
    metadata: Dict(String, String),
    priority: Option(Int),
    sticky: Bool,
    run_key: Option(String),
  )
}

pub type RunStatus {
  Pending
  Running
  Succeeded
  Failed(error: String)
  Cancelled
}

/// Worker handle for the background worker process.
///
/// The worker process manages:
/// - Connection to the Hatchet dispatcher
/// - Task assignment and execution
/// - Heartbeat and health monitoring
///
/// Internally stores a process ID (Pid) that can receive WorkerMessage
/// from worker_actor.gleam. We store Pid instead of Subject to avoid
/// circular type dependencies between types.gleam and worker_actor.gleam.
pub opaque type Worker {
  Worker(pid: Option(process.Pid), id: String)
}

/// Create a worker with just an ID (for testing/backwards compatibility).
pub fn create_worker(id: String) -> Worker {
  Worker(pid: None, id: id)
}

/// Create a worker with an actor subject (internal use).
///
/// This extracts the Pid from the Subject to store in Worker.
/// The caller (client.gleam) is responsible for using the correct
/// message type when sending to this worker.
pub fn create_worker_with_subject(subject: process.Subject(a)) -> Worker {
  let pid = case process.subject_owner(subject) {
    Ok(owner_pid) -> Some(owner_pid)
    Error(Nil) -> None
  }
  Worker(pid: pid, id: "active-worker")
}

/// Get the worker's process ID if available.
///
/// Used by client.gleam to send messages to the worker actor.
/// The caller must ensure they send the correct message type (WorkerMessage).
pub fn get_worker_pid(worker: Worker) -> Option(process.Pid) {
  worker.pid
}

/// Get the worker ID.
pub fn get_worker_id(worker: Worker) -> String {
  worker.id
}

// Legacy types kept for backwards compatibility
pub type ProcessHandle {
  ProcessHandle(id: String)
}

pub type LegacyWorkerMessage {
  Start
  Stop
  AddWorkflows(List(Workflow))
}

pub type LegacyWorkerState {
  LegacyWorkerState(
    client: Client,
    config: WorkerConfig,
    workflows: List(Workflow),
    running: Bool,
  )
}
