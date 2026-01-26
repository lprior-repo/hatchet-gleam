////!
/// gRPC Client Module
///
//! This module provides a Gleam-friendly interface to the Hatchet gRPC
//! dispatcher using Erlang FFI to grpcbox.
//!
//! ## Note
//!
//! This is a stub implementation for Phase 2. The complete gRPC integration
//! with proper protobuf encoding will be implemented once the basic
//! worker infrastructure is in place.
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

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
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

//// Connect to the Hatchet gRPC dispatcher (stub).
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
  // Stub implementation - returns a mock channel
  // Real implementation will use grpcbox:connect/4
  Ok(Channel(pid: 12345))
}

//// Register a worker with the Hatchet dispatcher (stub).
////
//// **Parameters:**
////   - `channel` - The gRPC channel
////   - `worker_id` - Unique identifier for this worker
////   - `actions` - List of action names this worker can handle
////
//// **Returns:** `Ok(RegisterResponse)` on success, `Error(String)` on failure
pub fn register_worker(
  channel: Channel,
  worker_id: String,
  actions: List(String),
) -> Result(RegisterResponse, String) {
  // Stub implementation
  Ok(RegisterResponse(worker_id: worker_id))
}

//// Start listening for task assignments via ListenV2 (stub).
////
//// **Parameters:**
////   - `channel` - The gRPC channel
////   - `worker_id` - The worker identifier from registration
////
//// **Returns:** `Ok(Stream)` on success, `Error(String)` on failure
pub fn listen_v2(
  channel: Channel,
  worker_id: String,
) -> Result(Stream, String) {
  // Stub implementation
  Ok(Stream(pid: 12346))
}

//// Send a step event on the active stream (stub).
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
  stream: Stream,
  step_run_id: String,
  event_type: StepEventType,
  output_data: Option(String),
  error_message: Option(String),
) -> Result(Nil, String) {
  // Stub implementation
  Ok(Nil)
}

//// Send a heartbeat to keep the worker connection alive (stub).
////
//// **Parameters:**
////   - `stream` - The ListenV2 stream
////   - `worker_id` - The worker identifier
////
//// **Returns:** `Ok(Nil)` on success, `Error(String)` on failure
pub fn heartbeat(stream: Stream, worker_id: String) -> Result(Nil, String) {
  // Stub implementation
  Ok(Nil)
}

//// Close a gRPC channel (stub).
////
//// **Parameters:**
////   - `channel` - The gRPC channel to close
pub fn close(channel: Channel) -> Nil {
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
fn event_type_to_string(event: StepEventType) -> String {
  case event {
    Started -> "EVENT_TYPE_STARTED"
    Completed -> "EVENT_TYPE_COMPLETED"
    Failed -> "EVENT_TYPE_FAILED"
    Cancelled -> "EVENT_TYPE_CANCELLED"
    Timeout -> "EVENT_TYPE_TIMEOUT"
  }
}
