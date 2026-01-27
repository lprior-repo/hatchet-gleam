//// Tests for the Hatchet SDK error types.

import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import hatchet/errors.{
  type HatchetError, AuthenticationFailed, ConfigError, ConnectionError,
  ConnectionFailed, ConnectionReset, ConnectionTimeout, DecodeError, EncodeError,
  EnvironmentError, EventSendFailed, GenericError, GrpcError, HandlerError,
  InputDecodeError, InvalidConfig, JsonError, MaxReconnectsExceeded,
  MaxRetriesExceeded, MissingConfig, NoHandlerFound, ProtocolError,
  TaskCancelled, TaskError, TaskTimeout, TlsError, UnexpectedResponse,
}

pub fn main() {
  gleeunit.main()
}

// ============================================================================
// Connection Error Tests
// ============================================================================

pub fn connection_failed_to_string_test() {
  let error = ConnectionError(ConnectionFailed("localhost", 7077, "refused"))
  let result = errors.to_string(error)
  result |> should.equal("Connection failed to localhost:7077: refused")
}

pub fn authentication_failed_to_string_test() {
  let error = ConnectionError(AuthenticationFailed("invalid token"))
  let result = errors.to_string(error)
  result |> should.equal("Authentication failed: invalid token")
}

pub fn connection_timeout_to_string_test() {
  let error = ConnectionError(ConnectionTimeout(5000))
  let result = errors.to_string(error)
  result |> should.equal("Connection timeout after 5000ms")
}

pub fn connection_reset_to_string_test() {
  let error = ConnectionError(ConnectionReset("peer closed"))
  let result = errors.to_string(error)
  result |> should.equal("Connection reset: peer closed")
}

pub fn tls_error_to_string_test() {
  let error = ConnectionError(TlsError("certificate expired"))
  let result = errors.to_string(error)
  result |> should.equal("TLS error: certificate expired")
}

pub fn max_reconnects_to_string_test() {
  let error = ConnectionError(MaxReconnectsExceeded(15))
  let result = errors.to_string(error)
  result |> should.equal("Max reconnection attempts (15) exceeded")
}

// ============================================================================
// Task Error Tests
// ============================================================================

pub fn handler_error_to_string_test() {
  let error = TaskError(HandlerError("my-task", "division by zero"))
  let result = errors.to_string(error)
  result |> should.equal("Task 'my-task' failed: division by zero")
}

pub fn task_timeout_to_string_test() {
  let error = TaskError(TaskTimeout("slow-task", 60_000))
  let result = errors.to_string(error)
  result |> should.equal("Task 'slow-task' timed out after 60000ms")
}

pub fn no_handler_found_to_string_test() {
  let error = TaskError(NoHandlerFound("unknown:action"))
  let result = errors.to_string(error)
  result |> should.equal("No handler found for action: unknown:action")
}

pub fn task_cancelled_to_string_test() {
  let error = TaskError(TaskCancelled("my-task", "workflow cancelled"))
  let result = errors.to_string(error)
  result |> should.equal("Task 'my-task' was cancelled: workflow cancelled")
}

pub fn max_retries_exceeded_to_string_test() {
  let error = TaskError(MaxRetriesExceeded("flaky-task", 3, "network error"))
  let result = errors.to_string(error)
  result
  |> should.equal("Task 'flaky-task' failed after 3 attempts: network error")
}

pub fn event_send_failed_to_string_test() {
  let error = TaskError(EventSendFailed("my-task", "COMPLETED", "timeout"))
  let result = errors.to_string(error)
  result
  |> should.equal("Failed to send COMPLETED event for task 'my-task': timeout")
}

pub fn input_decode_error_to_string_test() {
  let error = TaskError(InputDecodeError("my-task", "invalid JSON"))
  let result = errors.to_string(error)
  result
  |> should.equal("Failed to decode input for task 'my-task': invalid JSON")
}

// ============================================================================
// Config Error Tests
// ============================================================================

pub fn missing_config_to_string_test() {
  let error = ConfigError(MissingConfig("HATCHET_TOKEN"))
  let result = errors.to_string(error)
  result |> should.equal("Missing required configuration: HATCHET_TOKEN")
}

pub fn invalid_config_to_string_test() {
  let error = ConfigError(InvalidConfig("port", "abc", "must be integer"))
  let result = errors.to_string(error)
  result
  |> should.equal("Invalid configuration for 'port' = 'abc': must be integer")
}

pub fn environment_error_to_string_test() {
  let error = ConfigError(EnvironmentError("HATCHET_HOST", "not set"))
  let result = errors.to_string(error)
  result |> should.equal("Environment variable error for HATCHET_HOST: not set")
}

// ============================================================================
// Protocol Error Tests
// ============================================================================

pub fn encode_error_to_string_test() {
  let error =
    ProtocolError(EncodeError("WorkerRegisterRequest", "missing field"))
  let result = errors.to_string(error)
  result
  |> should.equal("Failed to encode WorkerRegisterRequest: missing field")
}

pub fn decode_error_to_string_test() {
  let error = ProtocolError(DecodeError("AssignedAction", "invalid format"))
  let result = errors.to_string(error)
  result |> should.equal("Failed to decode AssignedAction: invalid format")
}

pub fn json_error_to_string_test() {
  let error = ProtocolError(JsonError("parse", "unexpected token"))
  let result = errors.to_string(error)
  result |> should.equal("JSON parse error: unexpected token")
}

pub fn grpc_error_with_code_to_string_test() {
  let error =
    ProtocolError(GrpcError("RegisterWorker", Some(14), "unavailable"))
  let result = errors.to_string(error)
  result |> should.equal("gRPC error in RegisterWorker (code 14): unavailable")
}

pub fn grpc_error_without_code_to_string_test() {
  let error = ProtocolError(GrpcError("SendEvent", None, "stream closed"))
  let result = errors.to_string(error)
  result |> should.equal("gRPC error in SendEvent: stream closed")
}

pub fn unexpected_response_to_string_test() {
  let error =
    ProtocolError(UnexpectedResponse("WorkerRegisterResponse", "error"))
  let result = errors.to_string(error)
  result
  |> should.equal(
    "Unexpected response: expected WorkerRegisterResponse, got error",
  )
}

// ============================================================================
// Generic Error Tests
// ============================================================================

pub fn generic_error_to_string_test() {
  let error = GenericError("Something went wrong")
  let result = errors.to_string(error)
  result |> should.equal("Something went wrong")
}

// ============================================================================
// Retryability Tests
// ============================================================================

pub fn connection_failed_is_retryable_test() {
  let error = ConnectionError(ConnectionFailed("localhost", 7077, "refused"))
  errors.is_retryable(error) |> should.equal(True)
}

pub fn connection_timeout_is_retryable_test() {
  let error = ConnectionError(ConnectionTimeout(5000))
  errors.is_retryable(error) |> should.equal(True)
}

pub fn auth_failed_not_retryable_test() {
  let error = ConnectionError(AuthenticationFailed("invalid"))
  errors.is_retryable(error) |> should.equal(False)
}

pub fn tls_error_not_retryable_test() {
  let error = ConnectionError(TlsError("cert expired"))
  errors.is_retryable(error) |> should.equal(False)
}

pub fn handler_error_is_retryable_test() {
  let error = TaskError(HandlerError("task", "transient failure"))
  errors.is_retryable(error) |> should.equal(True)
}

pub fn task_timeout_is_retryable_test() {
  let error = TaskError(TaskTimeout("task", 60_000))
  errors.is_retryable(error) |> should.equal(True)
}

pub fn no_handler_not_retryable_test() {
  let error = TaskError(NoHandlerFound("unknown"))
  errors.is_retryable(error) |> should.equal(False)
}

pub fn max_retries_not_retryable_test() {
  let error = TaskError(MaxRetriesExceeded("task", 3, "error"))
  errors.is_retryable(error) |> should.equal(False)
}

pub fn config_error_not_retryable_test() {
  let error = ConfigError(MissingConfig("key"))
  errors.is_retryable(error) |> should.equal(False)
}

pub fn encode_error_not_retryable_test() {
  let error = ProtocolError(EncodeError("msg", "reason"))
  errors.is_retryable(error) |> should.equal(False)
}

pub fn grpc_error_is_retryable_test() {
  let error = ProtocolError(GrpcError("method", None, "reason"))
  errors.is_retryable(error) |> should.equal(True)
}

pub fn generic_error_is_retryable_test() {
  let error = GenericError("unknown")
  errors.is_retryable(error) |> should.equal(True)
}

// ============================================================================
// Error Classification Tests
// ============================================================================

pub fn is_connection_error_test() {
  let conn_error = ConnectionError(ConnectionFailed("host", 1234, "reason"))
  let task_error = TaskError(HandlerError("task", "error"))

  errors.is_connection_error(conn_error) |> should.equal(True)
  errors.is_connection_error(task_error) |> should.equal(False)
}

pub fn is_task_error_test() {
  let conn_error = ConnectionError(ConnectionFailed("host", 1234, "reason"))
  let task_error = TaskError(HandlerError("task", "error"))

  errors.is_task_error(task_error) |> should.equal(True)
  errors.is_task_error(conn_error) |> should.equal(False)
}
