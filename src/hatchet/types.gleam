import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/option.{type Option}

pub opaque type Client {
  Client(host: String, port: Int, token: String, namespace: Option(String))
}

pub fn create_client(
  host: String,
  port: Int,
  token: String,
  namespace: Option(String),
) -> Client {
  Client(host: host, port: port, token: token, namespace: namespace)
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

pub opaque type Worker {
  Worker(process: ProcessHandle)
}

pub fn create_worker(id: String) -> Worker {
  Worker(ProcessHandle(id))
}

pub type ProcessHandle {
  ProcessHandle(id: String)
}

pub type WorkerMessage {
  Start
  Stop
  AddWorkflows(List(Workflow))
}

pub type WorkerState {
  WorkerState(
    client: Client,
    config: WorkerConfig,
    workflows: List(Workflow),
    running: Bool,
  )
}
