////!
//// ========================================================================
//// ========================================================================
//// A gRPC channel to the Hatchet dispatcher.
//// A bidirectional stream for receiving task assignments.
//// ========================================================================
//// ========================================================================
//// Types of step events that can be reported to the dispatcher.
//// ========================================================================
//// ========================================================================
//// Connect to the Hatchet gRPC dispatcher.
////
//// **Parameters:**
////   - `host` - The Hatchet server hostname
////   - `port` - The gRPC port (default 7070)
////   - `tls_config` - TLS/mTLS configuration
////   - `timeout_ms` - Connection timeout in milliseconds
////
//// **Returns:** `Ok(Channel)` on success, `Error(String)` on failure
//// Register a worker with the Hatchet dispatcher.
////
//// **Parameters:**
////   - `channel` - The gRPC channel
////   - `request` - The worker registration request
////
//// **Returns:** `Ok(RegisterResponse)` on success, `Error(String)` on failure
//// Start listening for task assignments via ListenV2.
////
//// **Parameters:**
////   - `channel` - The gRPC channel
////   - `worker_id` - The worker identifier from registration
////
//// **Returns:** `Ok(Stream)` on success, `Error(String)` on failure
//// Send a step event on the active stream.
////
//// **Parameters:**
////   - `stream` - The ListenV2 stream
////   - `event_data` - The encoded step action event
////
//// **Returns:** `Ok(Nil)` on success, `Error(String)` on failure
//// Send a heartbeat to keep the worker connection alive.
////
//// **Parameters:**
////   - `stream` - The ListenV2 stream
////   - `heartbeat_data` - The encoded heartbeat request
////
//// **Returns:** `Ok(Nil)` on success, `Error(String)` on failure
//// Receive a message from the stream.
////
//// **Parameters:**
////   - `stream` - The ListenV2 stream
////   - `timeout_ms` - Receive timeout in milliseconds
////
//// **Returns:** `Ok(BitArray)` on success, `Error(String)` on failure
//// Close a gRPC channel.
////
//// **Parameters:**
////   - `channel` - The gRPC channel to close
//// Close a bidirectional stream.
////
//// **Parameters:**
////   - `stream` - The stream to close
//// ========================================================================
//// ========================================================================
//// Response from worker registration.
//// ========================================================================
//// ========================================================================
//// Convert event type to string for debugging.
//// ========================================================================
//// ========================================================================
//// Create a mock channel for testing.
//// Create a mock stream for testing.
//// Get the internal pid from a Channel (for testing compatibility).
//// Get the internal pid from a Stream (for testing compatibility).

//! This module provides a Gleam-friendly interface to the Hatchet gRPC
//! dispatcher using Erlang FFI to grpcbox.

/// gRPC Client Module
///
import gleam/option.{type Option, None, Some}
import hatchet/internal/ffi/grpcbox
import hatchet/internal/ffi/protobuf
import hatchet/internal/tls.{type TLSConfig, Insecure, Mtls, Tls}

/// Connection Types
pub opaque type Channel {
  Channel(grpcbox.Channel)
}

pub opaque type Stream {
  Stream(grpcbox.Stream)
}

/// Step Event Types
pub type StepEventType {
  Started
  Completed
  Failed
  Cancelled
  Timeout
}

/// Connection Management
pub fn connect(
  host: String,
  port: Int,
  tls_config: TLSConfig,
  timeout_ms: Int,
) -> Result(Channel, String) {
  let grpcbox_opts = convert_tls_config(tls_config)
  let conn_opts =
    grpcbox.ConnectionOptions(
      host: host,
      port: port,
      tls_config: grpcbox_opts,
      timeout_ms: timeout_ms,
    )
  case grpcbox.connect(conn_opts) {
    Ok(ch) -> Ok(Channel(ch))
    Error(e) -> Error(error_to_string(e))
  }
}

fn convert_tls_config(tls: TLSConfig) -> Option(grpcbox.TLSConfig) {
  case tls {
    Insecure -> None
    Tls(ca_path) -> {
      Some(grpcbox.TLSConfig(
        ca_file: Some(ca_path),
        cert_file: None,
        key_file: None,
        verify: Some(True),
      ))
    }
    Mtls(ca_path, cert_path, key_path) -> {
      Some(grpcbox.TLSConfig(
        ca_file: Some(ca_path),
        cert_file: Some(cert_path),
        key_file: Some(key_path),
        verify: Some(True),
      ))
    }
  }
}

fn error_to_string(err: grpcbox.GrpcError) -> String {
  case err {
    grpcbox.GrpcConnectionError(msg) -> "Connection error: " <> msg
    grpcbox.GrpcRpcError(msg) -> "RPC error: " <> msg
    grpcbox.GrpcStreamError(msg) -> "Stream error: " <> msg
  }
}

pub fn register_worker(
  channel: Channel,
  request: protobuf.ProtobufMessage,
) -> Result(RegisterResponse, String) {
  let Channel(ch) = channel
  let data = protobuf.protobuf_message_to_bits(request)
  let rpc_opts = grpcbox.RpcOptions(timeout_ms: 5000, metadata: [])
  case
    grpcbox.unary_call(
      ch,
      "hatchet.dispatcher.Dispatcher",
      "Register",
      data,
      rpc_opts,
    )
  {
    Ok(resp_data) ->
      case
        protobuf.decode_worker_register_response(
          protobuf.protobuf_message_from_bits(resp_data),
        )
      {
        Ok(resp) -> Ok(RegisterResponse(worker_id: resp.worker_id))
        Error(e) -> Error("Decode error: " <> error_message(e))
      }
    Error(e) -> Error(error_to_string(e))
  }
}

fn error_message(err: protobuf.ProtobufError) -> String {
  case err {
    protobuf.ProtobufEncodeError(msg) -> msg
    protobuf.ProtobufDecodeError(msg) -> msg
  }
}

/// Start listening for task assignments via ListenV2 bidirectional stream.
///
/// This establishes a bidirectional gRPC stream with the dispatcher.
/// The stream is used to:
/// 1. Receive AssignedAction messages (task assignments)
/// 2. Send heartbeats to keep the connection alive
///
/// **Parameters:**
///   - `channel` - The gRPC channel
///   - `worker_id` - The worker identifier from registration
///   - `auth_token` - Bearer token for authentication
///
/// **Returns:** `Ok(Stream)` on success, `Error(String)` on failure
pub fn listen_v2(
  channel: Channel,
  worker_id: String,
  auth_token: String,
) -> Result(Stream, String) {
  let Channel(ch) = channel

  // Set up metadata with authentication
  let metadata = [#("authorization", "Bearer " <> auth_token)]

  // Create stream options for ListenV2
  let stream_opts =
    grpcbox.StreamOptions(
      channel: ch,
      service: "hatchet.dispatcher.Dispatcher",
      rpc: "ListenV2",
      metadata: metadata,
    )

  // Start the bidirectional stream
  case grpcbox.start_bidirectional_stream(stream_opts) {
    Ok(#(stream, _stream_ref)) -> {
      // Send the initial WorkerListenRequest
      let listen_request = protobuf.WorkerListenRequest(worker_id: worker_id)
      case protobuf.encode_worker_listen_request(listen_request) {
        Ok(encoded) -> {
          let data = protobuf.protobuf_message_to_bits(encoded)
          case grpcbox.stream_send(stream, data) {
            Ok(_) -> Ok(Stream(stream))
            Error(e) -> Error(error_to_string(e))
          }
        }
        Error(e) ->
          Error("Failed to encode listen request: " <> pb_error_message(e))
      }
    }
    Error(e) -> Error(error_to_string(e))
  }
}

fn pb_error_message(err: protobuf.ProtobufError) -> String {
  case err {
    protobuf.ProtobufEncodeError(msg) -> msg
    protobuf.ProtobufDecodeError(msg) -> msg
  }
}

pub fn send_step_event(
  stream: Stream,
  event_data: protobuf.ProtobufMessage,
) -> Result(Nil, String) {
  let Stream(s) = stream
  let data = protobuf.protobuf_message_to_bits(event_data)
  case grpcbox.stream_send(s, data) {
    Ok(_) -> Ok(Nil)
    Error(e) -> Error(error_to_string(e))
  }
}

pub fn heartbeat(
  stream: Stream,
  heartbeat_data: protobuf.ProtobufMessage,
) -> Result(Nil, String) {
  let Stream(s) = stream
  let data = protobuf.protobuf_message_to_bits(heartbeat_data)
  case grpcbox.stream_send(s, data) {
    Ok(_) -> Ok(Nil)
    Error(e) -> Error(error_to_string(e))
  }
}

pub fn stream_recv(stream: Stream, timeout_ms: Int) -> Result(BitArray, String) {
  let Stream(s) = stream
  case grpcbox.stream_recv(s, timeout_ms) {
    Ok(data) -> Ok(data)
    Error(e) -> Error(error_to_string(e))
  }
}

/// Receive and decode an AssignedAction from the stream
pub fn recv_assigned_action(
  stream: Stream,
  timeout_ms: Int,
) -> Result(protobuf.AssignedAction, String) {
  case stream_recv(stream, timeout_ms) {
    Ok(data) -> {
      let msg = protobuf.protobuf_message_from_bits(data)
      case protobuf.decode_assigned_action(msg) {
        Ok(action) -> Ok(action)
        Error(e) -> Error("Decode error: " <> pb_error_message(e))
      }
    }
    Error(e) -> Error(e)
  }
}

/// Send a step action event to the dispatcher via unary RPC
pub fn send_step_action_event(
  channel: Channel,
  event: protobuf.StepActionEvent,
  auth_token: String,
) -> Result(protobuf.ActionEventResponse, String) {
  let Channel(ch) = channel

  case protobuf.encode_step_action_event(event) {
    Ok(encoded) -> {
      let data = protobuf.protobuf_message_to_bits(encoded)
      let rpc_opts =
        grpcbox.RpcOptions(timeout_ms: 10_000, metadata: [
          #("authorization", "Bearer " <> auth_token),
        ])

      case
        grpcbox.unary_call(
          ch,
          "hatchet.dispatcher.Dispatcher",
          "SendStepActionEvent",
          data,
          rpc_opts,
        )
      {
        Ok(resp_data) -> {
          let msg = protobuf.protobuf_message_from_bits(resp_data)
          case protobuf.decode_action_event_response(msg) {
            Ok(resp) -> Ok(resp)
            Error(e) -> Error("Decode error: " <> pb_error_message(e))
          }
        }
        Error(e) -> Error(error_to_string(e))
      }
    }
    Error(e) -> Error("Encode error: " <> pb_error_message(e))
  }
}

/// Send a heartbeat via unary RPC
pub fn send_heartbeat(
  channel: Channel,
  worker_id: String,
  auth_token: String,
) -> Result(Nil, String) {
  let Channel(ch) = channel

  // Get current timestamp in milliseconds
  let timestamp = current_time_ms()
  let heartbeat_req =
    protobuf.HeartbeatRequest(worker_id: worker_id, heartbeat_at: timestamp)

  case protobuf.encode_heartbeat_request(heartbeat_req) {
    Ok(encoded) -> {
      let data = protobuf.protobuf_message_to_bits(encoded)
      let rpc_opts =
        grpcbox.RpcOptions(timeout_ms: 5000, metadata: [
          #("authorization", "Bearer " <> auth_token),
        ])

      case
        grpcbox.unary_call(
          ch,
          "hatchet.dispatcher.Dispatcher",
          "Heartbeat",
          data,
          rpc_opts,
        )
      {
        Ok(_) -> Ok(Nil)
        Error(e) -> Error(error_to_string(e))
      }
    }
    Error(e) -> Error("Encode error: " <> pb_error_message(e))
  }
}

fn current_time_ms() -> Int {
  do_current_time_ms()
}

@external(erlang, "hatchet_time_ffi", "system_time_ms")
fn do_current_time_ms() -> Int

pub fn close(channel: Channel) -> Nil {
  let Channel(ch) = channel
  grpcbox.close_channel(ch)
}

pub fn close_stream(stream: Stream) -> Nil {
  let Stream(s) = stream
  grpcbox.close_stream(s)
}

/// Internal Types
pub type RegisterResponse {
  RegisterResponse(worker_id: String)
}

/// Helper Functions
pub fn event_type_to_string(event: StepEventType) -> String {
  case event {
    Started -> "EVENT_TYPE_STARTED"
    Completed -> "EVENT_TYPE_COMPLETED"
    Failed -> "EVENT_TYPE_FAILED"
    Cancelled -> "EVENT_TYPE_CANCELLED"
    Timeout -> "EVENT_TYPE_TIMEOUT"
  }
}

/// Test Helper Functions
pub fn mock_channel(_pid: Int) -> Channel {
  Channel(dummy_channel())
}

@external(erlang, "grpcbox_helper", "dummy_channel")
fn dummy_channel() -> grpcbox.Channel

pub fn mock_stream(_pid: Int) -> Stream {
  Stream(dummy_stream())
}

@external(erlang, "grpcbox_helper", "dummy_stream")
fn dummy_stream() -> grpcbox.Stream

pub fn get_channel_pid(channel: Channel) -> Int {
  let Channel(_) = channel
  0
}

pub fn get_stream_pid(stream: Stream) -> Int {
  let Stream(_) = stream
  0
}
