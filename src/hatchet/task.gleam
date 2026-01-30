import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/list as list_module
import gleam/option
import hatchet/constants
import hatchet/context.{type ChildWorkflowSpec}
import hatchet/standalone
import hatchet/types.{
  type BackoffConfig, type DurableTaskDef, type LimitStrategy,
  type RateLimitConfig, type StandaloneTask, type TaskContext, type TaskDef,
  type WaitCondition, ConcurrencyConfig, Constant, DurableTaskDef, Exponential,
  Linear, RateLimitConfig, TaskDef, WaitForEvent, WaitForExpression, WaitForTime,
}

/// Set the retry backoff strategy for a task.
///
/// **Parameters:**
///   - `task`: The task to configure
///   - `backoff`: The backoff strategy (exponential, linear, or constant)
///
/// **Returns:** The updated task
///
/// **Examples:**
/// ```gleam
/// let config = task.exponential_backoff(1000, 60_000)
/// ```
pub fn with_retry_backoff(task: TaskDef, backoff: BackoffConfig) -> TaskDef {
  TaskDef(..task, retry_backoff: option.Some(backoff))
}

/// Set the schedule timeout for a task.
///
/// This limits how long a task can wait in the queue before being scheduled.
///
/// **Parameters:**
///   - `task`: The task to configure
///   - `timeout_ms`: Schedule timeout in milliseconds
///
/// **Returns:** The updated task
///
/// **Examples:**
/// ```gleam
/// // Task must be scheduled within 5 seconds
/// task.with_schedule_timeout(my_task, 5_000)
/// ```
pub fn with_schedule_timeout(task: TaskDef, timeout_ms: Int) -> TaskDef {
  TaskDef(..task, schedule_timeout_ms: option.Some(timeout_ms))
}

/// Add a rate limit to a task.
///
/// Limits how often the task can execute.
///
/// **Parameters:**
///   - `task`: The task to configure
///   - `config`: Rate limit configuration
///
/// **Returns:** The updated task with rate limit added
///
/// **Examples:**
/// ```gleam
/// let limit = task.rate_limit("api", 10, 60_000)
/// task.with_rate_limit(my_task, limit)
/// ```
pub fn with_rate_limit(task: TaskDef, config: RateLimitConfig) -> TaskDef {
  TaskDef(..task, rate_limits: [config, ..task.rate_limits])
}

/// Set task-level concurrency limits.
///
/// Limits the number of concurrent executions of this specific task.
///
/// **Parameters:**
///   - `task`: The task to configure
///   - `max`: Maximum number of concurrent executions
///   - `strategy`: How to handle exceeding the limit
///
/// **Returns:** The updated task
///
/// **Examples:**
/// ```gleam
/// import hatchet/types.{CancelInFlight}
///
/// task.with_task_concurrency(my_task, 1, CancelInFlight)
/// ```
pub fn with_task_concurrency(
  task: TaskDef,
  max: Int,
  strategy: LimitStrategy,
) -> TaskDef {
  let config = ConcurrencyConfig(max_concurrent: max, limit_strategy: strategy)
  TaskDef(..task, concurrency: option.Some(config))
}

/// Set a condition to skip the task.
///
/// The task will be skipped if the predicate returns True.
///
/// **Parameters:**
///   - `task`: The task to configure
///   - `condition`: Function that determines whether to skip the task
///
/// **Returns:** The updated task
///
/// **Examples:**
/// ```gleam
/// task.skip_if(my_task, fn(ctx) {
///   let flag = task.get_metadata(ctx, "skip")
///   option.unwrap(flag, "false") == "true"
/// })
/// ```
pub fn skip_if(task: TaskDef, condition: fn(TaskContext) -> Bool) -> TaskDef {
  TaskDef(..task, skip_if: option.Some(condition))
}

/// Set a wait condition for the task.
///
/// The task will wait for the condition to be met before executing.
///
/// **Parameters:**
///   - `task`: The task to configure
///   - `condition`: The condition to wait for (event, time, or expression)
///
/// **Returns:** The updated task
///
/// **Examples:**
/// ```gleam
/// let condition = task.wait_for_event("trigger", 60_000)
/// task.wait_for(my_task, condition)
/// ```
pub fn wait_for(task: TaskDef, condition: WaitCondition) -> TaskDef {
  TaskDef(..task, wait_for: option.Some(condition))
}

/// Create an exponential backoff strategy.
///
/// Backoff time doubles on each retry, up to a maximum.
///
/// **Parameters:**
///   - `base_ms`: Initial backoff time in milliseconds
///   - `max_ms`: Maximum backoff time in milliseconds
///
/// **Returns:** An exponential backoff configuration
///
/// **Examples:**
/// ```gleam
/// // Start at 1 second, max 60 seconds
/// task.exponential_backoff(1000, 60_000)
/// // Retries: 1s, 2s, 4s, 8s, 16s, 32s, 60s, 60s, ...
/// ```
pub fn exponential_backoff(base_ms: Int, max_ms: Int) -> BackoffConfig {
  Exponential(base_ms: base_ms, max_ms: max_ms)
}

/// Create a linear backoff strategy.
///
/// Backoff time increases by a fixed amount on each retry.
///
/// **Parameters:**
///   - `step_ms`: Amount to add on each retry
///   - `max_ms`: Maximum backoff time in milliseconds
///
/// **Returns:** A linear backoff configuration
///
/// **Examples:**
/// ```gleam
/// // Add 2 seconds each retry, max 60 seconds
/// task.linear_backoff(2000, 60_000)
/// // Retries: 2s, 4s, 6s, 8s, ..., 60s, 60s, ...
/// ```
pub fn linear_backoff(step_ms: Int, max_ms: Int) -> BackoffConfig {
  Linear(step_ms: step_ms, max_ms: max_ms)
}

/// Create a constant backoff strategy.
///
/// The same delay is used for all retries.
///
/// **Parameters:**
///   - `delay_ms`: Constant delay in milliseconds
///
/// **Returns:** A constant backoff configuration
///
/// **Examples:**
/// ```gleam
/// // Always wait 5 seconds between retries
/// task.constant_backoff(5_000)
/// // Retries: 5s, 5s, 5s, ...
/// ```
pub fn constant_backoff(delay_ms: Int) -> BackoffConfig {
  Constant(delay_ms: delay_ms)
}

/// Create a rate limit configuration.
///
/// Limits task execution rate.
///
/// **Parameters:**
///   - `key`: A unique key for the rate limit (e.g., "api", "database")
///   - `units`: Number of allowed executions
///   - `duration_ms`: Time window in milliseconds
///
/// **Returns:** A rate limit configuration
///
/// **Examples:**
/// ```gleam
/// // 10 requests per minute
/// task.rate_limit("api", 10, 60_000)
///
/// // 1 request per second
/// task.rate_limit("database", 1, 1000)
/// ```
pub fn rate_limit(key: String, units: Int, duration_ms: Int) -> RateLimitConfig {
  RateLimitConfig(key: key, units: units, duration_ms: duration_ms)
}

/// Create a wait condition for an event.
///
/// The task will wait for the specified event to be published.
///
/// **Parameters:**
///   - `event`: The event key to wait for
///   - `timeout_ms`: Maximum time to wait in milliseconds
///
/// **Returns:** A wait condition for events
///
/// **Examples:**
/// ```gleam
/// // Wait for "data.ready" event, timeout after 1 minute
/// task.wait_for_event("data.ready", 60_000)
/// ```
pub fn wait_for_event(event: String, timeout_ms: Int) -> WaitCondition {
  WaitForEvent(event: event, timeout_ms: timeout_ms)
}

/// Create a wait condition for a time delay.
///
/// The task will wait for the specified duration before executing.
///
/// **Parameters:**
///   - `duration_ms`: Time to wait in milliseconds
///
/// **Returns:** A wait condition for time delays
///
/// **Examples:**
/// ```gleam
/// // Wait 5 seconds before executing
/// task.wait_for_time(5_000)
/// ```
pub fn wait_for_time(duration_ms: Int) -> WaitCondition {
  WaitForTime(duration_ms: duration_ms)
}

/// Create a wait condition for a CEL expression.
///
/// The task will wait for the expression to evaluate to true.
///
/// **Parameters:**
///   - `cel`: A CEL expression string
///
/// **Returns:** A wait condition for expressions
///
/// **Examples:**
/// ```gleam
/// // Wait until input.status is "ready"
/// task.wait_for_expression("input.status == 'ready'")
/// ```
pub fn wait_for_expression(cel: String) -> WaitCondition {
  WaitForExpression(cel: cel)
}

/// Get an exponential backoff with default values.
///
/// Uses sensible defaults: 1 second base, 60 second max.
///
/// **Returns:** An exponential backoff configuration
///
/// **Examples:**
/// ```gleam
/// let backoff = task.exponential_backoff_default()
/// ```
pub fn exponential_backoff_default() -> BackoffConfig {
  exponential_backoff(
    constants.default_base_backoff_ms,
    constants.default_max_backoff_ms,
  )
}

/// Get a linear backoff with default values.
///
/// Uses sensible defaults: 2 second step, 60 second max.
///
/// **Returns:** A linear backoff configuration
///
/// **Examples:**
/// ```gleam
/// let backoff = task.linear_backoff_default()
/// ```
pub fn linear_backoff_default() -> BackoffConfig {
  linear_backoff(
    constants.default_linear_backoff_step_ms,
    constants.default_max_backoff_ms,
  )
}

/// Get a constant backoff with default values.
///
/// Uses sensible default: 1 second delay.
///
/// **Returns:** A constant backoff configuration
///
/// **Examples:**
/// ```gleam
/// let backoff = task.constant_backoff_default()
/// ```
pub fn constant_backoff_default() -> BackoffConfig {
  constant_backoff(constants.default_constant_backoff_ms)
}

/// Get the input data for the current task.
///
/// **Parameters:**
///   - `ctx`: The task context
///
/// **Returns:** The input data as a Dynamic value
///
/// **Examples:**
/// ```gleam
/// let input = task.get_input(ctx)
/// let decoded = dynamic.decode(input, dynamic.string)
/// ```
pub fn get_input(ctx: TaskContext) -> Dynamic {
  ctx.input
}

/// Get the output of a parent task.
///
/// **Parameters:**
///   - `ctx`: The task context
///   - `task_name`: The name of the parent task
///
/// **Returns:** `Some(output)` if the task completed, `None` otherwise
///
/// **Examples:**
/// ```gleam
/// case task.get_parent_output(ctx, "fetch") {
///   Some(data) -> {
///     // Process data
///   }
///   None -> {
///     // Handle missing data
///   }
/// }
/// ```
pub fn get_parent_output(
  ctx: TaskContext,
  task_name: String,
) -> option.Option(Dynamic) {
  case dict.get(ctx.parent_outputs, task_name) {
    Ok(value) -> option.Some(value)
    Error(_) -> option.None
  }
}

/// Get a metadata value by key.
///
/// **Parameters:**
///   - `ctx`: The task context
///   - `key`: The metadata key
///
/// **Returns:** `Some(value)` if the key exists, `None` otherwise
///
/// **Examples:**
/// ```gleam
/// case task.get_metadata(ctx, "user_id") {
///   Some(id) -> io.println("User: " <> id)
///   None -> io.println("No user ID")
/// }
/// ```
pub fn get_metadata(ctx: TaskContext, key: String) -> option.Option(String) {
  case dict.get(ctx.metadata, key) {
    Ok(value) -> option.Some(value)
    Error(_) -> option.None
  }
}

/// Get all metadata for the current task.
///
/// **Parameters:**
///   - `ctx`: The task context
///
/// **Returns:** A dictionary of all metadata
///
/// **Examples:**
/// ```gleam
/// let metadata = task.get_all_metadata(ctx)
/// dict.each(metadata, fn(key, value) {
///   io.println(key <> ": " <> value)
/// })
/// ```
pub fn get_all_metadata(ctx: TaskContext) -> Dict(String, String) {
  ctx.metadata
}

/// Log a message from within a task.
///
/// The message will appear in the Hatchet dashboard and logs.
///
/// **Parameters:**
///   - `ctx`: The task context
///   - `message`: The message to log
///
/// **Returns:** Nil
///
/// **Examples:**
/// ```gleam
/// task.log(ctx, "Processing started")
/// ```
pub fn log(ctx: TaskContext, message: String) {
  ctx.logger(message)
}

/// Get the workflow run ID for the current task.
///
/// **Parameters:**
///   - `ctx`: The task context
///
/// **Returns:** The workflow run ID
///
/// **Examples:**
/// ```gleam
/// let run_id = task.get_workflow_run_id(ctx)
/// io.println("Run ID: " <> run_id)
/// ```
pub fn get_workflow_run_id(ctx: TaskContext) -> String {
  ctx.workflow_run_id
}

/// Get the task run ID for the current task.
///
/// **Parameters:**
///   - `ctx`: The task context
///
/// **Returns:** The task run ID
///
/// **Examples:**
/// ```gleam
/// let task_id = task.get_task_run_id(ctx)
/// io.println("Task ID: " <> task_id)
/// ```
pub fn get_task_run_id(ctx: TaskContext) -> String {
  ctx.task_run_id
}

/// Get errors from failed steps in this workflow run.
///
/// This is primarily used in on-failure handlers to inspect
/// which steps failed and what errors they produced. Only available
/// in engine versions v0.53.10 and later.
///
/// **Parameters:**
///   - `ctx`: The task context
///
/// **Returns:** A dictionary mapping step names to error messages
///
/// **Examples:**
/// ```gleam
/// let errors = task.get_step_run_errors(ctx)
/// dict.each(errors, fn(step_name, error_msg) {
///   task.log(ctx, step_name <> " failed: " <> error_msg)
/// })
/// ```
pub fn get_step_run_errors(ctx: TaskContext) -> Dict(String, String) {
  ctx.step_run_errors
}

/// Get error for a specific step by name.
///
/// Returns `Some(error_message)` if the step failed,
/// or `None` if the step didn't fail or doesn't exist.
///
/// This is primarily used in on-failure handlers to inspect
/// specific step failures.
pub fn get_step_run_error(
  ctx: TaskContext,
  step_name: String,
) -> option.Option(String) {
  case dict.get(ctx.step_run_errors, step_name) {
    Ok(value) -> option.Some(value)
    Error(_) -> option.None
  }
}

/// Push streaming data from within a task handler.
///
/// Allows tasks to stream incremental results to clients.
///
/// **Parameters:**
///   - `ctx`: The task context
///   - `data`: The streaming data
///
/// **Returns:** `Ok(Nil)` on success, `Error(String)` on failure
///
/// **Examples:**
/// ```gleam
/// task.put_stream(ctx, dynamic.from("{\"progress\": 0.1}"))
/// ```
pub fn put_stream(ctx: TaskContext, data: Dynamic) -> Result(Nil, String) {
  ctx.stream_fn(data)
}

/// Release the worker slot while continuing execution.
///
/// Useful for long-running tasks that are waiting on external resources.
/// This frees up the worker slot for other tasks while waiting.
///
/// **Parameters:**
///   - `ctx`: The task context
///
/// **Returns:** `Ok(Nil)` on success, `Error(String)` on failure
///
/// **Examples:**
/// ```gleam
/// // Wait for external callback without blocking worker
/// let assert Ok(_) = task.release_slot(ctx)
/// // ... wait for external event ...
/// task.succeed(dynamic.from("done"))
/// ```
pub fn release_slot(ctx: TaskContext) -> Result(Nil, String) {
  ctx.release_slot_fn()
}

/// Extend the execution timeout by the given milliseconds.
///
/// Use this for long-running tasks that need more time.
///
/// **Parameters:**
///   - `ctx`: The task context
///   - `increment_ms`: Additional milliseconds to add to timeout
///
/// **Returns:** `Ok(Nil)` on success, `Error(String)` on failure
///
/// **Examples:**
/// ```gleam
/// // Add another 5 minutes to the timeout
/// let assert Ok(_) = task.refresh_timeout(ctx, 300_000)
/// ```
pub fn refresh_timeout(
  ctx: TaskContext,
  increment_ms: Int,
) -> Result(Nil, String) {
  ctx.refresh_timeout_fn(increment_ms)
}

/// Cancel the current workflow run.
///
/// All in-progress tasks will be stopped, and no further tasks will run.
///
/// **Parameters:**
///   - `ctx`: The task context
///
/// **Returns:** `Ok(Nil)` on success, `Error(String)` on failure
///
/// **Examples:**
/// ```gleam
/// case check_condition(ctx) {
///   True -> task.succeed(dynamic.from("done"))
///   False -> task.cancel(ctx)
/// }
/// ```
pub fn cancel(ctx: TaskContext) -> Result(Nil, String) {
  ctx.cancel_fn()
}

/// Spawn a child workflow from within a task handler.
///
/// The child workflow runs independently and the parent task does not wait for it.
/// Returns the child workflow run ID on success.
///
/// **Parameters:**
///   - `ctx`: The task context
///   - `workflow_name`: Name of the workflow to spawn
///   - `input`: Input data for the child workflow
///
/// **Returns:** `Ok(run_id)` on success, `Error(String)` on failure
///
/// **Examples:**
/// ```gleam
/// let assert Ok(child_id) = task.spawn_workflow(
///   ctx,
///   "child-workflow",
///   dynamic.from("{\"key\":\"value\"}")
/// )
/// ```
pub fn spawn_workflow(
  ctx: TaskContext,
  workflow_name: String,
  input: Dynamic,
) -> Result(String, String) {
  ctx.spawn_workflow_fn(workflow_name, input, ctx.metadata)
}

/// Spawn a child workflow with custom metadata.
///
/// The metadata from the current workflow is merged with the provided metadata.
/// The provided metadata takes precedence on key conflicts.
///
/// **Parameters:**
///   - `ctx`: The task context
///   - `workflow_name`: Name of the workflow to spawn
///   - `input`: Input data for the child workflow
///   - `metadata`: Additional metadata for the child workflow
///
/// **Returns:** `Ok(run_id)` on success, `Error(String)` on failure
///
/// **Examples:**
/// ```gleam
/// let assert Ok(child_id) = task.spawn_workflow_with_metadata(
///   ctx,
///   "child-workflow",
///   dynamic.from("{}"),
///   dict.from_list([#("trace_id", "12345")])
/// )
/// ```
pub fn spawn_workflow_with_metadata(
  ctx: TaskContext,
  workflow_name: String,
  input: Dynamic,
  metadata: Dict(String, String),
) -> Result(String, String) {
  let merged = dict.merge(ctx.metadata, metadata)
  ctx.spawn_workflow_fn(workflow_name, input, merged)
}

/// Spawn multiple child workflows in a batch.
///
/// This is more efficient than calling spawn_workflow multiple times
/// as it sends all spawns in a single request to Hatchet.
///
/// **Parameters:**
///   - `ctx`: The task context
///   - `workflows`: List of child workflow specifications
///
/// **Returns:** List of results, each being Ok(run_id) or Error(String)
///
/// **Examples:**
/// ```gleam
/// let specs = [
///   task.child_workflow_spec(
///     "process-payment",
///     dynamic.from("{\"amount\":100}"),
///     dict.from_list([#("source", "web")]),
///   ),
///   task.child_workflow_spec(
///     "send-receipt",
///     dynamic.from("{\"email\":\"user@example.com\""),
///     dict.new(),
///   ),
/// ]
///
/// case task.spawn_workflows(ctx, specs) {
///   [Ok(id1), Ok(id2), ..] -> // All spawned
///   [Ok(id1), Error(e), ..] -> io.println("Failed: " <> e)
///   [Error(e), ..] -> io.println("All failed: " <> e)
/// }
/// ```
pub fn spawn_workflows(
  ctx: TaskContext,
  workflows: List(ChildWorkflowSpec),
) -> List(Result(String, String)) {
  list_module.map(workflows, fn(spec) {
    let merged = dict.merge(ctx.metadata, spec.metadata)
    ctx.spawn_workflow_fn(spec.workflow_name, spec.input, merged)
  })
}

/// Create a child workflow specification for batch spawning.
///
/// **Parameters:**
///   - `workflow_name`: Name of the workflow to spawn
///   - `input`: Input data for the child workflow
///   - `metadata`: Additional metadata for the child workflow
///
/// **Returns:** A `ChildWorkflowSpec` that can be used with `spawn_workflows`
///
/// **Examples:**
/// ```gleam
/// let spec = task.child_workflow_spec(
///   "child-workflow",
///   dynamic.from("{\"key\":\"value\"}"),
///   dict.from_list([#("trace_id", "12345")])
/// )
/// ```
pub fn child_workflow_spec(
  workflow_name: String,
  input: Dynamic,
  metadata: Dict(String, String),
) -> context.ChildWorkflowSpec {
  context.ChildWorkflowSpec(
    workflow_name: workflow_name,
    input: input,
    metadata: metadata,
  )
}

/// Return a successful task result.
///
/// Use this to indicate the task completed successfully.
///
/// **Parameters:**
///   - `value`: The task output data
///
/// **Returns:** A `Result` indicating success
///
/// **Examples:**
/// ```gleam
/// task.succeed(dynamic.from("{\"status\":\"complete\"}"))
/// ```
pub fn succeed(value: Dynamic) -> Result(Dynamic, String) {
  Ok(value)
}

/// Return a failed task result.
///
/// Use this to indicate the task failed.
///
/// **Parameters:**
///   - `error`: Error message describing the failure
///
/// **Returns:** A `Result` indicating failure
///
/// **Examples:**
/// ```gleam
/// task.fail("Invalid input data")
/// ```
pub fn fail(error: String) -> Result(Dynamic, String) {
  Error(error)
}

/// Map a Dynamic result through a decoder.
///
/// Useful for decoding task results into typed values.
///
/// **Parameters:**
///   - `result`: The result to map
///   - `decoder`: A function to decode the Dynamic value
///
/// **Returns:** Decoded value or error
///
/// **Examples:**
/// ```gleam
/// let result: Result(Dynamic, String) = task.succeed(dynamic.from("42"))
/// task.map_result(result, dynamic.int)
/// // Returns Ok(42)
/// ```
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

/// Create a standalone task with no additional configuration.
///
/// Standalone tasks are single-task workflows that can be used without
/// creating a full workflow object.
///
/// **Parameters:**
///   - `name`: Task name
///   - `handler`: Function to execute for this task
///
/// **Returns:** A `StandaloneTask` ready to be converted to a workflow
///
/// **Examples:**
/// ```gleam
/// let task = task.standalone("simple-task", fn(ctx) {
///   task.succeed(dynamic.from("done"))
/// })
/// ```
pub fn standalone(
  name: String,
  handler: fn(TaskContext) -> Result(Dynamic, String),
) -> StandaloneTask {
  standalone.new_standalone(name, handler)
}

/// Create a standalone task with retry configuration.
///
/// **Parameters:**
///   - `name`: Task name
///   - `handler`: Function to execute for this task
///   - `retries`: Number of retry attempts on failure
///
/// **Returns:** A `StandaloneTask` with retry configuration
///
/// **Examples:**
/// ```gleam
/// let task = task.standalone_with_retries(
///   "retry-task",
///   fn(ctx) { task.succeed(dynamic.from("done")) },
///   3
/// )
/// ```
pub fn standalone_with_retries(
  name: String,
  handler: fn(TaskContext) -> Result(Dynamic, String),
  retries: Int,
) -> StandaloneTask {
  let task = standalone.new_standalone(name, handler)
  standalone.with_task_retries(task, retries)
}

/// Create a standalone task with a cron schedule.
///
/// **Parameters:**
///   - `name`: Task name
///   - `handler`: Function to execute for this task
///   - `cron`: Cron expression for scheduling
///
/// **Returns:** A `StandaloneTask` with cron schedule
///
/// **Examples:**
/// ```gleam
/// // Run every hour
/// let task = task.standalone_with_cron(
///   "hourly-task",
///   fn(ctx) { task.succeed(dynamic.from("done")) },
///   "0 * * * *"
/// )
/// ```
pub fn standalone_with_cron(
  name: String,
  handler: fn(TaskContext) -> Result(Dynamic, String),
  cron: String,
) -> StandaloneTask {
  let task = standalone.new_standalone(name, handler)
  standalone.with_task_cron(task, cron)
}

/// Create a standalone task with event triggers.
///
/// **Parameters:**
///   - `name`: Task name
///   - `handler`: Function to execute for this task
///   - `events`: List of event keys that trigger this task
///
/// **Returns:** A `StandaloneTask` with event triggers
///
/// **Examples:**
/// ```gleam
/// let task = task.standalone_with_events(
///   "event-task",
///   fn(ctx) { task.succeed(dynamic.from("done")) },
///   ["user.created", "order.placed"]
/// )
/// ```
pub fn standalone_with_events(
  name: String,
  handler: fn(TaskContext) -> Result(Dynamic, String),
  events: List(String),
) -> StandaloneTask {
  let task = standalone.new_standalone(name, handler)
  standalone.with_task_events(task, events)
}

/// Create a durable task with checkpointing.
///
/// Durable tasks can survive process restarts through checkpointing.
/// The checkpoint_key is used to persist task state.
///
/// **Parameters:**
///   - `task`: The task definition
///   - `checkpoint_key`: Unique key for checkpointing state
///
/// **Returns:** A `DurableTaskDef` that can be used in workflows
///
/// **Examples:**
/// ```gleam
/// let task = workflow.task("long-running", fn(ctx) {
///   // Task logic here
///   task.succeed(dynamic.from("done"))
/// })
/// let durable_task = task.durable(task, "my-checkpoint")
/// ```
pub fn durable(task: TaskDef, checkpoint_key: String) -> DurableTaskDef {
  DurableTaskDef(task: task, checkpoint_key: checkpoint_key)
}
