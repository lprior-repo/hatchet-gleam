//// Pure, testable task execution logic extracted from worker_actor.
////
//// This module handles the core business logic of executing a single task,
//// separated from I/O side effects. It follows the protocol state transitions:
//// ACKNOWLEDGED → STARTED → COMPLETED/FAILED/CANCELLED
////
//// All side effects (logging, event emission, gRPC calls) are passed as
//// callbacks in TaskEffects, making this module easily testable.

import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import hatchet/context
import hatchet/internal/ffi/protobuf
import hatchet/types.{type TaskContext}

// ============================================================================
// Type Definitions
// ============================================================================

/// Specification for a task to be executed.
///
/// Contains all input data needed to run a task handler,
/// including the action metadata, handler function, and parent outputs.
pub type TaskSpec {
  TaskSpec(
    action: protobuf.AssignedAction,
    handler: TaskHandler,
    worker_id: String,
    parent_outputs: Dict(String, String),
  )
}

/// Task handler with retry and condition configuration.
pub type TaskHandler {
  TaskHandler(
    workflow_name: String,
    task_name: String,
    handler: fn(TaskContext) -> Result(Dynamic, String),
    retries: Int,
    timeout_ms: Int,
    skip_if: Option(fn(TaskContext) -> Bool),
    cancel_if: Option(fn(TaskContext) -> Bool),
  )
}

/// Side effect callbacks for task execution.
///
/// All I/O operations are passed as callbacks to keep execution logic pure.
/// This enables easy testing and separation of concerns.
pub type TaskEffects {
  TaskEffects(
    log: fn(String) -> Nil,
    emit_event: fn(protobuf.StepActionEventType, String) -> Nil,
    release_slot: fn() -> Result(Nil, String),
    refresh_timeout: fn(Int) -> Result(Nil, String),
    cancel: fn() -> Result(Nil, String),
    spawn_workflow: fn(String, Dynamic, Dict(String, String)) ->
      Result(String, String),
  )
}

/// Successful task execution result.
pub type TaskOutput {
  TaskOutput(output_json: String, events: List(TaskEvent))
}

/// Task execution error with retry information.
pub type TaskError {
  TaskError(
    error: String,
    should_retry: Bool,
    retry_count: Int,
    events: List(TaskEvent),
  )
}

/// Task cancellation result.
pub type TaskCancelled {
  TaskCancelled(reason: String, events: List(TaskEvent))
}

/// Execution result wrapping all possible outcomes.
pub type ExecutionResult {
  Completed(TaskOutput)
  Failed(TaskError)
  Cancelled(TaskCancelled)
  Skipped(TaskOutput)
}

/// Event emitted during task execution for protocol state transitions.
pub type TaskEvent {
  TaskEvent(event_type: protobuf.StepActionEventType, payload: String)
}

// ============================================================================
// Main Execution Orchestrator
// ============================================================================

/// Execute a task from specification to completion.
///
/// This is the main entry point that orchestrates the entire task lifecycle:
/// 1. ACKNOWLEDGED - Signal task received
/// 2. STARTED - Begin execution
/// 3. Evaluate cancel_if condition
/// 4. Evaluate skip_if condition
/// 5. Execute handler
/// 6. COMPLETED/FAILED/CANCELLED - Finalize result
///
/// All side effects are performed through the effects callbacks,
/// keeping this function pure and testable.
pub fn execute_task(spec: TaskSpec, effects: TaskEffects) -> ExecutionResult {
  // Protocol State: ACKNOWLEDGED
  let acknowledged_event = TaskEvent(protobuf.StepEventTypeAcknowledged, "{}")
  effects.emit_event(protobuf.StepEventTypeAcknowledged, "{}")

  // Log task start
  effects.log("[" <> spec.handler.task_name <> "] Starting execution")

  // Protocol State: STARTED
  let started_event = TaskEvent(protobuf.StepEventTypeStarted, "{}")
  effects.emit_event(protobuf.StepEventTypeStarted, "{}")

  // Build execution context
  let ctx = build_context(spec, effects)
  let task_ctx = context.to_task_context(ctx)

  // Evaluate cancel_if condition before executing
  case evaluate_cancel_if(spec.handler, task_ctx) {
    True ->
      handle_cancellation(spec, effects, [acknowledged_event, started_event])
    False ->
      // Evaluate skip_if condition
      case evaluate_skip_if(spec.handler, task_ctx) {
        True -> handle_skip(spec, effects, [acknowledged_event, started_event])
        False ->
          // Execute the handler
          execute_handler(spec, task_ctx, effects, [
            acknowledged_event,
            started_event,
          ])
      }
  }
}

// ============================================================================
// Context Building
// ============================================================================

/// Build an execution context from task specification and effects.
///
/// Converts parent outputs from JSON strings to Dynamic values and
/// creates a Context with all necessary callbacks.
pub fn build_context(spec: TaskSpec, effects: TaskEffects) -> context.Context {
  // Convert parent outputs from JSON strings to Dynamic
  let parent_outputs_dynamic =
    dict.fold(spec.parent_outputs, dict.new(), fn(acc, step_name, output_json) {
      case json.parse(output_json, decode.dynamic) {
        Ok(value) -> dict.insert(acc, step_name, value)
        Error(_) -> acc
      }
    })

  // Build context callbacks from effects
  let callbacks =
    context.ContextCallbacks(
      log_fn: effects.log,
      stream_fn: fn(data) {
        let payload = encode_dynamic_to_json(data)
        effects.emit_event(protobuf.StepEventTypeStream, payload)
        Ok(Nil)
      },
      release_slot_fn: effects.release_slot,
      refresh_timeout_fn: effects.refresh_timeout,
      cancel_fn: effects.cancel,
      spawn_workflow_fn: effects.spawn_workflow,
    )

  // Create context using the standard context module
  context.from_assigned_action(
    spec.action,
    spec.worker_id,
    parent_outputs_dynamic,
    callbacks,
  )
}

// ============================================================================
// Condition Evaluation
// ============================================================================

/// Evaluate the cancel_if condition for a task.
///
/// Returns True if the workflow should be cancelled.
pub fn evaluate_cancel_if(handler: TaskHandler, ctx: TaskContext) -> Bool {
  case handler.cancel_if {
    Some(cancel_fn) -> cancel_fn(ctx)
    None -> False
  }
}

/// Evaluate the skip_if condition for a task.
///
/// Returns True if the task should be skipped.
pub fn evaluate_skip_if(handler: TaskHandler, ctx: TaskContext) -> Bool {
  case handler.skip_if {
    Some(skip_fn) -> skip_fn(ctx)
    None -> False
  }
}

// ============================================================================
// Handler Execution
// ============================================================================

/// Execute the task handler and process the result.
fn execute_handler(
  spec: TaskSpec,
  ctx: TaskContext,
  effects: TaskEffects,
  events: List(TaskEvent),
) -> ExecutionResult {
  case spec.handler.handler(ctx) {
    Ok(output) -> {
      let output_json = encode_dynamic_to_json(output)
      handle_success(output_json, effects, events)
    }
    Error(error) -> handle_failure(error, spec, effects, events)
  }
}

// ============================================================================
// Result Handlers
// ============================================================================

/// Process a successful task execution.
///
/// Protocol State: COMPLETED
pub fn handle_success(
  output_json: String,
  effects: TaskEffects,
  events: List(TaskEvent),
) -> ExecutionResult {
  // Protocol State: COMPLETED
  effects.emit_event(protobuf.StepEventTypeCompleted, output_json)
  let completed_event = TaskEvent(protobuf.StepEventTypeCompleted, output_json)

  Completed(
    TaskOutput(output_json: output_json, events: [completed_event, ..events]),
  )
}

/// Process a task execution failure with retry logic.
///
/// Determines if the task should be retried based on retry_count < max_retries.
/// Protocol State: FAILED
pub fn handle_failure(
  error: String,
  spec: TaskSpec,
  effects: TaskEffects,
  events: List(TaskEvent),
) -> ExecutionResult {
  // Calculate retry logic: should_retry if we haven't exceeded max retries
  let should_retry = spec.action.retry_count < spec.handler.retries

  // Build error payload with retry information
  let error_json =
    json.to_string(
      json.object([
        #("error", json.string(error)),
        #("retry_count", json.int(spec.action.retry_count)),
        #("max_retries", json.int(spec.handler.retries)),
        #("should_retry", json.bool(should_retry)),
      ]),
    )

  // Protocol State: FAILED
  effects.emit_event(protobuf.StepEventTypeFailed, error_json)
  let failed_event = TaskEvent(protobuf.StepEventTypeFailed, error_json)

  Failed(
    TaskError(
      error: error,
      should_retry: should_retry,
      retry_count: spec.action.retry_count,
      events: [failed_event, ..events],
    ),
  )
}

/// Handle task cancellation when cancel_if condition is met.
///
/// Protocol State: CANCELLED
fn handle_cancellation(
  spec: TaskSpec,
  effects: TaskEffects,
  events: List(TaskEvent),
) -> ExecutionResult {
  let workflow_name = case spec.action.workflow_id {
    Some(id) -> id
    None -> "unknown"
  }

  effects.log(
    "Cancelling workflow: " <> workflow_name <> " (cancel_if condition met)",
  )

  let cancel_output_json =
    json.to_string(
      json.object([
        #("cancelled", json.bool(True)),
        #("reason", json.string("cancel_if condition evaluated to true")),
      ]),
    )

  // Protocol State: CANCELLED
  effects.emit_event(protobuf.StepEventTypeCancelled, cancel_output_json)
  let cancelled_event =
    TaskEvent(protobuf.StepEventTypeCancelled, cancel_output_json)

  Cancelled(
    TaskCancelled(reason: "cancel_if condition evaluated to true", events: [
      cancelled_event,
      ..events
    ]),
  )
}

/// Handle task skip when skip_if condition is met.
///
/// Skipped tasks complete successfully with a skip marker in the output.
/// Protocol State: COMPLETED (with skip indicator)
fn handle_skip(
  spec: TaskSpec,
  effects: TaskEffects,
  events: List(TaskEvent),
) -> ExecutionResult {
  effects.log(
    "Skipping task: " <> spec.handler.task_name <> " (skip_if condition met)",
  )

  let skip_output_json =
    json.to_string(
      json.object([
        #("skipped", json.bool(True)),
        #("reason", json.string("skip_if condition evaluated to true")),
      ]),
    )

  // Protocol State: COMPLETED (with skip indicator)
  effects.emit_event(protobuf.StepEventTypeCompleted, skip_output_json)
  let completed_event =
    TaskEvent(protobuf.StepEventTypeCompleted, skip_output_json)

  Skipped(
    TaskOutput(output_json: skip_output_json, events: [
      completed_event,
      ..events
    ]),
  )
}

// ============================================================================
// JSON Encoding Helpers
// ============================================================================

/// Encode a Dynamic value to JSON string.
///
/// Handles common types (string, int, float, bool, list, dict).
/// For unknown types, returns the string representation.
fn encode_dynamic_to_json(value: Dynamic) -> String {
  case decode.run(value, decode.string) {
    Ok(s) -> json.to_string(json.string(s))
    Error(_) ->
      case decode.run(value, decode.int) {
        Ok(i) -> json.to_string(json.int(i))
        Error(_) ->
          case decode.run(value, decode.float) {
            Ok(f) -> json.to_string(json.float(f))
            Error(_) ->
              case decode.run(value, decode.bool) {
                Ok(b) -> json.to_string(json.bool(b))
                Error(_) ->
                  case decode.run(value, decode.list(decode.dynamic)) {
                    Ok(lst) -> {
                      let json_list =
                        lst
                        |> list.map(encode_dynamic_to_json_value)
                      json.to_string(json.array(json_list, fn(x) { x }))
                    }
                    Error(_) ->
                      case
                        decode.run(
                          value,
                          decode.dict(decode.string, decode.dynamic),
                        )
                      {
                        Ok(d) -> {
                          let json_dict =
                            d
                            |> dict.to_list
                            |> list.map(fn(pair) {
                              #(pair.0, encode_dynamic_to_json_value(pair.1))
                            })
                          json.to_string(json.object(json_dict))
                        }
                        Error(_) -> {
                          // Fallback: convert to string representation
                          json.to_string(json.string(string.inspect(value)))
                        }
                      }
                  }
              }
          }
      }
  }
}

/// Encode Dynamic to json.Json value (not string).
fn encode_dynamic_to_json_value(value: Dynamic) -> json.Json {
  case decode.run(value, decode.string) {
    Ok(s) -> json.string(s)
    Error(_) ->
      case decode.run(value, decode.int) {
        Ok(i) -> json.int(i)
        Error(_) ->
          case decode.run(value, decode.float) {
            Ok(f) -> json.float(f)
            Error(_) ->
              case decode.run(value, decode.bool) {
                Ok(b) -> json.bool(b)
                Error(_) ->
                  case decode.run(value, decode.list(decode.dynamic)) {
                    Ok(lst) -> {
                      let json_list =
                        list.map(lst, encode_dynamic_to_json_value)
                      json.array(json_list, fn(x) { x })
                    }
                    Error(_) ->
                      case
                        decode.run(
                          value,
                          decode.dict(decode.string, decode.dynamic),
                        )
                      {
                        Ok(d) -> {
                          let json_dict =
                            d
                            |> dict.to_list
                            |> list.map(fn(pair) {
                              #(pair.0, encode_dynamic_to_json_value(pair.1))
                            })
                          json.object(json_dict)
                        }
                        Error(_) -> {
                          // Fallback: convert to string
                          json.string(string.inspect(value))
                        }
                      }
                  }
              }
          }
      }
  }
}
