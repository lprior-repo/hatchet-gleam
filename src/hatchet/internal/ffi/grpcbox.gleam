////!
/// grpcbox FFI Module for Hatchet gRPC Client
///
//! Erlang FFI bindings to the grpcbox library for gRPC operations.

import gleam/bit_array
import gleam/list
import gleam/option.{type Option, None, Some}

//// Errors
pub type GrpcError {
  GrpcConnectionError(String)
  GrpcRpcError(String)
  GrpcStreamError(String)
}

//// Opaque types wrapping Erlang pids and references
pub opaque type Channel
pub opaque type Stream
pub opaque type StreamRef

//// Connection options
pub type ConnectionOptions {
  ConnectionOptions(
    host: String,
    port: Int,
    tls_config: Option(TLSConfig),
    timeout_ms: Int,
  )
}

pub type TLSConfig {
  TLSConfig(
    ca_file: Option(String),
    cert_file: Option(String),
    key_file: Option(String),
    verify: Option(Bool),
  )
}

//// RPC options
pub type RpcOptions {
  RpcOptions(
    timeout_ms: Int,
    metadata: List(#(String, String)),
  )
}

//// Stream options
pub type StreamOptions {
  StreamOptions(
    channel: Channel,
    service: String,
    rpc: String,
    metadata: List(#(String, String)),
  )
}

//// ============================================================================
/// Connection Management
//// ============================================================================

//// Connect to a gRPC server.
////
//// Uses grpcbox:connect_uri/2 with a generated URI from host and port.
pub fn connect(opts: ConnectionOptions) -> Result(Channel, GrpcError) {
  let uri = build_uri(opts.host, opts.port)
  case grpcbox_connect(uri, opts.timeout_ms, opts.tls_config) {
    Ok(ch) -> Ok(ch)
    Error(e) -> Error(GrpcConnectionError(e))
  }
}

@external(erlang, "grpcbox_helper", "connect")
fn grpcbox_connect(uri: String, timeout_ms: Int, tls: Option(TLSConfig)) -> Result(
  Channel,
  String,
)

fn build_uri(host: String, port: Int) -> String {
  "http://" <> host <> ":" <> int_to_string(port)
}

fn int_to_string(i: Int) -> String {
  // Use Erlang FFI for int to string conversion
  erlang_int_to_string(i)
}

@external(erlang, "erlang", "integer_to_binary")
fn erlang_int_to_string(i: Int) -> String

//// ============================================================================
/// Unary RPC Calls
//// ============================================================================

//// Make a unary RPC call.
////
//// Uses grpcbox:unary/3 for single request/response operations.
pub fn unary_call(
  channel: Channel,
  service: String,
  rpc: String,
  request_data: BitArray,
  opts: RpcOptions,
) -> Result(BitArray, GrpcError) {
  case grpcbox_unary(channel, service, rpc, request_data, opts) {
    Ok(resp) -> Ok(resp)
    Error(e) -> Error(GrpcRpcError(e))
  }
}

@external(erlang, "grpcbox_helper", "unary")
fn grpcbox_unary(
  channel: Channel,
  service: String,
  rpc: String,
  request: BitArray,
  opts: RpcOptions,
) -> Result(BitArray, String)

//// ============================================================================
/// Bidirectional Streaming
//// ============================================================================

//// Start a bidirectional gRPC stream.
////
//// Uses grpcbox:start_stream/3 for bidirectional RPCs like ListenV2.
pub fn start_bidirectional_stream(
  opts: StreamOptions,
) -> Result(#(Stream, StreamRef), GrpcError) {
  case grpcbox_start_stream(opts.channel, opts.service, opts.rpc, opts.metadata) {
    Ok(tuple) -> Ok(tuple)
    Error(e) -> Error(GrpcStreamError(e))
  }
}

@external(erlang, "grpcbox_helper", "start_stream")
fn grpcbox_start_stream(
  channel: Channel,
  service: String,
  rpc: String,
  metadata: List(#(String, String)),
) -> Result(#(Stream, StreamRef), String)

//// Send data on a bidirectional stream.
pub fn stream_send(stream: Stream, data: BitArray) -> Result(Nil, GrpcError) {
  case grpcbox_send(stream, data) {
    Ok(_) -> Ok(Nil)
    Error(e) -> Error(GrpcStreamError(e))
  }
}

@external(erlang, "grpcbox_helper", "send")
fn grpcbox_send(stream: Stream, data: BitArray) -> Result(Nil, String)

//// Receive data from a bidirectional stream.
pub fn stream_recv(stream: Stream, timeout_ms: Int) -> Result(
  BitArray,
  GrpcError,
) {
  case grpcbox_recv(stream, timeout_ms) {
    Ok(data) -> Ok(data)
    Error(e) -> Error(GrpcStreamError(e))
  }
}

@external(erlang, "grpcbox_helper", "recv")
fn grpcbox_recv(stream: Stream, timeout_ms: Int) -> Result(BitArray, String)

//// Close a bidirectional stream.
pub fn close_stream(stream: Stream) -> Nil {
  grpcbox_close_stream(stream)
}

@external(erlang, "grpcbox_helper", "close_stream")
fn grpcbox_close_stream(stream: Stream) -> Nil

//// ============================================================================
/// Channel Cleanup
//// ============================================================================

//// Close a gRPC channel connection.
pub fn close_channel(channel: Channel) -> Nil {
  grpcbox_close_channel(channel)
}

@external(erlang, "grpcbox_helper", "close_channel")
fn grpcbox_close_channel(channel: Channel) -> Nil

//// ============================================================================
/// Helper Functions for Testing
//// ============================================================================

//// Extract the inner Stream from a tuple
pub fn stream_from_tuple(tuple: #(Stream, a)) -> Stream {
  tuple.0
}
