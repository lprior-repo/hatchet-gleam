////!
////
//// gRPC Client Abstraction Tests
////
//// Tests for the GrpcClient abstraction layer that enables dependency
//// injection for testing and production use.

import gleam/dict
import gleam/option
import gleeunit
import gleeunit/should
import hatchet/internal/ffi/protobuf
import hatchet/internal/grpc
import hatchet/internal/grpc_client
import hatchet/internal/tls

pub fn main() {
  gleeunit.main()
}

// ============================================================================
// PRODUCTION CLIENT TESTS
// ============================================================================

pub fn real_grpc_client_creates_client_test() {
  // CONTRACT: real_grpc_client() creates a client with real gRPC functions
  // GIVEN: No parameters
  // WHEN: real_grpc_client() is called
  // THEN: A GrpcClient with production functions is returned

  let client = grpc_client.real_grpc_client()

  // Verify the client can be called (will fail since no server running)
  let result = client.connect("localhost", 7077, tls.Insecure, 1000)

  case result {
    Ok(_) -> should.fail()
    // Unexpected - no server running
    Error(msg) -> {
      // Expected - connection should fail without server
      should.not_equal("", msg)
    }
  }
}

// ============================================================================
// TEST DOUBLE CLIENT TESTS
// ============================================================================

pub fn test_grpc_client_returns_errors_test() {
  // CONTRACT: test_grpc_client() returns errors for unimplemented operations
  // GIVEN: A test_grpc_client()
  // WHEN: Any function is called
  // THEN: Error with descriptive message is returned

  let client = grpc_client.test_grpc_client()

  let result = client.connect("localhost", 7077, tls.Insecure, 5000)

  case result {
    Ok(_) -> should.fail()
    Error(msg) -> {
      msg
      |> should.equal("test_grpc_client: connect not implemented")
    }
  }
}

pub fn test_grpc_client_allows_overriding_functions_test() {
  // CONTRACT: test_grpc_client() functions can be overridden for testing
  // GIVEN: A test_grpc_client() with overridden connect function
  // WHEN: connect() is called
  // THEN: The custom function is used

  let client =
    grpc_client.GrpcClient(
      ..grpc_client.test_grpc_client(),
      connect: fn(_host, _port, _tls, _timeout) { Ok(grpc.mock_channel(42)) },
    )

  let result = client.connect("test-host", 8080, tls.Insecure, 3000)

  case result {
    Ok(_channel) -> {
      // Success - custom function was called
      should.be_true(True)
    }
    Error(_) -> should.fail()
  }
}

pub fn test_grpc_client_register_worker_not_implemented_test() {
  // CONTRACT: test_grpc_client() register_worker returns error by default
  let client = grpc_client.test_grpc_client()
  let channel = grpc.mock_channel(123)

  // Create a simple worker registration request
  let req =
    protobuf.WorkerRegisterRequest(
      worker_name: "test-worker",
      actions: [],
      services: [],
      max_runs: option.None,
      labels: dict.new(),
      webhook_id: option.None,
      runtime_info: option.None,
    )

  let assert Ok(pb_msg) = protobuf.encode_worker_register_request(req)

  let result = client.register_worker(channel, pb_msg, "test-token")

  case result {
    Ok(_) -> should.fail()
    Error(msg) -> {
      msg
      |> should.equal("test_grpc_client: register_worker not implemented")
    }
  }
}

pub fn test_grpc_client_listen_v2_not_implemented_test() {
  // CONTRACT: test_grpc_client() listen_v2 returns error by default
  let client = grpc_client.test_grpc_client()
  let channel = grpc.mock_channel(123)

  let result = client.listen_v2(channel, "worker-123", "token")

  case result {
    Ok(_) -> should.fail()
    Error(msg) -> {
      msg
      |> should.equal("test_grpc_client: listen_v2 not implemented")
    }
  }
}

pub fn test_grpc_client_send_heartbeat_not_implemented_test() {
  // CONTRACT: test_grpc_client() send_heartbeat returns error by default
  let client = grpc_client.test_grpc_client()
  let channel = grpc.mock_channel(123)

  let result = client.send_heartbeat(channel, "worker-123", "token")

  case result {
    Ok(_) -> should.fail()
    Error(msg) -> {
      msg
      |> should.equal("test_grpc_client: send_heartbeat not implemented")
    }
  }
}

pub fn test_grpc_client_close_succeeds_test() {
  // CONTRACT: test_grpc_client() close does not error
  let client = grpc_client.test_grpc_client()
  let channel = grpc.mock_channel(123)

  // Should not raise errors
  client.close(channel)
  should.be_true(True)
}

pub fn test_grpc_client_close_stream_succeeds_test() {
  // CONTRACT: test_grpc_client() close_stream does not error
  let client = grpc_client.test_grpc_client()
  let stream = grpc.mock_stream(123)

  // Should not raise errors
  client.close_stream(stream)
  should.be_true(True)
}

// ============================================================================
// SUCCESS CLIENT TESTS
// ============================================================================

pub fn success_grpc_client_connect_succeeds_test() {
  // CONTRACT: success_grpc_client() connect returns Ok with mock channel
  // GIVEN: A success_grpc_client()
  // WHEN: connect() is called
  // THEN: Ok(Channel) is returned

  let client = grpc_client.success_grpc_client()

  let result = client.connect("localhost", 7077, tls.Insecure, 5000)

  case result {
    Ok(_channel) -> should.be_true(True)
    Error(_) -> should.fail()
  }
}

pub fn success_grpc_client_register_worker_succeeds_test() {
  // CONTRACT: success_grpc_client() register_worker returns Ok with worker_id
  let client = grpc_client.success_grpc_client()
  let channel = grpc.mock_channel(123)

  let req =
    protobuf.WorkerRegisterRequest(
      worker_name: "test-worker",
      actions: ["action1"],
      services: [],
      max_runs: option.Some(10),
      labels: dict.new(),
      webhook_id: option.None,
      runtime_info: option.None,
    )

  let assert Ok(pb_msg) = protobuf.encode_worker_register_request(req)

  let result = client.register_worker(channel, pb_msg, "test-token")

  case result {
    Ok(resp) -> {
      resp.worker_id
      |> should.equal("test-worker-123")
    }
    Error(_) -> should.fail()
  }
}

pub fn success_grpc_client_listen_v2_succeeds_test() {
  // CONTRACT: success_grpc_client() listen_v2 returns Ok with stream
  let client = grpc_client.success_grpc_client()
  let channel = grpc.mock_channel(123)

  let result = client.listen_v2(channel, "worker-123", "token")

  case result {
    Ok(_stream) -> should.be_true(True)
    Error(_) -> should.fail()
  }
}

pub fn success_grpc_client_send_event_succeeds_test() {
  // CONTRACT: success_grpc_client() send_event returns Ok with response
  let client = grpc_client.success_grpc_client()
  let channel = grpc.mock_channel(123)

  let event =
    protobuf.StepActionEvent(
      worker_id: "worker-123",
      job_id: "job-456",
      job_run_id: "job-run-789",
      step_id: "step-abc",
      step_run_id: "step-run-123",
      action_id: "action-456",
      event_timestamp: 1_700_000_000_000,
      event_type: protobuf.StepEventTypeStarted,
      event_payload: "{}",
      retry_count: option.Some(0),
      should_not_retry: option.None,
    )

  let result = client.send_event(channel, event, "token")

  case result {
    Ok(resp) -> {
      resp.tenant_id
      |> should.equal("test-tenant")
      resp.worker_id
      |> should.equal("test-worker")
    }
    Error(_) -> should.fail()
  }
}

pub fn success_grpc_client_recv_assigned_action_succeeds_test() {
  // CONTRACT: success_grpc_client() recv_assigned_action returns Ok with action
  let client = grpc_client.success_grpc_client()
  let stream = grpc.mock_stream(123)

  let result = client.recv_assigned_action(stream, 5000)

  case result {
    Ok(action) -> {
      action.tenant_id
      |> should.equal("test-tenant")
      action.workflow_run_id
      |> should.equal("test-run-123")
      action.step_name
      |> should.equal("test_task")
    }
    Error(_) -> should.fail()
  }
}

pub fn success_grpc_client_send_heartbeat_succeeds_test() {
  // CONTRACT: success_grpc_client() send_heartbeat returns Ok
  let client = grpc_client.success_grpc_client()
  let channel = grpc.mock_channel(123)

  let result = client.send_heartbeat(channel, "worker-123", "token")

  case result {
    Ok(Nil) -> should.be_true(True)
    Error(_) -> should.fail()
  }
}

// ============================================================================
// FAILURE CLIENT TESTS
// ============================================================================

pub fn failure_grpc_client_connect_fails_test() {
  // CONTRACT: failure_grpc_client() connect returns Error
  let client = grpc_client.failure_grpc_client()

  let result = client.connect("localhost", 7077, tls.Insecure, 5000)

  case result {
    Ok(_) -> should.fail()
    Error(msg) -> {
      msg
      |> should.equal("Connection failed: simulated error")
    }
  }
}

pub fn failure_grpc_client_register_worker_fails_test() {
  // CONTRACT: failure_grpc_client() register_worker returns Error
  let client = grpc_client.failure_grpc_client()
  let channel = grpc.mock_channel(123)

  let req =
    protobuf.WorkerRegisterRequest(
      worker_name: "test-worker",
      actions: [],
      services: [],
      max_runs: option.None,
      labels: dict.new(),
      webhook_id: option.None,
      runtime_info: option.None,
    )

  let assert Ok(pb_msg) = protobuf.encode_worker_register_request(req)

  let result = client.register_worker(channel, pb_msg, "test-token")

  case result {
    Ok(_) -> should.fail()
    Error(msg) -> {
      msg
      |> should.equal("Worker registration failed: simulated error")
    }
  }
}

pub fn failure_grpc_client_listen_v2_fails_test() {
  // CONTRACT: failure_grpc_client() listen_v2 returns Error
  let client = grpc_client.failure_grpc_client()
  let channel = grpc.mock_channel(123)

  let result = client.listen_v2(channel, "worker-123", "token")

  case result {
    Ok(_) -> should.fail()
    Error(msg) -> {
      msg
      |> should.equal("Listen failed: simulated error")
    }
  }
}

pub fn failure_grpc_client_send_event_fails_test() {
  // CONTRACT: failure_grpc_client() send_event returns Error
  let client = grpc_client.failure_grpc_client()
  let channel = grpc.mock_channel(123)

  let event =
    protobuf.StepActionEvent(
      worker_id: "worker-123",
      job_id: "job-456",
      job_run_id: "job-run-789",
      step_id: "step-abc",
      step_run_id: "step-run-123",
      action_id: "action-456",
      event_timestamp: 1_700_000_000_000,
      event_type: protobuf.StepEventTypeFailed,
      event_payload: "{\"error\": \"test error\"}",
      retry_count: option.Some(1),
      should_not_retry: option.None,
    )

  let result = client.send_event(channel, event, "token")

  case result {
    Ok(_) -> should.fail()
    Error(msg) -> {
      msg
      |> should.equal("Send event failed: simulated error")
    }
  }
}

pub fn failure_grpc_client_recv_assigned_action_fails_test() {
  // CONTRACT: failure_grpc_client() recv_assigned_action returns Error
  let client = grpc_client.failure_grpc_client()
  let stream = grpc.mock_stream(123)

  let result = client.recv_assigned_action(stream, 5000)

  case result {
    Ok(_) -> should.fail()
    Error(msg) -> {
      msg
      |> should.equal("Receive action failed: simulated error")
    }
  }
}

pub fn failure_grpc_client_send_heartbeat_fails_test() {
  // CONTRACT: failure_grpc_client() send_heartbeat returns Error
  let client = grpc_client.failure_grpc_client()
  let channel = grpc.mock_channel(123)

  let result = client.send_heartbeat(channel, "worker-123", "token")

  case result {
    Ok(_) -> should.fail()
    Error(msg) -> {
      msg
      |> should.equal("Heartbeat failed: simulated error")
    }
  }
}

// ============================================================================
// INTEGRATION TESTS
// ============================================================================

pub fn custom_client_with_mixed_implementations_test() {
  // CONTRACT: Can create custom client mixing implementations
  // GIVEN: A custom client with some success and some failure functions
  // WHEN: Functions are called
  // THEN: Custom behavior is executed

  let client =
    grpc_client.GrpcClient(
      ..grpc_client.test_grpc_client(),
      // Connect succeeds
      connect: fn(_host, _port, _tls, _timeout) { Ok(grpc.mock_channel(999)) },
      // Register fails
      register_worker: fn(_channel, _request, _token) {
        Error("Custom error: registration blocked")
      },
    )

  // Connect should succeed
  let connect_result = client.connect("localhost", 7077, tls.Insecure, 5000)
  case connect_result {
    Ok(_) -> should.be_true(True)
    Error(_) -> should.fail()
  }

  // Register should fail with custom message
  let channel = grpc.mock_channel(123)
  let req =
    protobuf.WorkerRegisterRequest(
      worker_name: "test",
      actions: [],
      services: [],
      max_runs: option.None,
      labels: dict.new(),
      webhook_id: option.None,
      runtime_info: option.None,
    )
  let assert Ok(pb_msg) = protobuf.encode_worker_register_request(req)

  let register_result = client.register_worker(channel, pb_msg, "token")
  case register_result {
    Ok(_) -> should.fail()
    Error(msg) -> {
      msg
      |> should.equal("Custom error: registration blocked")
    }
  }
}
