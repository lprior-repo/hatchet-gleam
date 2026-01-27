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

pub fn worker_register_request_type_test() {
  let req =
    protobuf.WorkerRegisterRequest(
      worker_name: "test-worker",
      actions: ["action1", "action2"],
      services: [],
      max_runs: Some(10),
      labels: dict.from_list([#("env", "test")]),
      webhook_id: None,
    )
  req.worker_name |> should.equal("test-worker")
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

pub fn encode_worker_register_request_test() {
  let req =
    protobuf.WorkerRegisterRequest(
      worker_name: "test-worker",
      actions: ["action1"],
      services: [],
      max_runs: Some(5),
      labels: dict.new(),
      webhook_id: None,
    )
  let assert Ok(_pb) = protobuf.encode_worker_register_request(req)
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
      event_type: 1,
      event_payload: "{}",
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

pub fn decode_worker_register_response_test() {
  let mock = protobuf.protobuf_message_from_bits(<<>>)
  let assert Error(_) = protobuf.decode_worker_register_response(mock)
}

pub fn decode_heartbeat_response_test() {
  let mock = protobuf.protobuf_message_from_bits(<<>>)
  let assert Ok(_) = protobuf.decode_heartbeat_response(mock)
}

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
