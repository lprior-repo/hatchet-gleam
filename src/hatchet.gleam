import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/option
import hatchet/client
import hatchet/context
import hatchet/cron
import hatchet/events
import hatchet/rate_limits
import hatchet/run
import hatchet/schedule
import hatchet/standalone
import hatchet/task
import hatchet/types.{
  type BackoffConfig, type Client, type FailureContext, type LimitStrategy,
  type RateLimitConfig, type RunOptions, type StandaloneTask,
  type SuccessContext, type TaskContext, type TaskDef, type WaitCondition,
  type Worker, type WorkerConfig, type Workflow, type WorkflowRunRef,
}
import hatchet/workflow

// Re-export Context type from the new context module
pub type Context =
  context.Context

pub type Event =
  events.Event

pub fn new(host: String, token: String) {
  client.new(host, token)
}

pub fn with_port(client: Client, port: Int) {
  client.with_port(client, port)
}

pub fn with_namespace(client: Client, namespace: String) {
  client.with_namespace(client, namespace)
}

pub fn new_worker(
  client: Client,
  config: WorkerConfig,
  workflows: List(Workflow),
) {
  client.new_worker(client, config, workflows)
}

pub fn start_worker_blocking(worker: Worker) {
  client.start_worker_blocking(worker)
}

pub fn start_worker(worker: Worker) {
  client.start_worker(worker)
}

/// Stop a running worker gracefully.
pub fn stop_worker(worker: Worker) {
  client.stop_worker(worker)
}

// ============================================================================
// Context Functions (new context module)
// ============================================================================

/// Get the input data for the current task.
pub fn context_input(ctx: Context) {
  context.input(ctx)
}

/// Get output from a parent task by name.
pub fn context_step_output(ctx: Context, step_name: String) {
  context.step_output(ctx, step_name)
}

/// Get all parent task outputs.
pub fn context_all_parent_outputs(ctx: Context) {
  context.all_parent_outputs(ctx)
}

/// Get the current retry count (0 for first attempt).
pub fn context_retry_count(ctx: Context) {
  context.retry_count(ctx)
}

/// Get errors from failed steps in this workflow run.
pub fn context_step_run_errors(ctx: Context) {
  context.step_run_errors(ctx)
}

/// Get error for a specific step by name.
pub fn context_get_step_run_error(ctx: Context, step_name: String) {
  context.get_step_run_error(ctx, step_name)
}

/// Get the workflow run ID.
pub fn context_workflow_run_id(ctx: Context) {
  context.workflow_run_id(ctx)
}

/// Get the step run ID.
pub fn context_step_run_id(ctx: Context) {
  context.step_run_id(ctx)
}

/// Get additional metadata.
pub fn context_metadata(ctx: Context) {
  context.metadata(ctx)
}

/// Get a specific metadata value.
pub fn context_get_metadata(ctx: Context, key: String) {
  context.get_metadata(ctx, key)
}

/// Log a message to the Hatchet workflow run logs.
pub fn context_log(ctx: Context, message: String) {
  context.log(ctx, message)
}

pub fn workflow_new(name: String) {
  workflow.new(name)
}

pub fn workflow_with_description(wf: Workflow, desc: String) {
  workflow.with_description(wf, desc)
}

pub fn workflow_with_version(wf: Workflow, version: String) {
  workflow.with_version(wf, version)
}

pub fn workflow_with_cron(wf: Workflow, cron: String) {
  workflow.with_cron(wf, cron)
}

pub fn workflow_with_events(wf: Workflow, events: List(String)) {
  workflow.with_events(wf, events)
}

pub fn workflow_with_concurrency(
  wf: Workflow,
  max: Int,
  strategy: LimitStrategy,
) {
  workflow.with_concurrency(wf, max, strategy)
}

pub fn workflow_task(
  wf: Workflow,
  name: String,
  handler: fn(TaskContext) -> Result(dynamic.Dynamic, String),
) {
  workflow.task(wf, name, handler)
}

pub fn workflow_task_after(
  wf: Workflow,
  name: String,
  parents: List(String),
  handler: fn(TaskContext) -> Result(dynamic.Dynamic, String),
) {
  workflow.task_after(wf, name, parents, handler)
}

pub fn workflow_with_retries(wf: Workflow, retries: Int) {
  workflow.with_retries(wf, retries)
}

pub fn workflow_with_timeout(wf: Workflow, timeout_ms: Int) {
  workflow.with_timeout(wf, timeout_ms)
}

pub fn workflow_on_failure(
  wf: Workflow,
  handler: fn(FailureContext) -> Result(Nil, String),
) {
  workflow.on_failure(wf, handler)
}

pub fn workflow_on_success(
  wf: Workflow,
  handler: fn(SuccessContext) -> Result(Nil, String),
) {
  workflow.on_success(wf, handler)
}

pub fn workflow_with_retry_backoff(wf: Workflow, backoff: BackoffConfig) {
  workflow.with_retry_backoff(wf, backoff)
}

pub fn workflow_with_schedule_timeout(wf: Workflow, timeout_ms: Int) {
  workflow.with_schedule_timeout(wf, timeout_ms)
}

pub fn workflow_with_rate_limit(
  wf: Workflow,
  key: String,
  units: Int,
  duration_ms: Int,
) {
  workflow.with_rate_limit(wf, key, units, duration_ms)
}

pub fn workflow_with_task_concurrency(
  wf: Workflow,
  max: Int,
  strategy: LimitStrategy,
) {
  workflow.with_task_concurrency(wf, max, strategy)
}

pub fn workflow_with_skip_if(wf: Workflow, predicate: fn(TaskContext) -> Bool) {
  workflow.with_skip_if(wf, predicate)
}

pub fn workflow_with_cancel_if(wf: Workflow, predicate: fn(TaskContext) -> Bool) {
  workflow.with_cancel_if(wf, predicate)
}

pub fn workflow_with_wait_for(wf: Workflow, condition: WaitCondition) {
  workflow.with_wait_for(wf, condition)
}

pub fn task_with_retry_backoff(task: TaskDef, backoff: BackoffConfig) {
  task.with_retry_backoff(task, backoff)
}

pub fn task_with_schedule_timeout(task: TaskDef, timeout_ms: Int) {
  task.with_schedule_timeout(task, timeout_ms)
}

pub fn task_with_rate_limit(task: TaskDef, config: RateLimitConfig) {
  task.with_rate_limit(task, config)
}

pub fn task_with_task_concurrency(
  task: TaskDef,
  max: Int,
  strategy: LimitStrategy,
) {
  task.with_task_concurrency(task, max, strategy)
}

pub fn task_skip_if(wf: Workflow, condition: fn(TaskContext) -> Bool) {
  workflow.with_skip_if(wf, condition)
}

pub fn task_wait_for(wf: Workflow, condition: WaitCondition) {
  workflow.with_wait_for(wf, condition)
}

pub fn exponential_backoff(base_ms: Int, max_ms: Int) {
  task.exponential_backoff(base_ms, max_ms)
}

pub fn linear_backoff(step_ms: Int, max_ms: Int) {
  task.linear_backoff(step_ms, max_ms)
}

pub fn constant_backoff(delay_ms: Int) {
  task.constant_backoff(delay_ms)
}

pub fn rate_limit(key: String, units: Int, duration_ms: Int) {
  task.rate_limit(key, units, duration_ms)
}

pub fn wait_for_event(event: String, timeout_ms: Int) {
  task.wait_for_event(event, timeout_ms)
}

pub fn wait_for_time(duration_ms: Int) {
  task.wait_for_time(duration_ms)
}

pub fn wait_for_expression(cel: String) {
  task.wait_for_expression(cel)
}

pub fn exponential_backoff_default() {
  task.exponential_backoff_default()
}

pub fn linear_backoff_default() {
  task.linear_backoff_default()
}

pub fn constant_backoff_default() {
  task.constant_backoff_default()
}

pub fn get_input(ctx: TaskContext) {
  task.get_input(ctx)
}

pub fn get_parent_output(ctx: TaskContext, task_name: String) {
  task.get_parent_output(ctx, task_name)
}

pub fn get_metadata(ctx: TaskContext, key: String) {
  task.get_metadata(ctx, key)
}

pub fn get_all_metadata(ctx: TaskContext) {
  task.get_all_metadata(ctx)
}

pub fn get_step_run_error(ctx: TaskContext, step_name: String) {
  task.get_step_run_error(ctx, step_name)
}

pub fn log(ctx: TaskContext, message: String) {
  task.log(ctx, message)
}

pub fn get_workflow_run_id(ctx: TaskContext) {
  task.get_workflow_run_id(ctx)
}

pub fn get_task_run_id(ctx: TaskContext) {
  task.get_task_run_id(ctx)
}

pub fn succeed(value: dynamic.Dynamic) {
  task.succeed(value)
}

pub fn fail(error: String) {
  task.fail(error)
}

pub fn map_result(
  result: Result(dynamic.Dynamic, String),
  decoder: fn(dynamic.Dynamic) -> Result(a, decode.DecodeError),
) {
  case result {
    Ok(value) -> {
      case decoder(value) {
        Ok(decoded) -> Ok(decoded)
        Error(_) -> Error("Failed to decode result")
      }
    }
    Error(err) -> Error(err)
  }
}

pub fn standalone(
  name: String,
  handler: fn(TaskContext) -> Result(dynamic.Dynamic, String),
) {
  task.standalone(name, handler)
}

pub fn standalone_with_retries(
  name: String,
  handler: fn(TaskContext) -> Result(dynamic.Dynamic, String),
  retries: Int,
) {
  task.standalone_with_retries(name, handler, retries)
}

pub fn standalone_with_cron(
  name: String,
  handler: fn(TaskContext) -> Result(dynamic.Dynamic, String),
  cron: String,
) {
  task.standalone_with_cron(name, handler, cron)
}

pub fn standalone_with_events(
  name: String,
  handler: fn(TaskContext) -> Result(dynamic.Dynamic, String),
  events: List(String),
) {
  task.standalone_with_events(name, handler, events)
}

pub fn durable(task: TaskDef, checkpoint_key: String) {
  task.durable(task, checkpoint_key)
}

pub fn run(client: Client, workflow: Workflow, input: dynamic.Dynamic) {
  run.run(client, workflow, input)
}

pub fn run_with_options(
  client: Client,
  workflow: Workflow,
  input: dynamic.Dynamic,
  options: RunOptions,
) {
  run.run_with_options(client, workflow, input, options)
}

pub fn run_no_wait(client: Client, workflow: Workflow, input: dynamic.Dynamic) {
  run.run_no_wait(client, workflow, input)
}

pub fn run_no_wait_with_options(
  client: Client,
  workflow: Workflow,
  input: dynamic.Dynamic,
  options: RunOptions,
) {
  run.run_no_wait_with_options(client, workflow, input, options)
}

pub fn run_many(
  client: Client,
  workflow: Workflow,
  inputs: List(dynamic.Dynamic),
) {
  run.run_many(client, workflow, inputs)
}

pub fn await_result(ref: WorkflowRunRef) {
  run.await_result(ref)
}

pub fn get_status(ref: WorkflowRunRef) {
  run.get_status(ref)
}

pub fn cancel(ref: WorkflowRunRef) {
  run.cancel(ref)
}

pub fn worker_config() {
  types.WorkerConfig(
    name: option.None,
    slots: 10,
    durable_slots: 1,
    labels: dict.new(),
  )
}

pub fn worker_with_name(config: WorkerConfig, name: String) {
  types.WorkerConfig(..config, name: option.Some(name))
}

pub fn worker_with_slots(config: WorkerConfig, slots: Int) {
  types.WorkerConfig(..config, slots: slots)
}

pub fn worker_with_durable_slots(config: WorkerConfig, slots: Int) {
  types.WorkerConfig(..config, durable_slots: slots)
}

pub fn worker_with_labels(
  config: WorkerConfig,
  labels: dict.Dict(String, String),
) {
  types.WorkerConfig(..config, labels: labels)
}

pub fn run_options() {
  types.RunOptions(
    metadata: dict.new(),
    priority: option.None,
    sticky: False,
    run_key: option.None,
  )
}

pub fn run_with_metadata(
  options: RunOptions,
  metadata: dict.Dict(String, String),
) {
  types.RunOptions(..options, metadata: metadata)
}

pub fn run_with_priority(options: RunOptions, priority: Int) {
  types.RunOptions(..options, priority: option.Some(priority))
}

pub fn run_with_sticky(options: RunOptions, sticky: Bool) {
  types.RunOptions(..options, sticky: sticky)
}

pub fn run_with_run_key(options: RunOptions, run_key: String) {
  types.RunOptions(..options, run_key: option.Some(run_key))
}

pub fn publish(client: Client, event_key: String, data: dynamic.Dynamic) {
  events.publish(client, event_key, data)
}

pub fn publish_with_metadata(
  client: Client,
  event_key: String,
  data: dynamic.Dynamic,
  metadata: dict.Dict(String, String),
) {
  events.publish_with_metadata(client, event_key, data, metadata)
}

pub fn publish_many(client: Client, events_list: List(Event)) {
  events.publish_many(client, events_list)
}

pub fn event(key: String, data: dynamic.Dynamic) {
  events.event(key, data)
}

pub fn event_with_metadata(event: Event, metadata: dict.Dict(String, String)) {
  events.with_metadata(event, metadata)
}

pub fn event_put_metadata(event: Event, key: String, value: String) {
  events.put_metadata(event, key, value)
}

pub fn new_standalone(
  name: String,
  handler: fn(TaskContext) -> Result(dynamic.Dynamic, String),
) {
  standalone.new_standalone(name, handler)
}

pub fn standalone_with_task_retries(task: StandaloneTask, retries: Int) {
  standalone.with_task_retries(task, retries)
}

pub fn standalone_with_task_cron(task: StandaloneTask, cron: String) {
  standalone.with_task_cron(task, cron)
}

pub fn standalone_with_task_events(task: StandaloneTask, events: List(String)) {
  standalone.with_task_events(task, events)
}

pub fn standalone_to_workflow(task: StandaloneTask) {
  standalone.to_workflow(task)
}

// ============================================================================
// Context Orchestrator Methods
// ============================================================================

/// Push streaming data from within a task.
pub fn context_put_stream(ctx: Context, data: dynamic.Dynamic) {
  context.put_stream(ctx, data)
}

/// Release the worker slot while continuing execution.
pub fn context_release_slot(ctx: Context) {
  context.release_slot(ctx)
}

/// Extend the execution timeout by the given milliseconds.
pub fn context_refresh_timeout(ctx: Context, increment_ms: Int) {
  context.refresh_timeout(ctx, increment_ms)
}

/// Cancel the current workflow run.
pub fn context_cancel(ctx: Context) {
  context.cancel(ctx)
}

/// Spawn a child workflow from within a task handler.
pub fn context_spawn_workflow(
  ctx: Context,
  workflow_name: String,
  input: dynamic.Dynamic,
) {
  context.spawn_workflow(ctx, workflow_name, input)
}

/// Spawn multiple child workflows in a batch.
pub fn context_spawn_workflows(
  ctx: Context,
  workflows: List(context.ChildWorkflowSpec),
) -> List(Result(String, String)) {
  context.spawn_workflows(ctx, workflows)
}

// ============================================================================
// TaskContext Orchestrator Methods
// ============================================================================

/// Push streaming data from TaskContext.
pub fn put_stream(ctx: TaskContext, data: dynamic.Dynamic) {
  task.put_stream(ctx, data)
}

/// Release the worker slot from TaskContext.
pub fn release_slot(ctx: TaskContext) {
  task.release_slot(ctx)
}

/// Extend the execution timeout from TaskContext.
pub fn refresh_timeout(ctx: TaskContext, increment_ms: Int) {
  task.refresh_timeout(ctx, increment_ms)
}

/// Cancel the current workflow run from TaskContext.
pub fn task_cancel(ctx: TaskContext) {
  task.cancel(ctx)
}

/// Spawn a child workflow from TaskContext.
pub fn spawn_workflow(
  ctx: TaskContext,
  workflow_name: String,
  input: dynamic.Dynamic,
) {
  task.spawn_workflow(ctx, workflow_name, input)
}

/// Spawn a child workflow with metadata from TaskContext.
pub fn spawn_workflow_with_metadata(
  ctx: TaskContext,
  workflow_name: String,
  input: dynamic.Dynamic,
  metadata,
) -> Result(String, String) {
  task.spawn_workflow_with_metadata(ctx, workflow_name, input, metadata)
}

/// Spawn multiple child workflows in a batch.
pub fn spawn_workflows(
  ctx: TaskContext,
  workflows: List(context.ChildWorkflowSpec),
) -> List(Result(String, String)) {
  task.spawn_workflows(ctx, workflows)
}

/// Create a child workflow specification.
pub fn child_workflow_spec(
  workflow_name: String,
  input: dynamic.Dynamic,
  metadata,
) -> context.ChildWorkflowSpec {
  context.ChildWorkflowSpec(
    workflow_name: workflow_name,
    input: input,
    metadata: metadata,
  )
}

// ============================================================================
// Bulk Run Management
// ============================================================================

/// Cancel multiple workflow runs at once.
pub fn bulk_cancel(client: Client, run_ids: List(String)) {
  run.bulk_cancel(client, run_ids)
}

/// Replay (re-run) failed workflow runs.
pub fn replay(client: Client, run_ids: List(String)) {
  run.replay(client, run_ids)
}

// ============================================================================
// Cron Management
// ============================================================================

/// Create a named cron trigger for a workflow.
pub fn cron_create(
  client: Client,
  workflow: Workflow,
  name: String,
  expression: String,
  input: dynamic.Dynamic,
) {
  cron.create(client, workflow, name, expression, input)
}

/// Delete a cron trigger by its ID.
pub fn cron_delete(client: Client, cron_id: String) {
  cron.delete(client, cron_id)
}

// ============================================================================
// Schedule Management
// ============================================================================

/// Schedule a one-time workflow run at a specific time.
pub fn schedule_create(
  client: Client,
  workflow: Workflow,
  trigger_at: String,
  input: dynamic.Dynamic,
) {
  schedule.create(client, workflow, trigger_at, input)
}

/// Delete a scheduled run by its ID.
pub fn schedule_delete(client: Client, schedule_id: String) {
  schedule.delete(client, schedule_id)
}

// ============================================================================
// Rate Limit Management
// ============================================================================

pub type RateLimitDuration =
  rate_limits.RateLimitDuration

/// Create or update a rate limit on the server.
pub fn rate_limit_upsert(
  client: Client,
  key: String,
  limit: Int,
  duration: RateLimitDuration,
) {
  rate_limits.upsert(client, key, limit, duration)
}
