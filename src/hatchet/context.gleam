//// Task execution context providing access to workflow data and operations.
////
//// The `Context` type is passed to every task handler and provides:
//// - Access to task input data
//// - Access to outputs from parent tasks
//// - Workflow and task identifiers
//// - Logging capabilities
//// - Retry information
////
//// ## Example
////
//// ```gleam
//// fn my_task_handler(ctx: context.Context) -> Result(Dynamic, String) {
////   // Get the input data
////   let input = context.input(ctx)
////
////   // Get output from a parent task
////   case context.step_output(ctx, "validate") {
////     Some(parent_data) -> {
////       // Process with parent data
////       context.log(ctx, "Processing with parent data")
////       Ok(dynamic.from("result"))
////     }
////     None -> Error("Missing parent output")
////   }
//// }
//// ```

import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None, Some}
import hatchet/internal/ffi/protobuf

// ============================================================================
// Context Type
// ============================================================================

/// The execution context passed to task handlers.
///
/// Contains all information needed to execute a task, including input data,
/// parent outputs, and metadata. Also provides methods for interacting with
/// the Hatchet orchestrator (streaming, timeout refresh, cancellation).
pub type Context {
  Context(
    // Identifiers
    workflow_run_id: String,
    step_run_id: String,
    worker_id: String,
    // Task info
    step_name: String,
    action_id: String,
    job_id: String,
    job_run_id: String,
    // Data
    input: Dynamic,
    parent_outputs: Dict(String, Dynamic),
    additional_metadata: Dict(String, String),
    // Retry info
    retry_count: Int,
    // Callbacks to the worker/server
    log_fn: fn(String) -> Nil,
    stream_fn: fn(Dynamic) -> Result(Nil, String),
    release_slot_fn: fn() -> Result(Nil, String),
    refresh_timeout_fn: fn(Int) -> Result(Nil, String),
    cancel_fn: fn() -> Result(Nil, String),
    // Child workflow spawning
    spawn_workflow_fn: fn(String, Dynamic, Dict(String, String)) ->
      Result(String, String),
  )
}

// ============================================================================
// Context Accessors
// ============================================================================

/// Get the input data for this task.
///
/// The input is the data passed when the workflow was triggered,
/// or the output from parent tasks if this is a downstream task.
pub fn input(ctx: Context) -> Dynamic {
  ctx.input
}

/// Get the output from a specific parent task.
///
/// Returns `Some(output)` if the parent task completed successfully,
/// or `None` if the parent doesn't exist or hasn't completed.
pub fn step_output(ctx: Context, step_name: String) -> Option(Dynamic) {
  case dict.get(ctx.parent_outputs, step_name) {
    Ok(value) -> Some(value)
    Error(_) -> None
  }
}

/// Get all parent task outputs.
pub fn all_parent_outputs(ctx: Context) -> Dict(String, Dynamic) {
  ctx.parent_outputs
}

/// Get the current retry count (0 for first attempt).
pub fn retry_count(ctx: Context) -> Int {
  ctx.retry_count
}

/// Get the workflow run ID.
pub fn workflow_run_id(ctx: Context) -> String {
  ctx.workflow_run_id
}

/// Get the step run ID.
pub fn step_run_id(ctx: Context) -> String {
  ctx.step_run_id
}

/// Get the step (task) name.
pub fn step_name(ctx: Context) -> String {
  ctx.step_name
}

/// Get additional metadata passed with the workflow run.
pub fn metadata(ctx: Context) -> Dict(String, String) {
  ctx.additional_metadata
}

/// Get a specific metadata value.
pub fn get_metadata(ctx: Context, key: String) -> Option(String) {
  case dict.get(ctx.additional_metadata, key) {
    Ok(value) -> Some(value)
    Error(_) -> None
  }
}

/// Log a message to the Hatchet workflow run logs.
///
/// These logs will appear in the Hatchet dashboard for this workflow run.
pub fn log(ctx: Context, message: String) -> Nil {
  ctx.log_fn(message)
}

/// Push streaming data to the workflow run.
///
/// This allows tasks to emit intermediate results that can be consumed
/// by clients via `run_ref.stream()`. Useful for progress updates,
/// partial results, or real-time data.
pub fn put_stream(ctx: Context, data: Dynamic) -> Result(Nil, String) {
  ctx.stream_fn(data)
}

/// Release this task's worker slot while continuing execution.
///
/// Useful for long-running tasks that are waiting on external resources.
/// After releasing the slot, another task can use it. The current task
/// continues running but won't count against the worker's concurrency limit.
pub fn release_slot(ctx: Context) -> Result(Nil, String) {
  ctx.release_slot_fn()
}

/// Extend the execution timeout for this task.
///
/// Adds the specified number of milliseconds to the current timeout.
/// Useful for tasks that discover they need more time (e.g., processing
/// a larger-than-expected dataset).
pub fn refresh_timeout(ctx: Context, increment_ms: Int) -> Result(Nil, String) {
  ctx.refresh_timeout_fn(increment_ms)
}

/// Cancel the current workflow run.
///
/// Signals to the Hatchet orchestrator that this run should be cancelled.
/// Other running tasks in the same workflow run will also be cancelled.
pub fn cancel(ctx: Context) -> Result(Nil, String) {
  ctx.cancel_fn()
}

/// Spawn a child workflow run from within a task handler.
///
/// Returns the child workflow run ID on success. The child run inherits
/// metadata from the parent context. Hatchet tracks the parent-child
/// relationship for observability.
pub fn spawn_workflow(
  ctx: Context,
  workflow_name: String,
  input: Dynamic,
) -> Result(String, String) {
  ctx.spawn_workflow_fn(workflow_name, input, ctx.additional_metadata)
}

/// Spawn a child workflow with custom metadata.
pub fn spawn_workflow_with_metadata(
  ctx: Context,
  workflow_name: String,
  input: Dynamic,
  metadata: Dict(String, String),
) -> Result(String, String) {
  // Merge parent metadata with custom metadata (custom takes precedence)
  let merged = dict.merge(ctx.additional_metadata, metadata)
  ctx.spawn_workflow_fn(workflow_name, input, merged)
}

// ============================================================================
// Context Construction (Internal)
// ============================================================================

/// Callbacks for Context to communicate with the worker/server.
pub type ContextCallbacks {
  ContextCallbacks(
    log_fn: fn(String) -> Nil,
    stream_fn: fn(Dynamic) -> Result(Nil, String),
    release_slot_fn: fn() -> Result(Nil, String),
    refresh_timeout_fn: fn(Int) -> Result(Nil, String),
    cancel_fn: fn() -> Result(Nil, String),
    spawn_workflow_fn: fn(String, Dynamic, Dict(String, String)) ->
      Result(String, String),
  )
}

/// Create default no-op callbacks (for testing or when features aren't available).
pub fn default_callbacks(log_fn: fn(String) -> Nil) -> ContextCallbacks {
  ContextCallbacks(
    log_fn: log_fn,
    stream_fn: fn(_) { Error("Streaming not available") },
    release_slot_fn: fn() { Error("Release slot not available") },
    refresh_timeout_fn: fn(_) { Error("Refresh timeout not available") },
    cancel_fn: fn() { Error("Cancel not available") },
    spawn_workflow_fn: fn(_, _, _) {
      Error("Child workflow spawning not available")
    },
  )
}

/// Create a Context from an AssignedAction.
///
/// This is called internally by the worker when a task is assigned.
/// Parent outputs are extracted from the action_payload if present.
pub fn from_assigned_action(
  action: protobuf.AssignedAction,
  worker_id: String,
  additional_parent_outputs: Dict(String, Dynamic),
  callbacks: ContextCallbacks,
) -> Context {
  // Parse the action payload as JSON to get the input and parent outputs
  let #(input, payload_parent_outputs) =
    parse_action_payload_with_parents(action.action_payload)

  // Merge additional parent outputs with those from payload
  // Additional outputs take precedence (allows local overrides)
  let parent_outputs =
    dict.merge(payload_parent_outputs, additional_parent_outputs)

  // Parse additional metadata if present
  let metadata = case action.additional_metadata {
    Some(meta_json) -> parse_metadata(meta_json)
    None -> dict.new()
  }

  Context(
    workflow_run_id: action.workflow_run_id,
    step_run_id: action.step_run_id,
    worker_id: worker_id,
    step_name: action.step_name,
    action_id: action.action_id,
    job_id: action.job_id,
    job_run_id: action.job_run_id,
    input: input,
    parent_outputs: parent_outputs,
    additional_metadata: metadata,
    retry_count: action.retry_count,
    log_fn: callbacks.log_fn,
    stream_fn: callbacks.stream_fn,
    release_slot_fn: callbacks.release_slot_fn,
    refresh_timeout_fn: callbacks.refresh_timeout_fn,
    cancel_fn: callbacks.cancel_fn,
    spawn_workflow_fn: callbacks.spawn_workflow_fn,
  )
}

/// Parse the JSON action payload, extracting input and parent outputs.
///
/// The payload format from Hatchet is typically:
/// ```json
/// {
///   "input": {...},
///   "parents": {
///     "parent_task_name": {...}
///   }
/// }
/// ```
///
/// Or it may be just the input data directly.
fn parse_action_payload_with_parents(
  payload: String,
) -> #(Dynamic, Dict(String, Dynamic)) {
  case json.parse(payload, decode.dynamic) {
    Ok(value) -> {
      // Try to extract structured payload with input and parents using builder pattern
      let decoder = {
        use input <- decode.field("input", decode.dynamic)
        use parents <- decode.field(
          "parents",
          decode.dict(decode.string, decode.dynamic),
        )
        decode.success(#(input, parents))
      }

      case decode.run(value, decoder) {
        Ok(#(input, parents)) -> #(input, parents)
        Error(_) -> {
          // If structured decode fails, try just extracting input
          let input_decoder = {
            use input <- decode.field("input", decode.dynamic)
            decode.success(input)
          }
          case decode.run(value, input_decoder) {
            Ok(input) -> #(input, dict.new())
            Error(_) -> {
              // Payload is just the input data itself
              #(value, dict.new())
            }
          }
        }
      }
    }
    Error(_) -> {
      // If JSON parsing fails, treat the payload as a raw string value
      // Convert to Dynamic using the dynamic.string constructor
      #(dynamic.string(payload), dict.new())
    }
  }
}

/// Parse the JSON metadata into a Dict.
fn parse_metadata(meta_json: String) -> Dict(String, String) {
  case json.parse(meta_json, decode.dict(decode.string, decode.string)) {
    Ok(meta) -> meta
    Error(_) -> dict.new()
  }
}

// ============================================================================
// Test Helpers
// ============================================================================

/// Create a mock context for testing.
pub fn mock(input: Dynamic, parent_outputs: Dict(String, Dynamic)) -> Context {
  let noop_callbacks = default_callbacks(fn(_msg) { Nil })
  Context(
    workflow_run_id: "test-workflow-run-id",
    step_run_id: "test-step-run-id",
    worker_id: "test-worker-id",
    step_name: "test-step",
    action_id: "test-action-id",
    job_id: "test-job-id",
    job_run_id: "test-job-run-id",
    input: input,
    parent_outputs: parent_outputs,
    additional_metadata: dict.new(),
    retry_count: 0,
    log_fn: noop_callbacks.log_fn,
    stream_fn: noop_callbacks.stream_fn,
    release_slot_fn: noop_callbacks.release_slot_fn,
    refresh_timeout_fn: noop_callbacks.refresh_timeout_fn,
    cancel_fn: noop_callbacks.cancel_fn,
    spawn_workflow_fn: noop_callbacks.spawn_workflow_fn,
  )
}

/// Create a mock context with retry count for testing.
pub fn mock_with_retry(
  input: Dynamic,
  parent_outputs: Dict(String, Dynamic),
  retry: Int,
) -> Context {
  let noop_callbacks = default_callbacks(fn(_msg) { Nil })
  Context(
    workflow_run_id: "test-workflow-run-id",
    step_run_id: "test-step-run-id",
    worker_id: "test-worker-id",
    step_name: "test-step",
    action_id: "test-action-id",
    job_id: "test-job-id",
    job_run_id: "test-job-run-id",
    input: input,
    parent_outputs: parent_outputs,
    additional_metadata: dict.new(),
    retry_count: retry,
    log_fn: noop_callbacks.log_fn,
    stream_fn: noop_callbacks.stream_fn,
    release_slot_fn: noop_callbacks.release_slot_fn,
    refresh_timeout_fn: noop_callbacks.refresh_timeout_fn,
    cancel_fn: noop_callbacks.cancel_fn,
    spawn_workflow_fn: noop_callbacks.spawn_workflow_fn,
  )
}

// ============================================================================
// TaskContext Conversion
// ============================================================================

import hatchet/types.{type TaskContext, TaskContext as TypesTaskContext}

/// Convert a Context to a TaskContext for use with skip_if conditions
/// and handler functions that expect TaskContext.
///
/// TaskContext is a simpler type used in workflow definitions,
/// while Context is the richer type used during execution.
pub fn to_task_context(ctx: Context) -> TaskContext {
  TypesTaskContext(
    workflow_run_id: ctx.workflow_run_id,
    task_run_id: ctx.step_run_id,
    input: ctx.input,
    parent_outputs: ctx.parent_outputs,
    metadata: ctx.additional_metadata,
    logger: ctx.log_fn,
    stream_fn: ctx.stream_fn,
    release_slot_fn: ctx.release_slot_fn,
    refresh_timeout_fn: ctx.refresh_timeout_fn,
    cancel_fn: ctx.cancel_fn,
    spawn_workflow_fn: ctx.spawn_workflow_fn,
  )
}
