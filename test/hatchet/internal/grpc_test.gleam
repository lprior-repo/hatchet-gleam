////!

/// gRPC Module Tests
///
/// RED phase - Failing tests for gRPC client functionality.
/// These tests describe the desired behavior before implementation.
import gleam/option
import gleeunit
import gleeunit/should
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
  // THEN: Ok(Channel) is returned with valid pid

  let result = grpc.connect("localhost", 7070, tls.Insecure, 5000)

  // Should return Ok with a Channel containing a valid process pid
  case result {
    Ok(channel) -> {
      // Channel should have a valid pid (positive integer)
      let pid = grpc.get_channel_pid(channel)
      should.be_true(pid > 0)
    }
    Error(_) -> {
      // This will fail in RED phase - no implementation yet
      should.fail()
    }
  }
}

pub fn connect_with_tls_creates_secure_channel_test() {
  // CONTRACT: Connecting with TLS config should create a secure channel
  // GIVEN: localhost host, port 7070, TLS config with CA path
  // WHEN: connect() is called
  // THEN: Ok(Channel) is returned

  let result =
    grpc.connect("localhost", 7070, tls.Tls(ca_path: "/path/to/ca.pem"), 5000)

  case result {
    Ok(_) -> should.be_true(True)
    Error(_) -> {
      // This will fail in RED phase
      should.fail()
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

pub fn register_worker_sends_correct_request_test() {
  // CONTRACT: Registering a worker sends the correct gRPC request
  // GIVEN: A valid channel, worker ID, and list of actions
  // WHEN: register_worker() is called
  // THEN: Ok(RegisterResponse) is returned with worker_id

  // Create a mock channel for testing
  let channel = grpc.mock_channel(12_345)

  let result =
    grpc.register_worker(channel, "test-worker-1", [
      "action1",
      "action2",
      "action3",
    ])

  case result {
    Ok(response) -> {
      response.worker_id
      |> should.equal("test-worker-1")
    }
    Error(_) -> {
      should.fail()
    }
  }
}

pub fn register_worker_with_empty_actions_test() {
  // CONTRACT: Worker can be registered with empty action list
  // GIVEN: A valid channel and empty actions list
  // WHEN: register_worker() is called
  // THEN: Ok(RegisterResponse) is still returned

  let channel = grpc.mock_channel(12_345)

  let result = grpc.register_worker(channel, "test-worker-empty", [])

  case result {
    Ok(_) -> should.be_true(True)
    Error(_) -> {
      should.fail()
    }
  }
}

// ============================================================================
// STREAMING TESTS
// ============================================================================

pub fn listen_v2_creates_stream_test() {
  // CONTRACT: ListenV2 creates a streaming connection
  // GIVEN: A valid channel and worker ID
  // WHEN: listen_v2() is called
  // THEN: Ok(Stream) is returned

  let channel = grpc.mock_channel(12_345)

  let result = grpc.listen_v2(channel, "test-worker-1")

  case result {
    Ok(stream) -> {
      let pid = grpc.get_stream_pid(stream)
      should.be_true(pid > 0)
    }
    Error(_) -> {
      should.fail()
    }
  }
}

// ============================================================================
// STEP EVENT TESTS
// ============================================================================

pub fn send_step_event_started_test() {
  // CONTRACT: Sending Started event encodes correctly
  // GIVEN: A valid stream and step run ID
  // WHEN: send_step_event() is called with Started
  // THEN: Ok(Nil) is returned

  let stream = grpc.mock_stream(12_346)

  let result =
    grpc.send_step_event(
      stream,
      "step-run-123",
      grpc.Started,
      option.None,
      option.None,
    )

  case result {
    Ok(_) -> should.be_true(True)
    Error(_) -> {
      should.fail()
    }
  }
}

pub fn send_step_event_completed_with_output_test() {
  // CONTRACT: Sending Completed event with output data
  // GIVEN: A valid stream and step run ID with output
  // WHEN: send_step_event() is called with Completed and output
  // THEN: Ok(Nil) is returned

  let stream = grpc.mock_stream(12_346)

  let result =
    grpc.send_step_event(
      stream,
      "step-run-123",
      grpc.Completed,
      option.Some("{\"result\": \"success\"}"),
      option.None,
    )

  case result {
    Ok(_) -> should.be_true(True)
    Error(_) -> {
      should.fail()
    }
  }
}

pub fn send_step_event_failed_with_error_test() {
  // CONTRACT: Sending Failed event with error message
  // GIVEN: A valid stream and step run ID
  // WHEN: send_step_event() is called with Failed and error message
  // THEN: Ok(Nil) is returned

  let stream = grpc.mock_stream(12_346)

  let result =
    grpc.send_step_event(
      stream,
      "step-run-123",
      grpc.Failed,
      option.None,
      option.Some("Task failed: timeout"),
    )

  case result {
    Ok(_) -> should.be_true(True)
    Error(_) -> {
      should.fail()
    }
  }
}

pub fn send_step_event_cancelled_test() {
  // CONTRACT: Sending Cancelled event
  // GIVEN: A valid stream and step run ID
  // WHEN: send_step_event() is called with Cancelled
  // THEN: Ok(Nil) is returned

  let stream = grpc.mock_stream(12_346)

  let result =
    grpc.send_step_event(
      stream,
      "step-run-123",
      grpc.Cancelled,
      option.None,
      option.None,
    )

  case result {
    Ok(_) -> should.be_true(True)
    Error(_) -> {
      should.fail()
    }
  }
}

pub fn send_step_event_timeout_test() {
  // CONTRACT: Sending Timeout event
  // GIVEN: A valid stream and step run ID
  // WHEN: send_step_event() is called with Timeout
  // THEN: Ok(Nil) is returned

  let stream = grpc.mock_stream(12_346)

  let result =
    grpc.send_step_event(
      stream,
      "step-run-123",
      grpc.Timeout,
      option.None,
      option.Some("Task timed out after 30s"),
    )

  case result {
    Ok(_) -> should.be_true(True)
    Error(_) -> {
      should.fail()
    }
  }
}

// ============================================================================
// HEARTBEAT TESTS
// ============================================================================

pub fn heartbeat_sends_timestamp_test() {
  // CONTRACT: Heartbeat sends current timestamp to server
  // GIVEN: A valid stream and worker ID
  // WHEN: heartbeat() is called
  // THEN: Ok(Nil) is returned

  let stream = grpc.mock_stream(12_346)

  let result = grpc.heartbeat(stream, "test-worker-1")

  case result {
    Ok(_) -> should.be_true(True)
    Error(_) -> {
      should.fail()
    }
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
