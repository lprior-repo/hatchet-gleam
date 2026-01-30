////!
//// gRPC Client Abstraction
////
//// This module provides an abstraction layer for gRPC client operations,
//// enabling dependency injection for testing and production use.
////
//// The abstraction allows for:
//// - Production gRPC operations using real network connections
//// - Test doubles for unit testing without network dependencies
//// - Easy mocking of gRPC behavior in tests

import gleam/option
import hatchet/internal/ffi/protobuf
import hatchet/internal/grpc
import hatchet/internal/tls.{type TLSConfig}

/// GrpcClient abstraction with function fields for dependency injection
pub type GrpcClient {
  GrpcClient(
    /// Connect to a gRPC server
    connect: fn(String, Int, TLSConfig, Int) -> Result(grpc.Channel, String),
    /// Send a step action event
    send_event: fn(grpc.Channel, protobuf.StepActionEvent, String) ->
      Result(protobuf.ActionEventResponse, String),
    /// Register a worker with the dispatcher
    register_worker: fn(grpc.Channel, protobuf.ProtobufMessage, String) ->
      Result(grpc.RegisterResponse, String),
    /// Start listening for task assignments
    listen_v2: fn(grpc.Channel, String, String) -> Result(grpc.Stream, String),
    /// Send a heartbeat to keep connection alive
    send_heartbeat: fn(grpc.Channel, String, String) -> Result(Nil, String),
    /// Receive an assigned action from the stream
    recv_assigned_action: fn(grpc.Stream, Int) ->
      Result(protobuf.AssignedAction, String),
    /// Close a gRPC channel
    close: fn(grpc.Channel) -> Nil,
    /// Close a gRPC stream
    close_stream: fn(grpc.Stream) -> Nil,
  )
}

/// Create a real GrpcClient for production use
///
/// This client uses actual gRPC network operations to communicate
/// with the Hatchet dispatcher.
///
/// ## Example
///
/// ```gleam
/// let client = real_grpc_client()
/// let result = client.connect("localhost", 7077, tls.Insecure, 30_000)
/// ```
pub fn real_grpc_client() -> GrpcClient {
  GrpcClient(
    connect: grpc.connect,
    send_event: grpc.send_step_action_event,
    register_worker: grpc.register_worker,
    listen_v2: grpc.listen_v2,
    send_heartbeat: grpc.send_heartbeat,
    recv_assigned_action: grpc.recv_assigned_action,
    close: grpc.close,
    close_stream: grpc.close_stream,
  )
}

/// Create a test GrpcClient for testing
///
/// This client provides a base implementation for test doubles.
/// Tests can override specific functions to simulate different scenarios.
///
/// ## Example
///
/// ```gleam
/// let test_client = GrpcClient(
///   ..test_grpc_client(),
///   connect: fn(_host, _port, _tls, _timeout) {
///     Ok(grpc.mock_channel(123))
///   },
/// )
/// ```
pub fn test_grpc_client() -> GrpcClient {
  GrpcClient(
    connect: fn(_host, _port, _tls, _timeout) {
      Error("test_grpc_client: connect not implemented")
    },
    send_event: fn(_channel, _event, _token) {
      Error("test_grpc_client: send_event not implemented")
    },
    register_worker: fn(_channel, _request, _token) {
      Error("test_grpc_client: register_worker not implemented")
    },
    listen_v2: fn(_channel, _worker_id, _token) {
      Error("test_grpc_client: listen_v2 not implemented")
    },
    send_heartbeat: fn(_channel, _worker_id, _token) {
      Error("test_grpc_client: send_heartbeat not implemented")
    },
    recv_assigned_action: fn(_stream, _timeout) {
      Error("test_grpc_client: recv_assigned_action not implemented")
    },
    close: fn(_channel) { Nil },
    close_stream: fn(_stream) { Nil },
  )
}

/// Create a test GrpcClient that succeeds with mock data
///
/// This client provides successful responses for all operations,
/// useful for testing happy path scenarios.
///
/// ## Example
///
/// ```gleam
/// let client = success_grpc_client()
/// let assert Ok(channel) = client.connect("localhost", 7077, tls.Insecure, 5000)
/// ```
pub fn success_grpc_client() -> GrpcClient {
  GrpcClient(
    connect: fn(_host, _port, _tls, _timeout) { Ok(grpc.mock_channel(12_345)) },
    send_event: fn(_channel, _event, _token) {
      Ok(protobuf.ActionEventResponse(
        tenant_id: "test-tenant",
        worker_id: "test-worker",
      ))
    },
    register_worker: fn(_channel, _request, _token) {
      Ok(grpc.RegisterResponse(worker_id: "test-worker-123"))
    },
    listen_v2: fn(_channel, _worker_id, _token) { Ok(grpc.mock_stream(12_346)) },
    send_heartbeat: fn(_channel, _worker_id, _token) { Ok(Nil) },
    recv_assigned_action: fn(_stream, _timeout) {
      Ok(protobuf.AssignedAction(
        tenant_id: "test-tenant",
        workflow_run_id: "test-run-123",
        get_group_key_run_id: "",
        job_id: "test-job",
        job_name: "test-job-name",
        job_run_id: "test-job-run",
        step_id: "test-step",
        step_run_id: "test-step-run-123",
        action_id: "test-action",
        action_type: protobuf.StartStepRun,
        action_payload: "{}",
        step_name: "test_task",
        retry_count: 0,
        additional_metadata: option.None,
        child_workflow_index: option.None,
        child_workflow_key: option.None,
        parent_workflow_run_id: option.None,
        priority: 0,
        workflow_id: option.Some("test-workflow"),
        workflow_version_id: option.None,
      ))
    },
    close: fn(_channel) { Nil },
    close_stream: fn(_stream) { Nil },
  )
}

/// Create a test GrpcClient that fails with error messages
///
/// This client provides error responses for all operations,
/// useful for testing error handling scenarios.
///
/// ## Example
///
/// ```gleam
/// let client = failure_grpc_client()
/// let assert Error(msg) = client.connect("localhost", 7077, tls.Insecure, 5000)
/// ```
pub fn failure_grpc_client() -> GrpcClient {
  GrpcClient(
    connect: fn(_host, _port, _tls, _timeout) {
      Error("Connection failed: simulated error")
    },
    send_event: fn(_channel, _event, _token) {
      Error("Send event failed: simulated error")
    },
    register_worker: fn(_channel, _request, _token) {
      Error("Worker registration failed: simulated error")
    },
    listen_v2: fn(_channel, _worker_id, _token) {
      Error("Listen failed: simulated error")
    },
    send_heartbeat: fn(_channel, _worker_id, _token) {
      Error("Heartbeat failed: simulated error")
    },
    recv_assigned_action: fn(_stream, _timeout) {
      Error("Receive action failed: simulated error")
    },
    close: fn(_channel) { Nil },
    close_stream: fn(_stream) { Nil },
  )
}
