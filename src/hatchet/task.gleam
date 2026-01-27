import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/option
import hatchet/constants
import hatchet/standalone
import hatchet/types.{
  type BackoffConfig, type DurableTaskDef, type LimitStrategy,
  type RateLimitConfig, type StandaloneTask, type TaskContext, type TaskDef,
  type WaitCondition, ConcurrencyConfig, Constant, DurableTaskDef, Exponential,
  Linear, RateLimitConfig, TaskDef, WaitForEvent, WaitForExpression, WaitForTime,
}

pub fn with_retry_backoff(task: TaskDef, backoff: BackoffConfig) -> TaskDef {
  TaskDef(..task, retry_backoff: option.Some(backoff))
}

pub fn with_schedule_timeout(task: TaskDef, timeout_ms: Int) -> TaskDef {
  TaskDef(..task, schedule_timeout_ms: option.Some(timeout_ms))
}

pub fn with_rate_limit(task: TaskDef, config: RateLimitConfig) -> TaskDef {
  TaskDef(..task, rate_limits: [config, ..task.rate_limits])
}

pub fn with_task_concurrency(
  task: TaskDef,
  max: Int,
  strategy: LimitStrategy,
) -> TaskDef {
  let config = ConcurrencyConfig(max_concurrent: max, limit_strategy: strategy)
  TaskDef(..task, concurrency: option.Some(config))
}

pub fn skip_if(task: TaskDef, condition: fn(TaskContext) -> Bool) -> TaskDef {
  TaskDef(..task, skip_if: option.Some(condition))
}

pub fn wait_for(task: TaskDef, condition: WaitCondition) -> TaskDef {
  TaskDef(..task, wait_for: option.Some(condition))
}

pub fn exponential_backoff(base_ms: Int, max_ms: Int) -> BackoffConfig {
  Exponential(base_ms: base_ms, max_ms: max_ms)
}

pub fn linear_backoff(step_ms: Int, max_ms: Int) -> BackoffConfig {
  Linear(step_ms: step_ms, max_ms: max_ms)
}

pub fn constant_backoff(delay_ms: Int) -> BackoffConfig {
  Constant(delay_ms: delay_ms)
}

pub fn rate_limit(key: String, units: Int, duration_ms: Int) -> RateLimitConfig {
  RateLimitConfig(key: key, units: units, duration_ms: duration_ms)
}

pub fn wait_for_event(event: String, timeout_ms: Int) -> WaitCondition {
  WaitForEvent(event: event, timeout_ms: timeout_ms)
}

pub fn wait_for_time(duration_ms: Int) -> WaitCondition {
  WaitForTime(duration_ms: duration_ms)
}

pub fn wait_for_expression(cel: String) -> WaitCondition {
  WaitForExpression(cel: cel)
}

pub fn exponential_backoff_default() -> BackoffConfig {
  exponential_backoff(
    constants.default_base_backoff_ms,
    constants.default_max_backoff_ms,
  )
}

pub fn linear_backoff_default() -> BackoffConfig {
  linear_backoff(
    constants.default_linear_backoff_step_ms,
    constants.default_max_backoff_ms,
  )
}

pub fn constant_backoff_default() -> BackoffConfig {
  constant_backoff(constants.default_constant_backoff_ms)
}

pub fn get_input(ctx: TaskContext) -> Dynamic {
  ctx.input
}

pub fn get_parent_output(
  ctx: TaskContext,
  task_name: String,
) -> option.Option(Dynamic) {
  case dict.get(ctx.parent_outputs, task_name) {
    Ok(value) -> option.Some(value)
    Error(_) -> option.None
  }
}

pub fn get_metadata(ctx: TaskContext, key: String) -> option.Option(String) {
  case dict.get(ctx.metadata, key) {
    Ok(value) -> option.Some(value)
    Error(_) -> option.None
  }
}

pub fn get_all_metadata(ctx: TaskContext) -> Dict(String, String) {
  ctx.metadata
}

pub fn log(ctx: TaskContext, message: String) {
  ctx.logger(message)
}

pub fn get_workflow_run_id(ctx: TaskContext) -> String {
  ctx.workflow_run_id
}

pub fn get_task_run_id(ctx: TaskContext) -> String {
  ctx.task_run_id
}

/// Push streaming data from within a task handler.
pub fn put_stream(ctx: TaskContext, data: Dynamic) -> Result(Nil, String) {
  ctx.stream_fn(data)
}

/// Release the worker slot while continuing execution.
/// Useful for long-running tasks waiting on external resources.
pub fn release_slot(ctx: TaskContext) -> Result(Nil, String) {
  ctx.release_slot_fn()
}

/// Extend the execution timeout by the given milliseconds.
pub fn refresh_timeout(
  ctx: TaskContext,
  increment_ms: Int,
) -> Result(Nil, String) {
  ctx.refresh_timeout_fn(increment_ms)
}

/// Cancel the current workflow run.
pub fn cancel(ctx: TaskContext) -> Result(Nil, String) {
  ctx.cancel_fn()
}

/// Spawn a child workflow from within a task handler.
/// Returns the child workflow run ID on success.
pub fn spawn_workflow(
  ctx: TaskContext,
  workflow_name: String,
  input: Dynamic,
) -> Result(String, String) {
  ctx.spawn_workflow_fn(workflow_name, input, ctx.metadata)
}

/// Spawn a child workflow with custom metadata.
pub fn spawn_workflow_with_metadata(
  ctx: TaskContext,
  workflow_name: String,
  input: Dynamic,
  metadata: Dict(String, String),
) -> Result(String, String) {
  let merged = dict.merge(ctx.metadata, metadata)
  ctx.spawn_workflow_fn(workflow_name, input, merged)
}

pub fn succeed(value: Dynamic) -> Result(Dynamic, String) {
  Ok(value)
}

pub fn fail(error: String) -> Result(Dynamic, String) {
  Error(error)
}

pub fn map_result(
  result: Result(Dynamic, String),
  decoder: fn(Dynamic) -> Result(a, b),
) -> Result(a, String) {
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
  handler: fn(TaskContext) -> Result(Dynamic, String),
) -> StandaloneTask {
  standalone.new_standalone(name, handler)
}

pub fn standalone_with_retries(
  name: String,
  handler: fn(TaskContext) -> Result(Dynamic, String),
  retries: Int,
) -> StandaloneTask {
  let task = standalone.new_standalone(name, handler)
  standalone.with_task_retries(task, retries)
}

pub fn standalone_with_cron(
  name: String,
  handler: fn(TaskContext) -> Result(Dynamic, String),
  cron: String,
) -> StandaloneTask {
  let task = standalone.new_standalone(name, handler)
  standalone.with_task_cron(task, cron)
}

pub fn standalone_with_events(
  name: String,
  handler: fn(TaskContext) -> Result(Dynamic, String),
  events: List(String),
) -> StandaloneTask {
  let task = standalone.new_standalone(name, handler)
  standalone.with_task_events(task, events)
}

pub fn durable(task: TaskDef, checkpoint_key: String) -> DurableTaskDef {
  DurableTaskDef(task: task, checkpoint_key: checkpoint_key)
}
