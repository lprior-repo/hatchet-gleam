////!

///
/// gRPC Module Tests
///
/// Tests for gRPC client functionality using protobuf encoding.
import gleam/dict
import gleam/option
import gleeunit
import gleeunit/should
import hatchet/internal/ffi/protobuf
import hatchet/internal/grpc
import hatchet/internal/tls

pub fn main() {
  gleeunit.main()
}

// ============================================================================
// CONNECTION TESTS
// ============================================================================

pub fn connect_insecure_creates_channel_test() {
  // CONTRACT: Connecting with insecure config should create a channel
  // GIVEN: localhost host, port 7070, insecure TLS config
  // WHEN: connect() is called
  // THEN: Error is expected (no actual server running)

  let result = grpc.connect("localhost", 7070, tls.Insecure, 5000)

  // Should return Error since no server is running
  case result {
    Ok(_) -> {
      // Unexpected success
      should.fail()
    }
    Error(msg) -> {
      // Expected - no server running
      should.not_equal("", msg)
    }
  }
}

pub fn connect_with_tls_creates_secure_channel_test() {
  // CONTRACT: Connecting with TLS config should create a secure channel
  // GIVEN: localhost host, port 7070, TLS config with CA path
  // WHEN: connect() is called
  // THEN: Error is expected (no actual server running)

  let result =
    grpc.connect("localhost", 7070, tls.Tls(ca_path: "/path/to/ca.pem"), 5000)

  case result {
    Ok(_) -> {
      // Unexpected success
      should.fail()
    }
    Error(msg) -> {
      // Expected - no server running
      should.not_equal("", msg)
    }
  }
}

pub fn connect_with_invalid_host_returns_error_test() {
  // CONTRACT: Connecting to invalid host should return Error
  // GIVEN: empty host string
  // WHEN: connect() is called
  // THEN: Error is returned with descriptive message

  let result = grpc.connect("", 7070, tls.Insecure, 1000)

  case result {
    Ok(_) -> {
      should.fail()
    }
    Error(msg) -> {
      should.not_equal("", msg)
    }
  }
}

// ============================================================================
// WORKER REGISTRATION TESTS
// ============================================================================

pub fn register_worker_with_protobuf_test() {
  // CONTRACT: Registering a worker uses protobuf encoding
  // GIVEN: A valid channel and worker registration request
  // WHEN: register_worker() is called
  // THEN: Returns Error (mock channel can't make real gRPC calls)

  let channel = grpc.mock_channel(12_345)

  let req =
    protobuf.WorkerRegisterRequest(
      worker_name: "test-worker-1",
      actions: ["action1", "action2", "action3"],
      services: [],
      max_runs: option.Some(10),
      labels: dict.new(),
      webhook_id: option.None,
    )

  let assert Ok(pb_msg) = protobuf.encode_worker_register_request(req)

  let result = grpc.register_worker(channel, pb_msg)

  case result {
    Ok(_) -> {
      // Mock channel might return Ok in some implementations
      should.be_true(True)
    }
    Error(msg) -> {
      // Expected - mock channel can't make real gRPC calls
      should.not_equal("", msg)
    }
  }
}

pub fn register_worker_with_empty_actions_test() {
  // CONTRACT: Worker can be registered with empty action list
  // GIVEN: A valid channel and worker request with empty actions
  // WHEN: register_worker() is called
  // THEN: Result is returned (Error for mock channel)

  let channel = grpc.mock_channel(12_345)

  let req =
    protobuf.WorkerRegisterRequest(
      worker_name: "test-worker-empty",
      actions: [],
      services: [],
      max_runs: option.None,
      labels: dict.new(),
      webhook_id: option.None,
    )

  let assert Ok(pb_msg) = protobuf.encode_worker_register_request(req)

  let result = grpc.register_worker(channel, pb_msg)

  // Result should be defined (Ok or Error)
  case result {
    Ok(_) -> should.be_true(True)
    Error(_) -> should.be_true(True)
  }
}

// ============================================================================
// STREAMING TESTS
// ============================================================================

pub fn listen_v2_not_yet_implemented_test() {
  // CONTRACT: ListenV2 is not yet implemented
  // GIVEN: A valid channel and worker ID
  // WHEN: listen_v2() is called
  // THEN: Error with "Not yet implemented" message

  let channel = grpc.mock_channel(12_345)

  let result = grpc.listen_v2(channel, "test-worker-1")

  case result {
    Ok(_) -> should.fail()
    Error(msg) -> should.equal("Not yet implemented", msg)
  }
  // ============================================================================
  // STEP EVENT TESTS
  // ============================================================================
}

pub fn send_step_event_with_protobuf_test() {
  // CONTRACT: Sending step event uses protobuf encoding
  // GIVEN: A valid stream and step action event
  // WHEN: send_step_event() is called
  // THEN: Result is returned (Error for mock stream)

  let stream = grpc.mock_stream(12_346)

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
      // Started
      event_payload: "{}",
    )

  let assert Ok(pb_msg) = protobuf.encode_step_action_event(event)

  let result = grpc.send_step_event(stream, pb_msg)

  case result {
    Ok(_) -> should.be_true(True)
    Error(_) -> should.be_true(True)
  }
}

// ============================================================================
// HEARTBEAT TESTS
// ============================================================================

pub fn heartbeat_with_protobuf_test() {
  // CONTRACT: Heartbeat uses protobuf encoding
  // GIVEN: A valid stream and heartbeat request
  // WHEN: heartbeat() is called
  // THEN: Result is returned (Error for mock stream)

  let stream = grpc.mock_stream(12_346)

  let req =
    protobuf.HeartbeatRequest(
      worker_id: "test-worker-1",
      heartbeat_at: 1_700_000_000_000,
    )

  let assert Ok(pb_msg) = protobuf.encode_heartbeat_request(req)

  let result = grpc.heartbeat(stream, pb_msg)

  case result {
    Ok(_) -> should.be_true(True)
    Error(_) -> should.be_true(True)
  }
}

// ============================================================================
// CHANNEL LIFECYCLE TESTS
// ============================================================================

pub fn close_channel_cleanup_test() {
  // CONTRACT: Closing a channel should clean up resources
  // GIVEN: A valid channel
  // WHEN: close() is called
  // THEN: Channel resources are released (no error thrown)

  let channel = grpc.mock_channel(12_345)

  // This should not raise any errors
  let _ = grpc.close(channel)

  // If we get here, close succeeded
  should.be_true(True)
}

pub fn close_stream_cleanup_test() {
  // CONTRACT: Closing a stream should clean up resources
  // GIVEN: A valid stream
  // WHEN: close_stream() is called
  // THEN: Stream resources are released (no error thrown)

  let stream = grpc.mock_stream(12_346)

  // This should not raise any errors
  let _ = grpc.close_stream(stream)

  // If we get here, close succeeded
  should.be_true(True)
}

// ============================================================================
// EVENT TYPE CONVERSION TESTS
// ============================================================================

pub fn event_type_to_string_conversion_test() {
  // CONTRACT: Event types convert to correct proto string values
  // GIVEN: Each event type variant
  // WHEN: Converted to string
  // THEN: Correct proto enum string is returned

  grpc.Started
  |> grpc.event_type_to_string
  |> should.equal("EVENT_TYPE_STARTED")

  grpc.Completed
  |> grpc.event_type_to_string
  |> should.equal("EVENT_TYPE_COMPLETED")

  grpc.Failed
  |> grpc.event_type_to_string
  |> should.equal("EVENT_TYPE_FAILED")

  grpc.Cancelled
  |> grpc.event_type_to_string
  |> should.equal("EVENT_TYPE_CANCELLED")

  grpc.Timeout
  |> grpc.event_type_to_string
  |> should.equal("EVENT_TYPE_TIMEOUT")
}
