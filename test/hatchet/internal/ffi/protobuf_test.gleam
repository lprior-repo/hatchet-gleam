////!

/// Protobuf FFI Tests
import gleam/dict
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import hatchet/internal/ffi/protobuf

pub fn main() {
  gleeunit.main()
}

// ============================================================================
// SDK Language Enum Tests
// ============================================================================

pub fn sdk_language_gleam_test() {
  let lang = protobuf.Gleam
  case lang {
    protobuf.Gleam -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn sdk_language_all_values_test() {
  // Test that all SDK language values exist
  let _unknown = protobuf.Unknown
  let _go = protobuf.Go
  let _python = protobuf.Python
  let _typescript = protobuf.TypeScript
  let _gleam = protobuf.Gleam
  should.be_true(True)
}

// ============================================================================
// Action Type Enum Tests
// ============================================================================

pub fn action_type_start_step_run_test() {
  let action = protobuf.StartStepRun
  case action {
    protobuf.StartStepRun -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn action_type_all_values_test() {
  let _start = protobuf.StartStepRun
  let _cancel = protobuf.CancelStepRun
  let _get_group_key = protobuf.StartGetGroupKey
  should.be_true(True)
}

// ============================================================================
// Step Event Type Enum Tests
// ============================================================================

pub fn step_event_type_all_values_test() {
  let _unknown = protobuf.StepEventTypeUnknown
  let _started = protobuf.StepEventTypeStarted
  let _completed = protobuf.StepEventTypeCompleted
  let _failed = protobuf.StepEventTypeFailed
  let _acked = protobuf.StepEventTypeAcknowledged
  should.be_true(True)
}

pub fn step_event_type_to_int_test() {
  protobuf.step_event_type_to_int(protobuf.StepEventTypeStarted)
  |> should.equal(1)

  protobuf.step_event_type_to_int(protobuf.StepEventTypeCompleted)
  |> should.equal(2)

  protobuf.step_event_type_to_int(protobuf.StepEventTypeFailed)
  |> should.equal(3)
}

// ============================================================================
// RuntimeInfo Tests
// ============================================================================

pub fn runtime_info_type_test() {
  let info =
    protobuf.RuntimeInfo(
      sdk_version: "0.1.0",
      language: protobuf.Gleam,
      language_version: "1.0.0",
      os: "linux/amd64",
      extra: None,
    )
  info.sdk_version |> should.equal("0.1.0")
  case info.language {
    protobuf.Gleam -> should.be_true(True)
    _ -> should.fail()
  }
}

// ============================================================================
// Worker Label Tests
// ============================================================================

pub fn worker_label_string_test() {
  let label = protobuf.StringLabel("production")
  case label {
    protobuf.StringLabel(val) -> val |> should.equal("production")
    _ -> should.fail()
  }
}

pub fn worker_label_int_test() {
  let label = protobuf.IntLabel(42)
  case label {
    protobuf.IntLabel(val) -> val |> should.equal(42)
    _ -> should.fail()
  }
}

// ============================================================================
// Worker Register Request Tests
// ============================================================================

pub fn worker_register_request_type_test() {
  let req =
    protobuf.WorkerRegisterRequest(
      worker_name: "test-worker",
      actions: ["action1", "action2"],
      services: [],
      max_runs: Some(10),
      labels: dict.new(),
      webhook_id: None,
      runtime_info: None,
    )
  req.worker_name |> should.equal("test-worker")
}

pub fn worker_register_request_with_runtime_info_test() {
  let info =
    protobuf.RuntimeInfo(
      sdk_version: "0.1.0",
      language: protobuf.Gleam,
      language_version: "1.0.0",
      os: "linux",
      extra: None,
    )
  let req =
    protobuf.WorkerRegisterRequest(
      worker_name: "test-worker",
      actions: ["workflow:task"],
      services: [],
      max_runs: Some(10),
      labels: dict.new(),
      webhook_id: None,
      runtime_info: Some(info),
    )
  case req.runtime_info {
    Some(ri) -> ri.sdk_version |> should.equal("0.1.0")
    None -> should.fail()
  }
}

pub fn worker_register_response_type_test() {
  let resp =
    protobuf.WorkerRegisterResponse(
      tenant_id: "tenant-123",
      worker_id: "worker-456",
      worker_name: "test-worker",
    )
  resp.worker_id |> should.equal("worker-456")
}

// ============================================================================
// Worker Listen Request Tests
// ============================================================================

pub fn worker_listen_request_type_test() {
  let req = protobuf.WorkerListenRequest(worker_id: "worker-123")
  req.worker_id |> should.equal("worker-123")
}

// ============================================================================
// Assigned Action Tests
// ============================================================================

pub fn assigned_action_type_test() {
  let action =
    protobuf.AssignedAction(
      tenant_id: "tenant-123",
      workflow_run_id: "wf-run-456",
      get_group_key_run_id: "",
      job_id: "job-789",
      job_name: "process-order",
      job_run_id: "job-run-abc",
      step_id: "step-def",
      step_run_id: "step-run-ghi",
      action_id: "action-jkl",
      action_type: protobuf.StartStepRun,
      action_payload: "{\"order_id\": 123}",
      step_name: "validate",
      retry_count: 0,
      additional_metadata: None,
      child_workflow_index: None,
      child_workflow_key: None,
      parent_workflow_run_id: None,
      priority: 1,
      workflow_id: Some("wf-123"),
      workflow_version_id: Some("wf-v1"),
    )
  action.workflow_run_id |> should.equal("wf-run-456")
  action.step_name |> should.equal("validate")
  case action.action_type {
    protobuf.StartStepRun -> should.be_true(True)
    _ -> should.fail()
  }
}

// ============================================================================
// Step Action Event Tests
// ============================================================================

pub fn step_action_event_type_test() {
  let event =
    protobuf.StepActionEvent(
      worker_id: "worker-123",
      job_id: "job-456",
      job_run_id: "job-run-789",
      step_id: "step-abc",
      step_run_id: "step-run-123",
      action_id: "action-456",
      event_timestamp: 1_700_000_000_000,
      event_type: protobuf.StepEventTypeStarted,
      event_payload: "{}",
      retry_count: Some(0),
      should_not_retry: None,
    )
  event.worker_id |> should.equal("worker-123")
  case event.event_type {
    protobuf.StepEventTypeStarted -> should.be_true(True)
    _ -> should.fail()
  }
}

// ============================================================================
// Action Event Response Tests
// ============================================================================

pub fn action_event_response_type_test() {
  let resp =
    protobuf.ActionEventResponse(
      tenant_id: "tenant-123",
      worker_id: "worker-456",
    )
  resp.tenant_id |> should.equal("tenant-123")
  resp.worker_id |> should.equal("worker-456")
}

// ============================================================================
// Encoding Tests
// ============================================================================

pub fn encode_worker_register_request_test() {
  let req =
    protobuf.WorkerRegisterRequest(
      worker_name: "test-worker",
      actions: ["action1"],
      services: [],
      max_runs: Some(5),
      labels: dict.new(),
      webhook_id: None,
      runtime_info: None,
    )
  let assert Ok(_pb) = protobuf.encode_worker_register_request(req)
}

pub fn encode_worker_listen_request_test() {
  let req = protobuf.WorkerListenRequest(worker_id: "worker-123")
  let assert Ok(_pb) = protobuf.encode_worker_listen_request(req)
}

pub fn encode_step_action_event_test() {
  let event =
    protobuf.StepActionEvent(
      worker_id: "worker-123",
      job_id: "job-456",
      job_run_id: "job-run-789",
      step_id: "step-abc",
      step_run_id: "step-run-123",
      action_id: "action-456",
      event_timestamp: 1_700_000_000_000,
      event_type: protobuf.StepEventTypeCompleted,
      event_payload: "{\"result\": \"success\"}",
      retry_count: Some(0),
      should_not_retry: None,
    )
  let assert Ok(_pb) = protobuf.encode_step_action_event(event)
}

pub fn encode_step_action_event_with_no_retry_test() {
  let event =
    protobuf.StepActionEvent(
      worker_id: "worker-123",
      job_id: "job-456",
      job_run_id: "job-run-789",
      step_id: "step-abc",
      step_run_id: "step-run-123",
      action_id: "action-456",
      event_timestamp: 1_700_000_000_000,
      event_type: protobuf.StepEventTypeFailed,
      event_payload: "{\"error\": \"fatal error\"}",
      retry_count: Some(3),
      should_not_retry: Some(True),
    )
  let assert Ok(_pb) = protobuf.encode_step_action_event(event)
}

pub fn encode_heartbeat_request_test() {
  let req =
    protobuf.HeartbeatRequest(
      worker_id: "worker-123",
      heartbeat_at: 1_700_000_000_000,
    )
  let assert Ok(_pb) = protobuf.encode_heartbeat_request(req)
}

// ============================================================================
// Decoding Tests
// ============================================================================

pub fn decode_worker_register_response_test() {
  let mock = protobuf.protobuf_message_from_bits(<<>>)
  let assert Error(_) = protobuf.decode_worker_register_response(mock)
}

pub fn decode_heartbeat_response_test() {
  let mock = protobuf.protobuf_message_from_bits(<<>>)
  let assert Ok(_) = protobuf.decode_heartbeat_response(mock)
}

// ============================================================================
// Error Type Tests
// ============================================================================

pub fn protobuf_error_types_test() {
  let err = protobuf.ProtobufEncodeError("test")
  let err2 = protobuf.ProtobufDecodeError("test")
  case err {
    protobuf.ProtobufEncodeError(msg) -> msg |> should.equal("test")
  }
  case err2 {
    protobuf.ProtobufDecodeError(msg) -> msg |> should.equal("test")
  }
}

// ============================================================================
// Helper Function Tests
// ============================================================================

pub fn protobuf_message_round_trip_test() {
  let bits = <<1, 2, 3, 4, 5>>
  let msg = protobuf.protobuf_message_from_bits(bits)
  let result = protobuf.protobuf_message_to_bits(msg)
  result |> should.equal(bits)
}
