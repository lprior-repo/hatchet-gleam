////!
/// gRPC Client Module
///
//! This module provides a Gleam-friendly interface to the Hatchet gRPC
//! dispatcher using Erlang FFI to grpcbox.

import gleam/option.{type Option, None, Some}
import hatchet/internal/ffi/grpcbox as grpcbox
import hatchet/internal/ffi/protobuf as protobuf
import hatchet/internal/tls.{type TLSConfig, Insecure, Mtls, Tls}

//// ========================================================================
/// Connection Types
//// ========================================================================

//// A gRPC channel to the Hatchet dispatcher.
pub opaque type Channel {
  Channel(grpcbox.Channel)
}

//// A bidirectional stream for receiving task assignments.
pub opaque type Stream {
  Stream(grpcbox.Stream)
}

//// ========================================================================
/// Step Event Types
//// ========================================================================

//// Types of step events that can be reported to the dispatcher.
pub type StepEventType {
  Started
  Completed
  Failed
  Cancelled
  Timeout
}

//// ========================================================================
/// Connection Management
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
pub fn connect(
  host: String,
  port: Int,
  tls_config: TLSConfig,
  timeout_ms: Int,
) -> Result(Channel, String) {
  let grpcbox_opts = convert_tls_config(tls_config)
  let conn_opts = grpcbox.ConnectionOptions(
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

//// Register a worker with the Hatchet dispatcher.
////
//// **Parameters:**
////   - `channel` - The gRPC channel
////   - `request` - The worker registration request
////
//// **Returns:** `Ok(RegisterResponse)` on success, `Error(String)` on failure
pub fn register_worker(
  channel: Channel,
  request: protobuf.ProtobufMessage,
) -> Result(RegisterResponse, String) {
  let Channel(ch) = channel
  let data = protobuf.protobuf_message_to_bits(request)
  let rpc_opts = grpcbox.RpcOptions(timeout_ms: 5000, metadata: [])
  case grpcbox.unary_call(ch, "hatchet.dispatcher.Dispatcher", "Register", data, rpc_opts) {
    Ok(resp_data) ->
      case protobuf.decode_worker_register_response(
        protobuf.protobuf_message_from_bits(resp_data),
      ) {
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

//// Start listening for task assignments via ListenV2.
////
//// **Parameters:**
////   - `channel` - The gRPC channel
////   - `worker_id` - The worker identifier from registration
////
//// **Returns:** `Ok(Stream)` on success, `Error(String)` on failure
pub fn listen_v2(
  _channel: Channel,
  _worker_id: String,
) -> Result(Stream, String) {
  // TODO: Implement using grpcbox.start_bidirectional_stream
  // This requires sending an initial WorkerListenRequest message
  Error("Not yet implemented")
}

//// Send a step event on the active stream.
////
//// **Parameters:**
////   - `stream` - The ListenV2 stream
////   - `event_data` - The encoded step action event
////
//// **Returns:** `Ok(Nil)` on success, `Error(String)` on failure
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

//// Send a heartbeat to keep the worker connection alive.
////
//// **Parameters:**
////   - `stream` - The ListenV2 stream
////   - `heartbeat_data` - The encoded heartbeat request
////
//// **Returns:** `Ok(Nil)` on success, `Error(String)` on failure
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

//// Receive a message from the stream.
////
//// **Parameters:**
////   - `stream` - The ListenV2 stream
////   - `timeout_ms` - Receive timeout in milliseconds
////
//// **Returns:** `Ok(BitArray)` on success, `Error(String)` on failure
pub fn stream_recv(stream: Stream, timeout_ms: Int) -> Result(BitArray, String) {
  let Stream(s) = stream
  case grpcbox.stream_recv(s, timeout_ms) {
    Ok(data) -> Ok(data)
    Error(e) -> Error(error_to_string(e))
  }
}

//// Close a gRPC channel.
////
//// **Parameters:**
////   - `channel` - The gRPC channel to close
pub fn close(channel: Channel) -> Nil {
  let Channel(ch) = channel
  grpcbox.close_channel(ch)
}

//// Close a bidirectional stream.
////
//// **Parameters:**
////   - `stream` - The stream to close
pub fn close_stream(stream: Stream) -> Nil {
  let Stream(s) = stream
  grpcbox.close_stream(s)
}

//// ========================================================================
/// Internal Types
//// ========================================================================

//// Response from worker registration.
pub type RegisterResponse {
  RegisterResponse(worker_id: String)
}

//// ========================================================================
/// Helper Functions
//// ========================================================================

//// Convert event type to string for debugging.
pub fn event_type_to_string(event: StepEventType) -> String {
  case event {
    Started -> "EVENT_TYPE_STARTED"
    Completed -> "EVENT_TYPE_COMPLETED"
    Failed -> "EVENT_TYPE_FAILED"
    Cancelled -> "EVENT_TYPE_CANCELLED"
    Timeout -> "EVENT_TYPE_TIMEOUT"
  }
}

//// ========================================================================
/// Test Helper Functions
//// ========================================================================

//// Create a mock channel for testing.
pub fn mock_channel(_pid: Int) -> Channel {
  Channel(dummy_channel())
}

@external(erlang, "grpcbox_helper", "dummy_channel")
fn dummy_channel() -> grpcbox.Channel

//// Create a mock stream for testing.
pub fn mock_stream(_pid: Int) -> Stream {
  Stream(dummy_stream())
}

@external(erlang, "grpcbox_helper", "dummy_stream")
fn dummy_stream() -> grpcbox.Stream

//// Get the internal pid from a Channel (for testing compatibility).
pub fn get_channel_pid(channel: Channel) -> Int {
  let Channel(_) = channel
  0
}

//// Get the internal pid from a Stream (for testing compatibility).
pub fn get_stream_pid(stream: Stream) -> Int {
  let Stream(_) = stream
  0
}
