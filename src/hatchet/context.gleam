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
import gleam/json
import gleam/option.{type Option, None, Some}
import hatchet/internal/ffi/protobuf

// ============================================================================
// Context Type
// ============================================================================

/// The execution context passed to task handlers.
///
/// Contains all information needed to execute a task, including input data,
/// parent outputs, and metadata.
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
    // Logging (internal channel reference for sending logs)
    log_fn: fn(String) -> Nil,
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
  dict.get(ctx.parent_outputs, step_name)
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
  dict.get(ctx.additional_metadata, key)
}

/// Log a message to the Hatchet workflow run logs.
///
/// These logs will appear in the Hatchet dashboard for this workflow run.
pub fn log(ctx: Context, message: String) -> Nil {
  ctx.log_fn(message)
}

// ============================================================================
// Context Construction (Internal)
// ============================================================================

/// Create a Context from an AssignedAction.
///
/// This is called internally by the worker when a task is assigned.
/// Parent outputs are extracted from the action_payload if present.
pub fn from_assigned_action(
  action: protobuf.AssignedAction,
  worker_id: String,
  additional_parent_outputs: Dict(String, Dynamic),
  log_fn: fn(String) -> Nil,
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
    log_fn: log_fn,
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
  case json.decode(payload, dynamic.dynamic) {
    Ok(value) -> {
      // Try to extract structured payload with input and parents
      let input_result =
        dynamic.field("input", dynamic.dynamic)(value)
      let parents_result =
        dynamic.field("parents", dynamic.dict(dynamic.string, dynamic.dynamic))(
          value,
        )

      case input_result, parents_result {
        Ok(input), Ok(parents) -> #(input, parents)
        Ok(input), Error(_) -> #(input, dict.new())
        Error(_), _ -> {
          // Payload is just the input data itself
          #(value, dict.new())
        }
      }
    }
    Error(_) -> #(dynamic.from(payload), dict.new())
  }
}

/// Parse the JSON metadata into a Dict.
fn parse_metadata(meta_json: String) -> Dict(String, String) {
  case json.decode(meta_json, dynamic.dict(dynamic.string, dynamic.string)) {
    Ok(meta) -> meta
    Error(_) -> dict.new()
  }
}

// ============================================================================
// Test Helpers
// ============================================================================

/// Create a mock context for testing.
pub fn mock(
  input: Dynamic,
  parent_outputs: Dict(String, Dynamic),
) -> Context {
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
    log_fn: fn(_msg) { Nil },
  )
}

/// Create a mock context with retry count for testing.
pub fn mock_with_retry(
  input: Dynamic,
  parent_outputs: Dict(String, Dynamic),
  retry: Int,
) -> Context {
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
    log_fn: fn(_msg) { Nil },
  )
}
