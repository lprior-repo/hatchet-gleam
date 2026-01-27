//// Worker Actor Tests
////
//// Tests for the worker actor types and message handling.
//// Note: Full integration tests require a running Hatchet server.

import gleeunit
import gleeunit/should
import gleam/dict
import gleam/dynamic
import gleam/option.{None, Some}
import hatchet/internal/worker_actor
import hatchet/internal/ffi/protobuf

pub fn main() {
  gleeunit.main()
}

// ============================================================================
// Worker Message Type Tests
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

pub fn worker_message_send_heartbeat_test() {
  let msg = worker_actor.SendHeartbeat
  case msg {
    worker_actor.SendHeartbeat -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn worker_message_heartbeat_success_test() {
  let msg = worker_actor.HeartbeatSuccess
  case msg {
    worker_actor.HeartbeatSuccess -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn worker_message_heartbeat_failed_test() {
  let msg = worker_actor.HeartbeatFailed
  case msg {
    worker_actor.HeartbeatFailed -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn worker_message_listen_loop_test() {
  let msg = worker_actor.ListenLoop
  case msg {
    worker_actor.ListenLoop -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn worker_message_listen_error_test() {
  let msg = worker_actor.ListenError("connection reset")
  case msg {
    worker_actor.ListenError(err) -> err |> should.equal("connection reset")
    _ -> should.fail()
  }
}

pub fn worker_message_task_received_test() {
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

  let msg = worker_actor.TaskReceived(action)
  case msg {
    worker_actor.TaskReceived(a) -> a.step_name |> should.equal("my-task")
    _ -> should.fail()
  }
}

pub fn worker_message_task_completed_test() {
  let output = dynamic.from("result")
  let msg = worker_actor.TaskCompleted("step-run-123", output)
  case msg {
    worker_actor.TaskCompleted(step_run_id, _) ->
      step_run_id |> should.equal("step-run-123")
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

// ============================================================================
// Task Handler Type Tests
// ============================================================================

pub fn task_handler_type_test() {
  let handler = worker_actor.TaskHandler(
    workflow_name: "my-workflow",
    task_name: "my-task",
    handler: fn(_ctx) { Ok(dynamic.from("result")) },
    retries: 3,
  )

  handler.workflow_name |> should.equal("my-workflow")
  handler.task_name |> should.equal("my-task")
  handler.retries |> should.equal(3)
}

// ============================================================================
// Task Message Type Tests
// ============================================================================

pub fn task_message_execute_test() {
  let msg = worker_actor.Execute
  case msg {
    worker_actor.Execute -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn task_message_cancel_test() {
  let msg = worker_actor.Cancel
  case msg {
    worker_actor.Cancel -> should.be_true(True)
    _ -> should.fail()
  }
}
