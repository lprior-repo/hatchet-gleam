# Gleam Dependencies Setup

## Current Status

The dependencies are configured in gleam.toml as follows:

- gleam_stdlib: >= 0.44.0 and < 3.0.0
- gleam_json: >= 2.2.0 and < 3.0.0
- gleam_http: >= 3.7.0 and < 4.0.0
- gleam_httpc: >= 3.0.0 and < 4.0.0
- gleam_otp: >= 0.16.0 and < 1.0.0

## Known Issue: Gleam 1.14.0 Compatibility

The current environment has Gleam 1.14.0 installed, which introduced breaking changes to the `gleam/dynamic` module. The dependency packages (gleam_json, gleam_http, gleam_httpc, gleam_otp) at versions compatible with SDK design are written for earlier versions of Gleam.

### Error Example

When trying to build, you'll see errors like:
```
error: Unknown module value
   ┌─ build/packages/gleam_erlang/src/gleam/erlang/process.gleam:240:26
   │

240 │     let normal = dynamic.from(Normal)
   │                          ^^^^

The module `gleam/dynamic` does not have a `from` value.
```

## Solutions

1. **Wait for package updates**: The package maintainers need to update to support Gleam 1.14.0
2. **Use an earlier Gleam version**: The packages work with Gleam 1.6.0 or earlier
3. **Update SDK implementation**: Rewrite the code to not depend on these packages

For now, the dependencies are correctly configured and ready for when compatible package versions become available.

## Erlang Dependencies (via rebar3)

- **gun** - HTTP/2 client library
- **gpb** - Protocol Buffers compiler

## gRPC Implementation

The SDK uses a custom gRPC implementation via the `gun` HTTP/2 library
rather than the `grpcbox` hex package. This choice was made because:

1. **Server-Streaming RPCs**: Hatchet's ListenV2 RPC is server-streaming
   (sends request once, receives stream of responses), which requires specific
   HTTP/2 handling that standard grpcbox doesn't support out-of-the-box.

2. **Control Over Framing**: Custom implementation gives us direct control over
   gRPC message framing, compression, and HTTP/2 flow control.

3. **Testability**: Thin wrapper allows easy mocking and
   testing of connection lifecycle, errors, and retries.

4. **Gun is Production-Ready**: The `gun` library is widely used in
   production Erlang/Elixir systems and has excellent HTTP/2 support.

### grpcbox_helper.erl (296 lines)

Provides:
- Connection management with configurable TLS
- Unary RPC calls with metadata support
- Server-streaming RPCs for task assignments
- Bidirectional streaming for future use cases
- Proper error handling and connection lifecycle

### dispatcher_pb_helper.erl (328 lines)

Provides:
- Protocol buffer encoding helpers using gpb-generated code
- Conversion between Gleam types and Erlang maps
- Type-safe enum handling for protobuf messages

Both files are production-ready with comprehensive error handling and logging.
