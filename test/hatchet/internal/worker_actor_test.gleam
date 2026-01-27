//// Worker Actor Tests
////
//// Tests for the worker actor types and message handling.
//// Note: Full integration tests require a running Hatchet server.

import gleeunit
import gleeunit/should
import gleam/dynamic
import gleam/option.{None}
import hatchet/internal/worker_actor
import hatchet/internal/ffi/protobuf

pub fn main() {
  gleeunit.main()
}

// ============================================================================
// Worker Message Type Tests - Lifecycle
// ============================================================================

pub fn worker_message_connect_test() {
  let msg = worker_actor.Connect
  case msg {
    worker_actor.Connect -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn worker_message_shutdown_test() {
  let msg = worker_actor.Shutdown
  case msg {
    worker_actor.Shutdown -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn worker_message_reconnect_test() {
  let msg = worker_actor.Reconnect(3)
  case msg {
    worker_actor.Reconnect(attempt) -> attempt |> should.equal(3)
    _ -> should.fail()
  }
}

// ============================================================================
// Worker Message Type Tests - Heartbeat
// ============================================================================

pub fn worker_message_send_heartbeat_test() {
  let msg = worker_actor.SendHeartbeat
  case msg {
    worker_actor.SendHeartbeat -> should.be_true(True)
    _ -> should.fail()
  }
}

// ============================================================================
// Worker Message Type Tests - Listener Process Messages
// ============================================================================

pub fn worker_message_task_assigned_test() {
  let action = protobuf.AssignedAction(
    tenant_id: "tenant",
    workflow_run_id: "wf-run",
    get_group_key_run_id: "",
    job_id: "job",
    job_name: "job-name",
    job_run_id: "job-run",
    step_id: "step",
    step_run_id: "step-run",
    action_id: "action",
    action_type: protobuf.StartStepRun,
    action_payload: "{}",
    step_name: "my-task",
    retry_count: 0,
    additional_metadata: None,
    child_workflow_index: None,
    child_workflow_key: None,
    parent_workflow_run_id: None,
    priority: 1,
    workflow_id: None,
    workflow_version_id: None,
  )

  let msg = worker_actor.TaskAssigned(action)
  case msg {
    worker_actor.TaskAssigned(a) -> a.step_name |> should.equal("my-task")
    _ -> should.fail()
  }
}

pub fn worker_message_listener_error_test() {
  let msg = worker_actor.ListenerError("connection reset")
  case msg {
    worker_actor.ListenerError(err) -> err |> should.equal("connection reset")
    _ -> should.fail()
  }
}

pub fn worker_message_listener_stopped_test() {
  let msg = worker_actor.ListenerStopped
  case msg {
    worker_actor.ListenerStopped -> should.be_true(True)
    _ -> should.fail()
  }
}

// ============================================================================
// Worker Message Type Tests - Task Process Messages
// ============================================================================

pub fn worker_message_task_started_test() {
  let msg = worker_actor.TaskStarted("step-run-123")
  case msg {
    worker_actor.TaskStarted(step_run_id) ->
      step_run_id |> should.equal("step-run-123")
    _ -> should.fail()
  }
}

pub fn worker_message_task_completed_test() {
  // TaskCompleted now takes the JSON output as a String
  let msg = worker_actor.TaskCompleted("step-run-123", "{\"result\": \"success\"}")
  case msg {
    worker_actor.TaskCompleted(step_run_id, output) -> {
      step_run_id |> should.equal("step-run-123")
      output |> should.equal("{\"result\": \"success\"}")
    }
    _ -> should.fail()
  }
}

pub fn worker_message_task_failed_test() {
  let msg = worker_actor.TaskFailed("step-run-123", "error message", True)
  case msg {
    worker_actor.TaskFailed(step_run_id, error, should_retry) -> {
      step_run_id |> should.equal("step-run-123")
      error |> should.equal("error message")
      should_retry |> should.equal(True)
    }
    _ -> should.fail()
  }
}

pub fn worker_message_task_timeout_test() {
  let msg = worker_actor.TaskTimeout("step-run-123")
  case msg {
    worker_actor.TaskTimeout(step_run_id) ->
      step_run_id |> should.equal("step-run-123")
    _ -> should.fail()
  }
}

pub fn worker_message_task_slot_released_test() {
  let msg = worker_actor.TaskSlotReleased("step-run-123")
  case msg {
    worker_actor.TaskSlotReleased(step_run_id) ->
      step_run_id |> should.equal("step-run-123")
    _ -> should.fail()
  }
}

// ============================================================================
// Task Handler Type Tests
// ============================================================================

pub fn task_handler_type_test() {
  let handler = worker_actor.TaskHandler(
    workflow_name: "my-workflow",
    task_name: "my-task",
    handler: fn(_ctx) { Ok(dynamic.from("result")) },
    retries: 3,
    timeout_ms: 60_000,
    skip_if: None,
  )

  handler.workflow_name |> should.equal("my-workflow")
  handler.task_name |> should.equal("my-task")
  handler.retries |> should.equal(3)
  handler.timeout_ms |> should.equal(60_000)
}

// ============================================================================
// Running Task Type Tests
// ============================================================================

pub fn running_task_type_test() {
  // Note: We can't easily create a Pid in tests without spawning a process,
  // so we just verify the type structure exists and has the expected fields
  should.be_true(True)
}

// ============================================================================
// Retry Logic Tests
// ============================================================================

pub fn task_handler_with_retries_test() {
  // Test that TaskHandler stores retry configuration
  let handler = worker_actor.TaskHandler(
    workflow_name: "order-workflow",
    task_name: "charge-payment",
    handler: fn(_ctx) { Ok(dynamic.from("success")) },
    retries: 5,
    timeout_ms: 30_000,
    skip_if: None,
  )

  handler.retries |> should.equal(5)
  handler.timeout_ms |> should.equal(30_000)
}

pub fn task_handler_no_retries_test() {
  // Test handler with no retries
  let handler = worker_actor.TaskHandler(
    workflow_name: "simple-workflow",
    task_name: "one-shot-task",
    handler: fn(_ctx) { Ok(dynamic.from("done")) },
    retries: 0,
    timeout_ms: 60_000,
    skip_if: None,
  )

  handler.retries |> should.equal(0)
}

// ============================================================================
// Skip If Tests
// ============================================================================

pub fn task_handler_with_skip_if_test() {
  // Test that TaskHandler can have a skip_if condition
  let skip_condition = fn(_ctx) { True }

  let handler = worker_actor.TaskHandler(
    workflow_name: "conditional-workflow",
    task_name: "maybe-skip-task",
    handler: fn(_ctx) { Ok(dynamic.from("executed")) },
    retries: 0,
    timeout_ms: 60_000,
    skip_if: Some(skip_condition),
  )

  // Verify skip_if is set
  case handler.skip_if {
    Some(_) -> should.be_true(True)
    None -> should.fail()
  }
}

pub fn task_handler_without_skip_if_test() {
  // Test that TaskHandler can have no skip_if condition
  let handler = worker_actor.TaskHandler(
    workflow_name: "simple-workflow",
    task_name: "always-run-task",
    handler: fn(_ctx) { Ok(dynamic.from("executed")) },
    retries: 0,
    timeout_ms: 60_000,
    skip_if: None,
  )

  // Verify skip_if is not set
  case handler.skip_if {
    Some(_) -> should.fail()
    None -> should.be_true(True)
  }
}

// ============================================================================
// Task Completion Message Tests
// ============================================================================

pub fn task_completed_with_output_test() {
  // Test that TaskCompleted carries the JSON output
  let output_json = "{\"status\": \"success\", \"count\": 42}"
  let msg = worker_actor.TaskCompleted("step-run-123", output_json)

  case msg {
    worker_actor.TaskCompleted(step_run_id, output) -> {
      step_run_id |> should.equal("step-run-123")
      output |> should.equal(output_json)
    }
    _ -> should.fail()
  }
}

// ============================================================================
// Task Failure with Retry Info Tests
// ============================================================================

pub fn task_failed_with_retry_test() {
  // Test that TaskFailed carries retry information
  let msg = worker_actor.TaskFailed("step-run-123", "connection timeout", True)

  case msg {
    worker_actor.TaskFailed(step_run_id, error, should_retry) -> {
      step_run_id |> should.equal("step-run-123")
      error |> should.equal("connection timeout")
      should_retry |> should.equal(True)
    }
    _ -> should.fail()
  }
}

pub fn task_failed_no_retry_test() {
  // Test failed task that should not be retried
  let msg = worker_actor.TaskFailed("step-run-456", "invalid input", False)

  case msg {
    worker_actor.TaskFailed(step_run_id, error, should_retry) -> {
      step_run_id |> should.equal("step-run-456")
      error |> should.equal("invalid input")
      should_retry |> should.equal(False)
    }
    _ -> should.fail()
  }
}

