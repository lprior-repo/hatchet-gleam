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

// ============================================================================
// Error Types
// ============================================================================

pub type ProtobufError {
  ProtobufEncodeError(String)
  ProtobufDecodeError(String)
}

// ============================================================================
// SDK Language Enum (matches SDKS enum in proto)
// ============================================================================

pub type SdkLanguage {
  Unknown
  Go
  Python
  TypeScript
  Gleam
}

fn sdk_language_to_int(lang: SdkLanguage) -> Int {
  case lang {
    Unknown -> 0
    Go -> 1
    Python -> 2
    TypeScript -> 3
    Gleam -> 4
  }
}

fn int_to_sdk_language(i: Int) -> SdkLanguage {
  case i {
    1 -> Go
    2 -> Python
    3 -> TypeScript
    4 -> Gleam
    _ -> Unknown
  }
}

// ============================================================================
// Action Type Enum (matches ActionType enum in proto)
// ============================================================================

pub type ActionType {
  StartStepRun
  CancelStepRun
  StartGetGroupKey
}

fn int_to_action_type(i: Int) -> ActionType {
  case i {
    1 -> CancelStepRun
    2 -> StartGetGroupKey
    _ -> StartStepRun
  }
}

fn action_type_to_int(action: ActionType) -> Int {
  case action {
    StartStepRun -> 0
    CancelStepRun -> 1
    StartGetGroupKey -> 2
  }
}

// ============================================================================
// Step Action Event Type Enum
// ============================================================================

pub type StepActionEventType {
  StepEventTypeUnknown
  StepEventTypeStarted
  StepEventTypeCompleted
  StepEventTypeFailed
  StepEventTypeAcknowledged
  StepEventTypeStream
  StepEventTypeRefreshTimeout
  StepEventTypeCancelled
}

pub fn step_event_type_to_int(event_type: StepActionEventType) -> Int {
  case event_type {
    StepEventTypeUnknown -> 0
    StepEventTypeStarted -> 1
    StepEventTypeCompleted -> 2
    StepEventTypeFailed -> 3
    StepEventTypeAcknowledged -> 4
    StepEventTypeStream -> 5
    StepEventTypeRefreshTimeout -> 6
    StepEventTypeCancelled -> 7
  }
}

fn int_to_step_event_type(i: Int) -> StepActionEventType {
  case i {
    1 -> StepEventTypeStarted
    2 -> StepEventTypeCompleted
    3 -> StepEventTypeFailed
    4 -> StepEventTypeAcknowledged
    5 -> StepEventTypeStream
    6 -> StepEventTypeRefreshTimeout
    7 -> StepEventTypeCancelled
    _ -> StepEventTypeUnknown
  }
}

// ============================================================================
// Runtime Info (SDK metadata sent during registration)
// ============================================================================

pub type RuntimeInfo {
  RuntimeInfo(
    sdk_version: String,
    language: SdkLanguage,
    language_version: String,
    os: String,
    extra: Option(String),
  )
}

// ============================================================================
// Worker Labels (for worker affinity)
// ============================================================================

pub type WorkerLabel {
  StringLabel(String)
  IntLabel(Int)
}

// ============================================================================
// Worker Registration Types
// ============================================================================

pub type WorkerRegisterRequest {
  WorkerRegisterRequest(
    worker_name: String,
    actions: List(String),
    services: List(String),
    max_runs: Option(Int),
    labels: dict.Dict(String, WorkerLabel),
    webhook_id: Option(String),
    runtime_info: Option(RuntimeInfo),
  )
}

pub type WorkerRegisterResponse {
  WorkerRegisterResponse(
    tenant_id: String,
    worker_id: String,
    worker_name: String,
  )
}

// ============================================================================
// Worker Listen Request (sent to start ListenV2 stream)
// ============================================================================

pub type WorkerListenRequest {
  WorkerListenRequest(worker_id: String)
}

// ============================================================================
// Assigned Action (received from dispatcher when task is assigned)
// ============================================================================

pub type AssignedAction {
  AssignedAction(
    tenant_id: String,
    workflow_run_id: String,
    get_group_key_run_id: String,
    job_id: String,
    job_name: String,
    job_run_id: String,
    step_id: String,
    step_run_id: String,
    action_id: String,
    action_type: ActionType,
    action_payload: String,
    step_name: String,
    retry_count: Int,
    additional_metadata: Option(String),
    child_workflow_index: Option(Int),
    child_workflow_key: Option(String),
    parent_workflow_run_id: Option(String),
    priority: Int,
    workflow_id: Option(String),
    workflow_version_id: Option(String),
  )
}

// ============================================================================
// Step Action Event (sent to report task status)
// ============================================================================

pub type StepActionEvent {
  StepActionEvent(
    worker_id: String,
    job_id: String,
    job_run_id: String,
    step_id: String,
    step_run_id: String,
    action_id: String,
    event_timestamp: Int,
    event_type: StepActionEventType,
    event_payload: String,
    retry_count: Option(Int),
    should_not_retry: Option(Bool),
  )
}

// ============================================================================
// Action Event Response
// ============================================================================

pub type ActionEventResponse {
  ActionEventResponse(tenant_id: String, worker_id: String)
}

// ============================================================================
// Heartbeat Types
// ============================================================================

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
  // Add runtime_info if present
  let map = case req.runtime_info {
    Some(info) -> {
      let info_map = erlang_map_new()
      let info_map =
        erlang_map_put_string(info_map, "sdk_version", info.sdk_version)
      let info_map =
        erlang_map_put_int(
          info_map,
          "language",
          sdk_language_to_int(info.language),
        )
      let info_map =
        erlang_map_put_string(
          info_map,
          "language_version",
          info.language_version,
        )
      let info_map = erlang_map_put_string(info_map, "os", info.os)
      let info_map = case info.extra {
        Some(e) -> erlang_map_put_string(info_map, "extra", e)
        None -> info_map
      }
      erlang_map_put_nested(map, "runtime_info", info_map)
    }
    None -> map
  }
  // Add labels if present
  let map = case dict.size(req.labels) > 0 {
    True -> {
      let label_maps =
        dict.fold(req.labels, [], fn(acc, key, value) {
          let label_map = erlang_map_new()
          let label_map = case value {
            StringLabel(s) -> erlang_map_put_string(label_map, "str_value", s)
            IntLabel(i) -> erlang_map_put_int(label_map, "int_value", i)
          }
          [#(key, label_map), ..acc]
        })
      erlang_map_put_label_map(map, "labels", label_maps)
    }
    False -> map
  }
  Ok(ProtobufMessage(encode_msg("WorkerRegisterRequest", map)))
}

/// Encode a WorkerListenRequest for starting the ListenV2 stream
pub fn encode_worker_listen_request(
  req: WorkerListenRequest,
) -> Result(ProtobufMessage, ProtobufError) {
  let map = erlang_map_new()
  let map = erlang_map_put_string(map, "worker_id", req.worker_id)
  Ok(ProtobufMessage(encode_msg("WorkerListenRequest", map)))
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
  let map =
    erlang_map_put_int(
      map,
      "event_type",
      step_event_type_to_int(event.event_type),
    )
  let map = erlang_map_put_string(map, "event_payload", event.event_payload)
  let map = case event.retry_count {
    Some(count) -> erlang_map_put_int(map, "retry_count", count)
    None -> map
  }
  let map = case event.should_not_retry {
    Some(True) -> erlang_map_put_bool(map, "should_not_retry", True)
    Some(False) -> erlang_map_put_bool(map, "should_not_retry", False)
    None -> map
  }
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

/// Decode an AssignedAction from the dispatcher
pub fn decode_assigned_action(
  binary: ProtobufMessage,
) -> Result(AssignedAction, ProtobufError) {
  let ProtobufMessage(bits) = binary
  let map = decode_msg("AssignedAction", bits)

  // Required fields
  let tenant_id = erlang_map_get_string_default(map, "tenant_id", "")
  let workflow_run_id =
    erlang_map_get_string_default(map, "workflow_run_id", "")
  let get_group_key_run_id =
    erlang_map_get_string_default(map, "get_group_key_run_id", "")
  let job_id = erlang_map_get_string_default(map, "job_id", "")
  let job_name = erlang_map_get_string_default(map, "job_name", "")
  let job_run_id = erlang_map_get_string_default(map, "job_run_id", "")
  let step_id = erlang_map_get_string_default(map, "step_id", "")
  let step_run_id = erlang_map_get_string_default(map, "step_run_id", "")
  let action_id = erlang_map_get_string_default(map, "action_id", "")
  let action_type_int = erlang_map_get_int_default(map, "action_type", 0)
  let action_payload =
    erlang_map_get_string_default(map, "action_payload", "{}")
  let step_name = erlang_map_get_string_default(map, "step_name", "")
  let retry_count = erlang_map_get_int_default(map, "retry_count", 0)
  let priority = erlang_map_get_int_default(map, "priority", 0)

  // Optional fields
  let additional_metadata =
    erlang_map_get_string_option(map, "additional_metadata")
  let child_workflow_index =
    erlang_map_get_int_option(map, "child_workflow_index")
  let child_workflow_key =
    erlang_map_get_string_option(map, "child_workflow_key")
  let parent_workflow_run_id =
    erlang_map_get_string_option(map, "parent_workflow_run_id")
  let workflow_id = erlang_map_get_string_option(map, "workflow_id")
  let workflow_version_id =
    erlang_map_get_string_option(map, "workflow_version_id")

  Ok(AssignedAction(
    tenant_id: tenant_id,
    workflow_run_id: workflow_run_id,
    get_group_key_run_id: get_group_key_run_id,
    job_id: job_id,
    job_name: job_name,
    job_run_id: job_run_id,
    step_id: step_id,
    step_run_id: step_run_id,
    action_id: action_id,
    action_type: int_to_action_type(action_type_int),
    action_payload: action_payload,
    step_name: step_name,
    retry_count: retry_count,
    additional_metadata: additional_metadata,
    child_workflow_index: child_workflow_index,
    child_workflow_key: child_workflow_key,
    parent_workflow_run_id: parent_workflow_run_id,
    priority: priority,
    workflow_id: workflow_id,
    workflow_version_id: workflow_version_id,
  ))
}

/// Decode an ActionEventResponse from the dispatcher
pub fn decode_action_event_response(
  binary: ProtobufMessage,
) -> Result(ActionEventResponse, ProtobufError) {
  let ProtobufMessage(bits) = binary
  let map = decode_msg("ActionEventResponse", bits)

  let tenant_id = erlang_map_get_string_default(map, "tenant_id", "")
  let worker_id = erlang_map_get_string_default(map, "worker_id", "")

  Ok(ActionEventResponse(tenant_id: tenant_id, worker_id: worker_id))
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

@external(erlang, "dispatcher_pb_helper", "get_string_default")
fn erlang_map_get_string_default(
  map: ErlangMap,
  key: String,
  default: String,
) -> String

@external(erlang, "dispatcher_pb_helper", "get_string_option")
fn erlang_map_get_string_option(map: ErlangMap, key: String) -> Option(String)

@external(erlang, "dispatcher_pb_helper", "get_int")
fn erlang_map_get_int(map: ErlangMap, key: String) -> Result(Int, Nil)

@external(erlang, "dispatcher_pb_helper", "get_int_default")
fn erlang_map_get_int_default(map: ErlangMap, key: String, default: Int) -> Int

@external(erlang, "dispatcher_pb_helper", "get_int_option")
fn erlang_map_get_int_option(map: ErlangMap, key: String) -> Option(Int)

@external(erlang, "dispatcher_pb_helper", "put_bool")
fn erlang_map_put_bool(map: ErlangMap, key: String, value: Bool) -> ErlangMap

@external(erlang, "dispatcher_pb_helper", "put_nested")
fn erlang_map_put_nested(
  map: ErlangMap,
  key: String,
  nested: ErlangMap,
) -> ErlangMap

@external(erlang, "dispatcher_pb_helper", "put_label_map")
fn erlang_map_put_label_map(
  map: ErlangMap,
  key: String,
  labels: List(#(String, ErlangMap)),
) -> ErlangMap
