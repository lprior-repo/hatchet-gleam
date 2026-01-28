//// Error types for the Hatchet SDK.
////
//// This module provides structured error types instead of plain strings,
//// enabling better error handling, recovery strategies, and debugging.

import gleam/option.{type Option, None, Some}

// ============================================================================
// SDK Error Type
// ============================================================================

/// Main error type for the Hatchet SDK.
pub type HatchetError {
  // Connection errors
  ConnectionError(ConnectionErrorKind)

  // Task execution errors
  TaskError(TaskErrorKind)

  // Configuration errors
  ConfigError(ConfigErrorKind)

  // Protocol errors
  ProtocolError(ProtocolErrorKind)

  // Generic error with message
  GenericError(message: String)
}

// ============================================================================
// Connection Errors
// ============================================================================

/// Errors related to connecting to the Hatchet server.
pub type ConnectionErrorKind {
  /// Failed to establish connection
  ConnectionFailed(host: String, port: Int, reason: String)

  /// Authentication failed (invalid token, expired, etc.)
  AuthenticationFailed(reason: String)

  /// Connection timed out
  ConnectionTimeout(timeout_ms: Int)

  /// Connection was reset or dropped
  ConnectionReset(reason: String)

  /// TLS/SSL error
  TlsError(reason: String)

  /// Max reconnection attempts exceeded
  MaxReconnectsExceeded(attempts: Int)
}

// ============================================================================
// Task Errors
// ============================================================================

/// Errors related to task execution.
pub type TaskErrorKind {
  /// Task handler returned an error
  HandlerError(step_name: String, error: String)

  /// Task execution timed out
  TaskTimeout(step_name: String, timeout_ms: Int)

  /// No handler registered for this action
  NoHandlerFound(action_name: String)

  /// Task was cancelled
  TaskCancelled(step_name: String, reason: String)

  /// Max retries exceeded
  MaxRetriesExceeded(step_name: String, attempts: Int, last_error: String)

  /// Failed to send task event to server
  EventSendFailed(step_name: String, event_type: String, reason: String)

  /// Failed to decode task input
  InputDecodeError(step_name: String, reason: String)
}

// ============================================================================
// Configuration Errors
// ============================================================================

/// Errors related to SDK configuration.
pub type ConfigErrorKind {
  /// Missing required configuration
  MissingConfig(key: String)

  /// Invalid configuration value
  InvalidConfig(key: String, value: String, reason: String)

  /// Environment variable error
  EnvironmentError(variable: String, reason: String)
}

// ============================================================================
// Protocol Errors
// ============================================================================

/// Errors related to the Hatchet wire protocol.
pub type ProtocolErrorKind {
  /// Failed to encode protobuf message
  EncodeError(message_type: String, reason: String)

  /// Failed to decode protobuf message
  DecodeError(message_type: String, reason: String)

  /// Failed to encode/decode JSON
  JsonError(operation: String, reason: String)

  /// gRPC error
  GrpcError(method: String, code: Option(Int), reason: String)

  /// Unexpected response from server
  UnexpectedResponse(expected: String, got: String)
}

// ============================================================================
// Error Conversion
// ============================================================================

/// Convert a HatchetError to a human-readable string.
pub fn to_string(error: HatchetError) -> String {
  case error {
    ConnectionError(kind) -> connection_error_to_string(kind)
    TaskError(kind) -> task_error_to_string(kind)
    ConfigError(kind) -> config_error_to_string(kind)
    ProtocolError(kind) -> protocol_error_to_string(kind)
    GenericError(msg) -> msg
  }
}

fn connection_error_to_string(kind: ConnectionErrorKind) -> String {
  case kind {
    ConnectionFailed(host, port, reason) ->
      "Connection failed to "
      <> host
      <> ":"
      <> int_to_string(port)
      <> ": "
      <> reason
    AuthenticationFailed(reason) -> "Authentication failed: " <> reason
    ConnectionTimeout(timeout) ->
      "Connection timeout after " <> int_to_string(timeout) <> "ms"
    ConnectionReset(reason) -> "Connection reset: " <> reason
    TlsError(reason) -> "TLS error: " <> reason
    MaxReconnectsExceeded(attempts) ->
      "Max reconnection attempts (" <> int_to_string(attempts) <> ") exceeded"
  }
}

fn task_error_to_string(kind: TaskErrorKind) -> String {
  case kind {
    HandlerError(step, error) -> "Task '" <> step <> "' failed: " <> error
    TaskTimeout(step, timeout) ->
      "Task '" <> step <> "' timed out after " <> int_to_string(timeout) <> "ms"
    NoHandlerFound(action) -> "No handler found for action: " <> action
    TaskCancelled(step, reason) ->
      "Task '" <> step <> "' was cancelled: " <> reason
    MaxRetriesExceeded(step, attempts, error) ->
      "Task '"
      <> step
      <> "' failed after "
      <> int_to_string(attempts)
      <> " attempts: "
      <> error
    EventSendFailed(step, event_type, reason) ->
      "Failed to send "
      <> event_type
      <> " event for task '"
      <> step
      <> "': "
      <> reason
    InputDecodeError(step, reason) ->
      "Failed to decode input for task '" <> step <> "': " <> reason
  }
}

fn config_error_to_string(kind: ConfigErrorKind) -> String {
  case kind {
    MissingConfig(key) -> "Missing required configuration: " <> key
    InvalidConfig(key, value, reason) ->
      "Invalid configuration for '"
      <> key
      <> "' = '"
      <> value
      <> "': "
      <> reason
    EnvironmentError(var, reason) ->
      "Environment variable error for " <> var <> ": " <> reason
  }
}

fn protocol_error_to_string(kind: ProtocolErrorKind) -> String {
  case kind {
    EncodeError(msg_type, reason) ->
      "Failed to encode " <> msg_type <> ": " <> reason
    DecodeError(msg_type, reason) ->
      "Failed to decode " <> msg_type <> ": " <> reason
    JsonError(op, reason) -> "JSON " <> op <> " error: " <> reason
    GrpcError(method, code, reason) -> {
      let code_str = case code {
        Some(c) -> " (code " <> int_to_string(c) <> ")"
        None -> ""
      }
      "gRPC error in " <> method <> code_str <> ": " <> reason
    }
    UnexpectedResponse(expected, got) ->
      "Unexpected response: expected " <> expected <> ", got " <> got
  }
}

// ============================================================================
// Error Classification (for retry decisions)
// ============================================================================

/// Determine if an error is retryable.
pub fn is_retryable(error: HatchetError) -> Bool {
  case error {
    ConnectionError(kind) ->
      case kind {
        // Network issues are usually transient
        ConnectionFailed(_, _, _) -> True
        ConnectionTimeout(_) -> True
        ConnectionReset(_) -> True
        // Auth failures should not be retried
        AuthenticationFailed(_) -> False
        TlsError(_) -> False
        MaxReconnectsExceeded(_) -> False
      }
    TaskError(kind) ->
      case kind {
        // Handler errors might be retryable (depends on business logic)
        HandlerError(_, _) -> True
        // Timeouts can be retried
        TaskTimeout(_, _) -> True
        // These should not be retried
        NoHandlerFound(_) -> False
        TaskCancelled(_, _) -> False
        MaxRetriesExceeded(_, _, _) -> False
        EventSendFailed(_, _, _) -> True
        InputDecodeError(_, _) -> False
      }
    ConfigError(_) -> False
    ProtocolError(kind) ->
      case kind {
        // Encoding issues won't fix on retry
        EncodeError(_, _) -> False
        DecodeError(_, _) -> False
        JsonError(_, _) -> False
        // gRPC errors might be transient
        GrpcError(_, _, _) -> True
        UnexpectedResponse(_, _) -> False
      }
    GenericError(_) -> True
  }
}

/// Determine if an error is a connection error.
pub fn is_connection_error(error: HatchetError) -> Bool {
  case error {
    ConnectionError(_) -> True
    _ -> False
  }
}

/// Determine if an error is a task error.
pub fn is_task_error(error: HatchetError) -> Bool {
  case error {
    TaskError(_) -> True
    _ -> False
  }
}

// ============================================================================
// Helper Functions
// ============================================================================

@external(erlang, "erlang", "integer_to_binary")
fn int_to_string(i: Int) -> String

// ============================================================================
// Error Wrappers (for DRY error handling)
// ============================================================================

/// Wrap an HTTP API error with consistent formatting.
pub fn api_http_error(status_code: Int, body: String) -> HatchetError {
  ProtocolError(JsonError(
    "API request",
    "status " <> int_to_string(status_code) <> ": " <> body,
  ))
}

/// Wrap a network error with consistent formatting.
pub fn network_error(details: String) -> HatchetError {
  ConnectionError(ConnectionFailed("unknown", 0, details))
}

/// Wrap a decode/parse error with consistent formatting.
pub fn decode_error(operation: String, details: String) -> HatchetError {
  ProtocolError(DecodeError(operation, details))
}

/// Wrap a gRPC error with consistent formatting.
pub fn grpc_error(method: String, details: String) -> HatchetError {
  ProtocolError(GrpcError(method, None, details))
}

/// Convert a HatchetError to a simple string for Result(String) returns.
pub fn to_simple_string(error: HatchetError) -> String {
  to_string(error)
}
