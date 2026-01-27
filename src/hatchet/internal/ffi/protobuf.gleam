////!
//// Errors
//// Message Types
//// Create a ProtobufMessage from raw bits (for testing)
//// Extract the raw bits from a ProtobufMessage
//// Opaque type for Erlang map with mixed value types
//// Encoding - using Erlang map construction
//// Decoding
//// FFI to gpb-generated dispatcher_pb module (via helper for atom conversion)
//// Erlang map construction helpers via dispatcher_pb_helper

//! Simplified protobuf encoding/decoding using gpb-generated Erlang modules.

/// Protobuf FFI Module for Hatchet Dispatcher
///
import gleam/dict
import gleam/option.{type Option, None, Some}

pub type ProtobufError {
  ProtobufEncodeError(String)
  ProtobufDecodeError(String)
}

pub type WorkerRegisterRequest {
  WorkerRegisterRequest(
    worker_name: String,
    actions: List(String),
    services: List(String),
    max_runs: Option(Int),
    labels: dict.Dict(String, String),
    webhook_id: Option(String),
  )
}

pub type WorkerRegisterResponse {
  WorkerRegisterResponse(
    tenant_id: String,
    worker_id: String,
    worker_name: String,
  )
}

pub type StepActionEvent {
  StepActionEvent(
    worker_id: String,
    job_id: String,
    job_run_id: String,
    step_id: String,
    step_run_id: String,
    action_id: String,
    event_timestamp: Int,
    event_type: Int,
    event_payload: String,
  )
}

pub type HeartbeatRequest {
  HeartbeatRequest(worker_id: String, heartbeat_at: Int)
}

pub type HeartbeatResponse {
  HeartbeatResponse
}

pub opaque type ProtobufMessage {
  ProtobufMessage(BitArray)
}

pub fn protobuf_message_from_bits(bits: BitArray) -> ProtobufMessage {
  ProtobufMessage(bits)
}

pub fn protobuf_message_to_bits(msg: ProtobufMessage) -> BitArray {
  let ProtobufMessage(bits) = msg
  bits
}

pub type ErlangMap

pub fn encode_worker_register_request(
  req: WorkerRegisterRequest,
) -> Result(ProtobufMessage, ProtobufError) {
  let map = erlang_map_new()
  let map = erlang_map_put_string(map, "worker_name", req.worker_name)
  let map = erlang_map_put_list(map, "actions", req.actions)
  let map = erlang_map_put_list(map, "services", req.services)
  let map = case req.max_runs {
    Some(v) -> erlang_map_put_int(map, "max_runs", v)
    None -> map
  }
  let map = case req.webhook_id {
    Some(v) -> erlang_map_put_string(map, "webhook_id", v)
    None -> map
  }
  Ok(ProtobufMessage(encode_msg("WorkerRegisterRequest", map)))
}

pub fn encode_step_action_event(
  event: StepActionEvent,
) -> Result(ProtobufMessage, ProtobufError) {
  let map = erlang_map_new()
  let map = erlang_map_put_string(map, "worker_id", event.worker_id)
  let map = erlang_map_put_string(map, "job_id", event.job_id)
  let map = erlang_map_put_string(map, "job_run_id", event.job_run_id)
  let map = erlang_map_put_string(map, "step_id", event.step_id)
  let map = erlang_map_put_string(map, "step_run_id", event.step_run_id)
  let map = erlang_map_put_string(map, "action_id", event.action_id)
  let map = erlang_map_put_int(map, "event_timestamp", event.event_timestamp)
  let map = erlang_map_put_int(map, "event_type", event.event_type)
  let map = erlang_map_put_string(map, "event_payload", event.event_payload)
  Ok(ProtobufMessage(encode_msg("StepActionEvent", map)))
}

pub fn encode_heartbeat_request(
  req: HeartbeatRequest,
) -> Result(ProtobufMessage, ProtobufError) {
  let map = erlang_map_new()
  let map = erlang_map_put_string(map, "worker_id", req.worker_id)
  let map = erlang_map_put_int(map, "heartbeat_at", req.heartbeat_at)
  Ok(ProtobufMessage(encode_msg("HeartbeatRequest", map)))
}

pub fn decode_worker_register_response(
  binary: ProtobufMessage,
) -> Result(WorkerRegisterResponse, ProtobufError) {
  let ProtobufMessage(bits) = binary
  let map = decode_msg("WorkerRegisterResponse", bits)
  case erlang_map_get_string(map, "worker_id") {
    Ok(worker_id) ->
      case erlang_map_get_string(map, "worker_name") {
        Ok(worker_name) ->
          case erlang_map_get_string(map, "tenant_id") {
            Ok(tenant_id) ->
              Ok(WorkerRegisterResponse(
                tenant_id: tenant_id,
                worker_id: worker_id,
                worker_name: worker_name,
              ))
            Error(_) -> Error(ProtobufDecodeError("Missing: tenant_id"))
          }
        Error(_) -> Error(ProtobufDecodeError("Missing: worker_name"))
      }
    Error(_) -> Error(ProtobufDecodeError("Missing: worker_id"))
  }
}

pub fn decode_heartbeat_response(
  binary: ProtobufMessage,
) -> Result(HeartbeatResponse, ProtobufError) {
  let ProtobufMessage(bits) = binary
  let _map = decode_msg("HeartbeatResponse", bits)
  Ok(HeartbeatResponse)
}

@external(erlang, "dispatcher_pb_helper", "encode_msg")
fn encode_msg(msg_type: String, map: ErlangMap) -> BitArray

@external(erlang, "dispatcher_pb_helper", "decode_msg")
fn decode_msg(msg_type: String, binary: BitArray) -> ErlangMap

@external(erlang, "dispatcher_pb_helper", "new_map")
fn erlang_map_new() -> ErlangMap

@external(erlang, "dispatcher_pb_helper", "put_string")
fn erlang_map_put_string(
  map: ErlangMap,
  key: String,
  value: String,
) -> ErlangMap

@external(erlang, "dispatcher_pb_helper", "put_int")
fn erlang_map_put_int(map: ErlangMap, key: String, value: Int) -> ErlangMap

@external(erlang, "dispatcher_pb_helper", "put_list")
fn erlang_map_put_list(map: ErlangMap, key: String, value: List(a)) -> ErlangMap

@external(erlang, "dispatcher_pb_helper", "get_string")
fn erlang_map_get_string(map: ErlangMap, key: String) -> Result(String, Nil)
