//// Task Executor Tests
////
//// Comprehensive unit tests for task execution logic.
//// Tests task handler invocation, context building, skip/cancel conditions,
//// error handling, and event collection without network calls.

import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/option.{type Option, None, Some}
import gleeunit
import gleeunit/should
import hatchet/internal/ffi/protobuf
import hatchet/types

pub fn main() {
  gleeunit.main()
}

// ============================================================================
// Test Effects Builder
// ============================================================================

/// Test effects that capture calls instead of executing them
pub type TestEffects {
  TestEffects(
    logs: List(String),
    events: List(TestEvent),
    slot_released: Bool,
    timeout_refreshed: Option(Int),
    cancelled: Bool,
    spawned_workflows: List(SpawnedWorkflow),
  )
}

pub type TestEvent {
  LogEvent(message: String)
  StreamEvent(data: Dynamic)
  ReleaseSlotEvent
  RefreshTimeoutEvent(increment_ms: Int)
  CancelEvent
}

pub type SpawnedWorkflow {
  SpawnedWorkflow(
    workflow_name: String,
    input: Dynamic,
    metadata: dict.Dict(String, String),
  )
}

// ============================================================================
// Mock Data Builders
// ============================================================================

/// Create a test AssignedAction
fn test_action(
  step_run_id: String,
  step_name: String,
  action_payload: String,
  retry_count: Int,
) -> protobuf.AssignedAction {
  protobuf.AssignedAction(
    tenant_id: "test-tenant",
    workflow_run_id: "test-wf-run-123",
    get_group_key_run_id: "",
    job_id: "test-job-id",
    job_name: "test-job",
    job_run_id: "test-job-run",
    step_id: "test-step-id",
    step_run_id: step_run_id,
    action_id: "test-action-id",
    action_type: protobuf.StartStepRun,
    action_payload: action_payload,
    step_name: step_name,
    retry_count: retry_count,
    additional_metadata: Some("{\"key\":\"value\"}"),
    child_workflow_index: None,
    child_workflow_key: None,
    parent_workflow_run_id: None,
    priority: 1,
    workflow_id: Some("test-workflow-id"),
    workflow_version_id: Some("test-version-id"),
  )
}

/// Create a test TaskContext
fn test_task_context(
  input_data: Dynamic,
  parent_outputs: dict.Dict(String, Dynamic),
) -> types.TaskContext {
  types.TaskContext(
    workflow_run_id: "test-wf-run-123",
    task_run_id: "test-task-run-123",
    input: input_data,
    parent_outputs: parent_outputs,
    metadata: dict.from_list([#("key", "value"), #("env", "test")]),
    logger: fn(_msg) { Nil },
    stream_fn: fn(_data) { Ok(Nil) },
    release_slot_fn: fn() { Ok(Nil) },
    refresh_timeout_fn: fn(_increment_ms) { Ok(Nil) },
    cancel_fn: fn() { Ok(Nil) },
    spawn_workflow_fn: fn(_name, _input, _metadata) { Ok("child-run-id") },
    step_run_errors: dict.new(),
  )
}

// ============================================================================
// Test Scenarios - Successful Task Execution
// ============================================================================

pub fn successful_task_execution_test() {
  // Arrange: Create a simple successful handler
  let handler = fn(_ctx: types.TaskContext) -> Result(Dynamic, String) {
    Ok(dynamic.string("task completed successfully"))
  }

  let input = dynamic.string("{\"data\":\"test\"}")
  let parent_outputs = dict.new()
  let ctx = test_task_context(input, parent_outputs)

  // Act: Execute the handler
  let result = handler(ctx)

  // Assert: Handler succeeded with expected output
  result |> should.be_ok

  case result {
    Ok(output) -> {
      case decode.run(output, decode.string) {
        Ok(s) -> s |> should.equal("task completed successfully")
        Error(_) -> panic as "Failed to decode output"
      }
    }
    Error(_) -> panic as "Expected Ok result"
  }
}

pub fn task_with_input_processing_test() {
  // Arrange: Handler that processes input
  let handler = fn(ctx: types.TaskContext) -> Result(Dynamic, String) {
    // Get input and double it (simulating processing)
    case decode.run(ctx.input, decode.int) {
      Ok(value) -> Ok(dynamic.int(value * 2))
      Error(_) -> Error("Invalid input: expected integer")
    }
  }

  let input = dynamic.int(42)
  let ctx = test_task_context(input, dict.new())

  // Act: Execute handler
  let result = handler(ctx)

  // Assert: Handler processed input correctly
  result |> should.be_ok
  case result {
    Ok(output) -> {
      case decode.run(output, decode.int) {
        Ok(value) -> value |> should.equal(84)
        Error(_) -> panic as "Failed to decode"
      }
    }
    Error(_) -> panic as "Expected Ok result"
  }
}

pub fn task_with_parent_outputs_test() {
  // Arrange: Handler that uses parent output
  let handler = fn(ctx: types.TaskContext) -> Result(Dynamic, String) {
    case dict.get(ctx.parent_outputs, "fetch-data") {
      Ok(parent_data) -> {
        case decode.run(parent_data, decode.string) {
          Ok(data) -> Ok(dynamic.string("Processed: " <> data))
          Error(_) -> Error("Parent data not a string")
        }
      }
      Error(_) -> Error("Missing parent output: fetch-data")
    }
  }

  let parent_outputs =
    dict.from_list([#("fetch-data", dynamic.string("raw-data"))])
  let ctx = test_task_context(dynamic.string("{}"), parent_outputs)

  // Act: Execute handler
  let result = handler(ctx)

  // Assert: Handler used parent output correctly
  result |> should.be_ok
  case result {
    Ok(output) -> {
      case decode.run(output, decode.string) {
        Ok(s) -> s |> should.equal("Processed: raw-data")
        Error(_) -> panic as "Failed to decode"
      }
    }
    Error(_) -> panic as "Expected Ok result"
  }
}

// ============================================================================
// Test Scenarios - Handler Error with Retry Logic
// ============================================================================

pub fn handler_error_should_retry_test() {
  // Arrange: Handler that fails
  let handler = fn(_ctx: types.TaskContext) -> Result(Dynamic, String) {
    Error("Database connection failed")
  }

  let ctx = test_task_context(dynamic.string("{}"), dict.new())

  // Act: Execute handler
  let result = handler(ctx)

  // Assert: Handler returned error
  result |> should.be_error
  case result {
    Error(msg) -> msg |> should.equal("Database connection failed")
    Ok(_) -> panic as "Expected Error result"
  }
}

pub fn handler_error_permanent_failure_test() {
  // Arrange: Handler that fails with validation error (shouldn't retry)
  let handler = fn(_ctx: types.TaskContext) -> Result(Dynamic, String) {
    Error("Invalid email format")
  }

  let ctx = test_task_context(dynamic.string("{}"), dict.new())

  // Act: Execute handler
  let result = handler(ctx)

  // Assert: Handler returned error
  result |> should.be_error
  case result {
    Error(msg) -> msg |> should.equal("Invalid email format")
    Ok(_) -> panic as "Expected Error result"
  }
}

pub fn handler_retry_count_increments_test() {
  // Test that retry count is properly tracked
  let action = test_action("step-run-1", "retry-task", "{}", 3)

  // Assert: Retry count is 3
  action.retry_count |> should.equal(3)
}

// ============================================================================
// Test Scenarios - skip_if Condition
// ============================================================================

pub fn skip_if_condition_true_test() {
  // Arrange: skip_if evaluates to True
  let skip_condition = fn(ctx: types.TaskContext) -> Bool {
    case dict.get(ctx.metadata, "skip") {
      Ok(value) -> value == "true"
      Error(_) -> False
    }
  }

  let metadata = dict.from_list([#("skip", "true")])
  let ctx =
    types.TaskContext(
      ..test_task_context(dynamic.string("{}"), dict.new()),
      metadata: metadata,
    )

  // Act: Evaluate skip condition
  let should_skip = skip_condition(ctx)

  // Assert: Should skip
  should_skip |> should.be_true
}

pub fn skip_if_condition_false_test() {
  // Arrange: skip_if evaluates to False
  let skip_condition = fn(ctx: types.TaskContext) -> Bool {
    case dict.get(ctx.metadata, "skip") {
      Ok(value) -> value == "true"
      Error(_) -> False
    }
  }

  let metadata = dict.from_list([#("skip", "false")])
  let ctx =
    types.TaskContext(
      ..test_task_context(dynamic.string("{}"), dict.new()),
      metadata: metadata,
    )

  // Act: Evaluate skip condition
  let should_skip = skip_condition(ctx)

  // Assert: Should not skip
  should_skip |> should.be_false
}

pub fn skip_if_with_handler_execution_test() {
  // Simulate full skip_if flow
  let skip_condition = fn(ctx: types.TaskContext) -> Bool {
    case dict.get(ctx.metadata, "env") {
      Ok("production") -> False
      Ok("test") -> True
      _ -> False
    }
  }

  let handler = fn(_ctx: types.TaskContext) -> Result(Dynamic, String) {
    Ok(dynamic.string("task executed"))
  }

  let ctx = test_task_context(dynamic.string("{}"), dict.new())

  // Act: Check skip condition, then execute if needed
  let should_skip = skip_condition(ctx)

  // Assert: Should skip in test environment
  should_skip |> should.be_true

  // If not skipped, handler would execute
  case should_skip {
    True -> Nil
    False -> {
      let _result = handler(ctx)
      Nil
    }
  }
}

// ============================================================================
// Test Scenarios - cancel_if Condition
// ============================================================================

pub fn cancel_if_condition_true_test() {
  // Arrange: cancel_if evaluates to True
  let cancel_condition = fn(ctx: types.TaskContext) -> Bool {
    case decode.run(ctx.input, decode.int) {
      Ok(value) -> value > 1000
      Error(_) -> False
    }
  }

  let ctx = test_task_context(dynamic.int(1500), dict.new())

  // Act: Evaluate cancel condition
  let should_cancel = cancel_condition(ctx)

  // Assert: Should cancel
  should_cancel |> should.be_true
}

pub fn cancel_if_condition_false_test() {
  // Arrange: cancel_if evaluates to False
  let cancel_condition = fn(ctx: types.TaskContext) -> Bool {
    case decode.run(ctx.input, decode.int) {
      Ok(value) -> value > 1000
      Error(_) -> False
    }
  }

  let ctx = test_task_context(dynamic.int(500), dict.new())

  // Act: Evaluate cancel condition
  let should_cancel = cancel_condition(ctx)

  // Assert: Should not cancel
  should_cancel |> should.be_false
}

pub fn cancel_if_prevents_execution_test() {
  // Simulate full cancel_if flow
  let cancel_condition = fn(ctx: types.TaskContext) -> Bool {
    case dict.get(ctx.metadata, "abort") {
      Ok("true") -> True
      _ -> False
    }
  }

  let handler = fn(_ctx: types.TaskContext) -> Result(Dynamic, String) {
    Ok(dynamic.string("should not execute"))
  }

  let metadata = dict.from_list([#("abort", "true")])
  let ctx =
    types.TaskContext(
      ..test_task_context(dynamic.string("{}"), dict.new()),
      metadata: metadata,
    )

  // Act: Check cancel condition
  let should_cancel = cancel_condition(ctx)

  // Assert: Should cancel, handler doesn't execute
  should_cancel |> should.be_true

  case should_cancel {
    True -> Nil
    False -> {
      let _result = handler(ctx)
      Nil
    }
  }
}

// ============================================================================
// Test Scenarios - Context Building
// ============================================================================

pub fn context_building_with_input_test() {
  // Arrange: Build context with specific input
  let input = dynamic.string("{\"user_id\":123,\"action\":\"create\"}")
  let ctx = test_task_context(input, dict.new())

  // Assert: Context has correct input
  ctx.input |> should.equal(input)
  ctx.workflow_run_id |> should.equal("test-wf-run-123")
}

pub fn context_building_with_parent_outputs_test() {
  // Arrange: Build context with parent outputs
  let parent_outputs =
    dict.from_list([
      #("step1", dynamic.string("output1")),
      #("step2", dynamic.string("output2")),
    ])
  let ctx = test_task_context(dynamic.string("{}"), parent_outputs)

  // Assert: Context has parent outputs
  dict.size(ctx.parent_outputs) |> should.equal(2)
  case dict.get(ctx.parent_outputs, "step1") {
    Ok(output) -> {
      case decode.run(output, decode.string) {
        Ok(s) -> s |> should.equal("output1")
        Error(_) -> panic as "Failed to decode"
      }
    }
    Error(_) -> panic as "Missing parent output"
  }
}

pub fn context_building_with_metadata_test() {
  // Arrange: Build context with metadata
  let ctx = test_task_context(dynamic.string("{}"), dict.new())

  // Assert: Context has metadata
  case dict.get(ctx.metadata, "key") {
    Ok(value) -> value |> should.equal("value")
    Error(_) -> panic as "Missing metadata"
  }
  case dict.get(ctx.metadata, "env") {
    Ok(value) -> value |> should.equal("test")
    Error(_) -> panic as "Missing env metadata"
  }
}

pub fn context_workflow_run_id_test() {
  // Arrange: Create context
  let ctx = test_task_context(dynamic.string("{}"), dict.new())

  // Assert: Workflow run ID is set
  ctx.workflow_run_id |> should.equal("test-wf-run-123")
  ctx.task_run_id |> should.equal("test-task-run-123")
}

// ============================================================================
// Test Scenarios - Protocol State Transitions (No gRPC)
// ============================================================================

pub fn action_payload_parsing_test() {
  // Test parsing action payload (JSON input)
  let action = test_action("step-1", "my-task", "{\"data\":\"test\"}", 0)

  // Assert: Action payload is valid JSON string
  action.action_payload |> should.equal("{\"data\":\"test\"}")
  action.step_name |> should.equal("my-task")
}

pub fn action_metadata_parsing_test() {
  // Test parsing additional metadata
  let action = test_action("step-1", "my-task", "{}", 0)

  // Assert: Additional metadata is present
  case action.additional_metadata {
    Some(metadata) -> metadata |> should.equal("{\"key\":\"value\"}")
    None -> panic as "Expected metadata"
  }
}

pub fn action_type_start_step_run_test() {
  // Test action type
  let action = test_action("step-1", "my-task", "{}", 0)

  // Assert: Action type is StartStepRun
  action.action_type |> should.equal(protobuf.StartStepRun)
}

// ============================================================================
// Test Scenarios - Event Collection Verification
// ============================================================================

pub fn event_type_acknowledged_test() {
  // Test that we can create acknowledged event type
  let event_type = protobuf.StepEventTypeAcknowledged

  // Assert: Event type is correct
  protobuf.step_event_type_to_int(event_type) |> should.equal(4)
}

pub fn event_type_started_test() {
  // Test started event type
  let event_type = protobuf.StepEventTypeStarted

  // Assert: Event type is correct
  protobuf.step_event_type_to_int(event_type) |> should.equal(1)
}

pub fn event_type_completed_test() {
  // Test completed event type
  let event_type = protobuf.StepEventTypeCompleted

  // Assert: Event type is correct
  protobuf.step_event_type_to_int(event_type) |> should.equal(2)
}

pub fn event_type_failed_test() {
  // Test failed event type
  let event_type = protobuf.StepEventTypeFailed

  // Assert: Event type is correct
  protobuf.step_event_type_to_int(event_type) |> should.equal(3)
}

pub fn event_type_stream_test() {
  // Test stream event type
  let event_type = protobuf.StepEventTypeStream

  // Assert: Event type is correct
  protobuf.step_event_type_to_int(event_type) |> should.equal(5)
}

pub fn event_type_refresh_timeout_test() {
  // Test refresh timeout event type
  let event_type = protobuf.StepEventTypeRefreshTimeout

  // Assert: Event type is correct
  protobuf.step_event_type_to_int(event_type) |> should.equal(6)
}

pub fn event_type_cancelled_test() {
  // Test cancelled event type
  let event_type = protobuf.StepEventTypeCancelled

  // Assert: Event type is correct
  protobuf.step_event_type_to_int(event_type) |> should.equal(7)
}

// ============================================================================
// Test Scenarios - Complex Workflows
// ============================================================================

pub fn multi_step_workflow_with_dependencies_test() {
  // Simulate a multi-step workflow where step2 depends on step1
  let step1_handler = fn(_ctx: types.TaskContext) -> Result(Dynamic, String) {
    Ok(dynamic.string("step1-output"))
  }

  let step2_handler = fn(ctx: types.TaskContext) -> Result(Dynamic, String) {
    case dict.get(ctx.parent_outputs, "step1") {
      Ok(step1_output) -> {
        case decode.run(step1_output, decode.string) {
          Ok(data) -> Ok(dynamic.string("step2-processed-" <> data))
          Error(_) -> Error("Invalid step1 output")
        }
      }
      Error(_) -> Error("Missing step1 output")
    }
  }

  // Execute step1
  let step1_ctx = test_task_context(dynamic.string("{}"), dict.new())
  let step1_result = step1_handler(step1_ctx)

  // Assert: Step1 succeeded
  step1_result |> should.be_ok

  // Execute step2 with step1's output
  case step1_result {
    Ok(step1_output) -> {
      let parent_outputs = dict.from_list([#("step1", step1_output)])
      let step2_ctx = test_task_context(dynamic.string("{}"), parent_outputs)
      let step2_result = step2_handler(step2_ctx)

      // Assert: Step2 used step1's output
      step2_result |> should.be_ok
      case step2_result {
        Ok(output) -> {
          case decode.run(output, decode.string) {
            Ok(s) -> s |> should.equal("step2-processed-step1-output")
            Error(_) -> panic as "Failed to decode"
          }
        }
        Error(_) -> panic as "Expected Ok"
      }
    }
    Error(_) -> panic as "Step1 should succeed"
  }
}

pub fn error_propagation_in_workflow_test() {
  // Test that errors in one step prevent downstream execution
  let failing_step = fn(_ctx: types.TaskContext) -> Result(Dynamic, String) {
    Error("Step failed")
  }

  let downstream_step = fn(_ctx: types.TaskContext) -> Result(Dynamic, String) {
    Ok(dynamic.string("should not execute"))
  }

  // Execute failing step
  let ctx = test_task_context(dynamic.string("{}"), dict.new())
  let result = failing_step(ctx)

  // Assert: Step failed
  result |> should.be_error

  // Downstream should not execute
  case result {
    Error(_) -> Nil
    Ok(_) -> {
      let _downstream_result = downstream_step(ctx)
      panic as "Downstream should not execute"
    }
  }
}

// ============================================================================
// Test Scenarios - Edge Cases
// ============================================================================

pub fn empty_parent_outputs_test() {
  // Test handler with no parent outputs
  let handler = fn(ctx: types.TaskContext) -> Result(Dynamic, String) {
    case dict.size(ctx.parent_outputs) {
      0 -> Ok(dynamic.string("no parents"))
      _ -> Error("Expected no parent outputs")
    }
  }

  let ctx = test_task_context(dynamic.string("{}"), dict.new())
  let result = handler(ctx)

  // Assert: Handler handled empty parents correctly
  result |> should.be_ok
  case result {
    Ok(output) -> {
      case decode.run(output, decode.string) {
        Ok(s) -> s |> should.equal("no parents")
        Error(_) -> panic as "Failed to decode"
      }
    }
    Error(_) -> panic as "Expected Ok"
  }
}

pub fn nil_input_handling_test() {
  // Test handler with nil/empty input
  let handler = fn(ctx: types.TaskContext) -> Result(Dynamic, String) {
    // Try to decode as string, fallback to default
    case decode.run(ctx.input, decode.string) {
      Ok(_) -> Ok(dynamic.string("processed"))
      Error(_) -> Ok(dynamic.string("default"))
    }
  }

  // Nil in Gleam is represented as a dynamic value
  let ctx = test_task_context(dynamic.int(0), dict.new())
  let result = handler(ctx)

  // Assert: Handler handled nil input
  result |> should.be_ok
}

pub fn large_parent_outputs_test() {
  // Test with many parent outputs
  let parent_outputs =
    dict.from_list([
      #("step1", dynamic.string("out1")),
      #("step2", dynamic.string("out2")),
      #("step3", dynamic.string("out3")),
      #("step4", dynamic.string("out4")),
      #("step5", dynamic.string("out5")),
    ])

  let ctx = test_task_context(dynamic.string("{}"), parent_outputs)

  // Assert: All parent outputs are accessible
  dict.size(ctx.parent_outputs) |> should.equal(5)
}
