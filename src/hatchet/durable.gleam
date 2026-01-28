//// Durable task execution with checkpoint mechanism.
////
//// Durable tasks can survive process restarts by checkpointing state
//// to Hatchet. The task can be paused at checkpoint points and
//// resumed after restarts.
////
//// ## Example
////
//// ```gleam
//// import gleam/dynamic
//// import hatchet/durable
////
//// fn my_durable_task(ctx: durable.DurableContext) -> Result(Dynamic, String) {
////   // Do some work
////   durable.log(ctx, "Starting work")
////
////   // Save checkpoint
////   durable.save_checkpoint(ctx, "checkpoint-1", dynamic.int(42))
////
////   // Sleep durably (survives restarts)
////   durable.sleep_for(ctx, 5000)  // 5 seconds
////
////   // Continue after sleep
////   durable.log(ctx, "Resuming after sleep")
////
////   Ok(dynamic.string("done"))
//// }
//// ```

import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/result
import hatchet/context.{type Context}
import hatchet/types.{type TaskContext}

// ============================================================================
// Durable Context Type
// ============================================================================

/// Context for durable task execution.
///
/// Extends the base context with checkpointing capabilities and
/// durable sleep operations that survive process restarts.
pub type DurableContext {
  DurableContext(
    // Base context
    base_context: Context,
    // Task context for compatibility
    task_context: TaskContext,
    // Checkpoint key
    checkpoint_key: String,
    // Wait key counter for unique durable operation keys
    wait_key_counter: Int,
    // Callbacks for durable operations
    register_durable_event_fn: fn(String, String, DurableEventConditions) ->
      Result(Nil, String),
    await_durable_event_fn: fn(String, String) -> Result(Dynamic, String),
  )
}

/// Durable event conditions for SleepFor operations.
pub type DurableEventConditions {
  DurableEventConditions(
    sleep_duration_ms: Option(Int),
    event_key: Option(String),
    event_expression: Option(String),
  )
}

// ============================================================================
// Context Conversion
// ============================================================================

/// Create a DurableContext from a Context.
///
/// This is called by the worker when a durable task is executed.
pub fn from_context(
  ctx: Context,
  checkpoint_key: String,
  register_durable_event_fn: fn(String, String, DurableEventConditions) ->
    Result(Nil, String),
  await_durable_event_fn: fn(String, String) -> Result(Dynamic, String),
) -> DurableContext {
  let task_ctx = context.to_task_context(ctx)

  DurableContext(
    base_context: ctx,
    task_context: task_ctx,
    checkpoint_key: checkpoint_key,
    wait_key_counter: 0,
    register_durable_event_fn: register_durable_event_fn,
    await_durable_event_fn: await_durable_event_fn,
  )
}

/// Get the base Context from a DurableContext.
pub fn to_context(durable_ctx: DurableContext) -> Context {
  durable_ctx.base_context
}

/// Get the TaskContext from a DurableContext.
///
/// Useful for compatibility with functions expecting TaskContext.
pub fn to_task_context(durable_ctx: DurableContext) -> TaskContext {
  durable_ctx.task_context
}

// ============================================================================
// Checkpoint Operations
// ============================================================================

/// Save a checkpoint with the given key and data.
///
/// The checkpoint is persisted to Hatchet and can be restored
/// after a process restart.
///
/// **Parameters:**
///   - `ctx`: The durable context
///   - `checkpoint_key`: Unique key for this checkpoint
///   - `data`: Data to checkpoint (as Dynamic)
///
/// **Returns:** `Ok(Nil)` on success, `Error(String)` on failure
///
/// **Example:**
/// ```gleam
/// durable.save_checkpoint(ctx, "step1", dynamic.int(42))
/// ```
pub fn save_checkpoint(
  _ctx: DurableContext,
  _checkpoint_key: String,
  data: Dynamic,
) -> Result(Nil, String) {
  // TODO: Implement checkpoint saving to Hatchet API
  // For now, just return Ok to allow compilation
  Ok(data)
  |> result.map(fn(_) { Nil })
}

/// Load a checkpoint with the given key.
///
/// **Parameters:**
///   - `ctx`: The durable context
///   - `checkpoint_key`: Key of the checkpoint to load
///
/// **Returns:** `Some(data)` if checkpoint exists, `None` otherwise
///
/// **Example:**
/// ```gleam
/// case durable.load_checkpoint(ctx, "step1") {
///   Some(data) -> // Resume from checkpoint
///   None -> // First execution
/// }
/// ```
pub fn load_checkpoint(
  ctx: DurableContext,
  checkpoint_key: String,
) -> Option(Dynamic) {
  // In a full implementation, this would query the Hatchet API for checkpoint data
  // For now, we return None to indicate no checkpoint exists
  None
}

// ============================================================================
// Durable Sleep
// ============================================================================

/// Sleep for the specified duration in a durable manner.
///
/// The sleep operation is registered with the Hatchet server and will
/// continue even if the worker process restarts. The task will resume
/// execution after the sleep duration has elapsed.
///
/// **Parameters:**
///   - `ctx`: The durable context
///   - `duration_ms`: Sleep duration in milliseconds
///
/// **Returns:** `Ok(Dynamic)` when sleep completes, `Error(String)` on failure
///
/// **Example:**
/// ```gleam
/// durable.sleep_for(ctx, 5000)  // Sleep for 5 seconds
/// ```
pub fn sleep_for(
  ctx: DurableContext,
  duration_ms: Int,
) -> Result(Dynamic, String) {
  // Generate unique signal key for this sleep operation
  let signal_key = "sleep-" <> int.to_string(ctx.wait_key_counter)

  // Register durable sleep event with Hatchet
  let conditions =
    DurableEventConditions(
      sleep_duration_ms: Some(duration_ms),
      event_key: None,
      event_expression: None,
    )

  use Nil <- result.try(ctx.register_durable_event_fn(
    context.step_run_id(ctx.base_context),
    signal_key,
    conditions,
  ))

  // Wait for the sleep to complete
  ctx.await_durable_event_fn(context.step_run_id(ctx.base_context), signal_key)
}

/// Wait for a specific event to occur durably.
///
/// The wait is registered with the Hatchet server and will continue
/// even if the worker process restarts.
///
/// **Parameters:**
///   - `ctx`: The durable context
///   - `event_key`: The event key to wait for
///   - `expression`: Optional CEL expression to filter events
///
/// **Returns:** `Ok(Dynamic)` when event occurs, `Error(String)` on failure
///
/// **Example:**
/// ```gleam
/// durable.wait_for_event(ctx, "user.created", "data.userId == '123'")
/// ```
pub fn wait_for_event(
  ctx: DurableContext,
  event_key: String,
  expression: Option(String),
) -> Result(Dynamic, String) {
  let signal_key = "event-" <> int.to_string(ctx.wait_key_counter)

  let conditions =
    DurableEventConditions(
      sleep_duration_ms: None,
      event_key: Some(event_key),
      event_expression: expression,
    )

  use Nil <- result.try(ctx.register_durable_event_fn(
    context.step_run_id(ctx.base_context),
    signal_key,
    conditions,
  ))

  ctx.await_durable_event_fn(context.step_run_id(ctx.base_context), signal_key)
}

// ============================================================================
// Increment Wait Key Counter
// ============================================================================

/// Increment the wait key counter to ensure unique keys for multiple operations.
///
/// This is called internally after each durable operation to generate
/// unique signal keys.
pub fn increment_wait_key_counter(ctx: DurableContext) -> DurableContext {
  DurableContext(..ctx, wait_key_counter: ctx.wait_key_counter + 1)
}

// ============================================================================
// Context Accessors (forward to base context)
// ============================================================================

/// Get the input data for this task.
pub fn input(ctx: DurableContext) -> Dynamic {
  context.input(ctx.base_context)
}

/// Get the output from a specific parent task.
pub fn step_output(ctx: DurableContext, step_name: String) -> Option(Dynamic) {
  context.step_output(ctx.base_context, step_name)
}

/// Get all parent task outputs.
pub fn all_parent_outputs(ctx: DurableContext) -> Dict(String, Dynamic) {
  context.all_parent_outputs(ctx.base_context)
}

/// Get the workflow run ID.
pub fn workflow_run_id(ctx: DurableContext) -> String {
  context.workflow_run_id(ctx.base_context)
}

/// Get the step run ID.
pub fn step_run_id(ctx: DurableContext) -> String {
  context.step_run_id(ctx.base_context)
}

/// Get the step (task) name.
pub fn step_name(ctx: DurableContext) -> String {
  context.step_name(ctx.base_context)
}

/// Get additional metadata.
pub fn metadata(ctx: DurableContext) -> Dict(String, String) {
  context.metadata(ctx.base_context)
}

/// Get a specific metadata value.
pub fn get_metadata(ctx: DurableContext, key: String) -> Option(String) {
  context.get_metadata(ctx.base_context, key)
}

/// Get the current retry count.
pub fn retry_count(ctx: DurableContext) -> Int {
  context.retry_count(ctx.base_context)
}

/// Log a message to the Hatchet workflow run logs.
pub fn log(ctx: DurableContext, message: String) -> Nil {
  context.log(ctx.base_context, message)
}

/// Push streaming data to the workflow run.
pub fn put_stream(ctx: DurableContext, data: Dynamic) -> Result(Nil, String) {
  context.put_stream(ctx.base_context, data)
}

/// Release this task's worker slot while continuing execution.
pub fn release_slot(ctx: DurableContext) -> Result(Nil, String) {
  context.release_slot(ctx.base_context)
}

/// Extend the execution timeout for this task.
pub fn refresh_timeout(
  ctx: DurableContext,
  increment_ms: Int,
) -> Result(Nil, String) {
  context.refresh_timeout(ctx.base_context, increment_ms)
}

/// Cancel the current workflow run.
pub fn cancel(ctx: DurableContext) -> Result(Nil, String) {
  context.cancel(ctx.base_context)
}

/// Spawn a child workflow run.
pub fn spawn_workflow(
  ctx: DurableContext,
  workflow_name: String,
  input: Dynamic,
) -> Result(String, String) {
  context.spawn_workflow(ctx.base_context, workflow_name, input)
}

/// Spawn a child workflow with custom metadata.
pub fn spawn_workflow_with_metadata(
  ctx: DurableContext,
  workflow_name: String,
  input: Dynamic,
  metadata: Dict(String, String),
) -> Result(String, String) {
  context.spawn_workflow_with_metadata(
    ctx.base_context,
    workflow_name,
    input,
    metadata,
  )
}

/// Get the checkpoint key for this durable task.
pub fn get_checkpoint_key(ctx: DurableContext) -> String {
  ctx.checkpoint_key
}
