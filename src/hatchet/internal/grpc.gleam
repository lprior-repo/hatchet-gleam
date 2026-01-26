////!
/// gRPC Client Module
///
//! This module provides a Gleam-friendly interface to the Hatchet gRPC
//! dispatcher using Erlang FFI to grpcbox.
//!
//! ## Note
//!
//! This is a stub implementation. The complete gRPC integration with proper
//! protobuf encoding will be implemented once the basic worker infrastructure
//! is in place.
//!
//! ## Architecture
//!
//! The gRPC client communicates with the Hatchet dispatcher over long-lived
//! bidirectional streams. Workers:
//!
//! 1. Connect to the dispatcher
//! 2. Register their capabilities (actions they can handle)
//! 3. Listen for task assignments via ListenV2
//! 4. Send step events as tasks progress
//! 5. Send heartbeats to keep the connection alive

import gleam/option.{type Option, None, Some}
import hatchet/internal/tls.{type TLSConfig}

//// ========================================================================
/// Connection Types
//// ========================================================================

//// A gRPC channel to the Hatchet dispatcher.
////
//// This is an opaque wrapper around an Erlang process pid.
pub opaque type Channel {
  Channel(pid: ProcessPid)
}

//// A bidirectional stream for receiving task assignments.
////
//// This represents the ListenV2 stream connection.
pub opaque type Stream {
  Stream(pid: ProcessPid)
}

//// Process handle type (Erlang pid).
////
//// In Gleam on BEAM, pids are represented as opaque integers.
pub type ProcessPid =
  Int

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
  _port: Int,
  _tls_config: TLSConfig,
  _timeout_ms: Int,
) -> Result(Channel, String) {
  // Stub implementation - validates input and returns a mock channel
  // Real implementation will use grpcbox:connect/4

  // Validate host is not empty
  case host {
    "" -> Error("Invalid host: cannot be empty")
    _ -> Ok(Channel(pid: 12_345))
  }
}

//// Register a worker with the Hatchet dispatcher.
////
//// **Parameters:**
////   - `channel` - The gRPC channel
////   - `worker_id` - Unique identifier for this worker
////   - `actions` - List of action names this worker can handle
////
//// **Returns:** `Ok(RegisterResponse)` on success, `Error(String)` on failure
pub fn register_worker(
  _channel: Channel,
  worker_id: String,
  _actions: List(String),
) -> Result(RegisterResponse, String) {
  // Stub implementation
  Ok(RegisterResponse(worker_id: worker_id))
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
  // Stub implementation
  Ok(Stream(pid: 12_346))
}

//// Send a step event on the active stream.
////
//// **Parameters:**
////   - `stream` - The ListenV2 stream
////   - `step_run_id` - The step run identifier
////   - `event_type` - Type of event (Started, Completed, etc.)
////   - `output_data` - Optional JSON output data
////   - `error_message` - Optional error message for failures
////
//// **Returns:** `Ok(Nil)` on success, `Error(String)` on failure
pub fn send_step_event(
  _stream: Stream,
  _step_run_id: String,
  _event_type: StepEventType,
  _output_data: Option(String),
  _error_message: Option(String),
) -> Result(Nil, String) {
  // Stub implementation
  Ok(Nil)
}

//// Send a heartbeat to keep the worker connection alive.
////
//// **Parameters:**
////   - `stream` - The ListenV2 stream
////   - `worker_id` - The worker identifier
////
//// **Returns:** `Ok(Nil)` on success, `Error(String)` on failure
pub fn heartbeat(_stream: Stream, _worker_id: String) -> Result(Nil, String) {
  // Stub implementation
  Ok(Nil)
}

//// Close a gRPC channel.
////
//// **Parameters:**
////   - `channel` - The gRPC channel to close
pub fn close(_channel: Channel) -> Nil {
  Nil
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
////
//// **Parameters:**
////   - `pid` - Mock process pid
////
//// **Returns:** A mock Channel
pub fn mock_channel(pid: Int) -> Channel {
  Channel(pid: pid)
}

//// Create a mock stream for testing.
////
//// **Parameters:**
////   - `pid` - Mock process pid
////
//// **Returns:** A mock Stream
pub fn mock_stream(pid: Int) -> Stream {
  Stream(pid: pid)
}

//// Get the pid from a Channel (for testing).
////
//// **Parameters:**
////   - `channel` - The Channel
////
//// **Returns:** The process pid
pub fn get_channel_pid(channel: Channel) -> Int {
  channel.pid
}

//// Get the pid from a Stream (for testing).
////
//// **Parameters:**
////   - `stream` - The Stream
////
//// **Returns:** The process pid
pub fn get_stream_pid(stream: Stream) -> Int {
  stream.pid
}
