-module(grpcbox_helper).
-export([connect/3, unary/5, start_stream/4, send/2, recv/2, close_stream/1, close_channel/1,
         dummy_channel/0, dummy_stream/0]).

%% Connect to a gRPC server (mock for testing)
connect(Uri, _TimeoutMs, _TLSConfig) ->
    %% Mock implementation - return error since no server running
    %% In production, this would call grpcbox:connect_uri/2
    {error, iolist_to_binary(["Mock cannot connect to ", Uri])}.

%% Make a unary RPC call (mock for testing)
unary(_Channel, _Service, _Rpc, _Request, _Opts) ->
    %% Mock implementation - return error since no server
    {error, <<"Mock unary call not implemented">>}.

%% Start a bidirectional stream (mock for testing)
start_stream(_Channel, _Service, _Rpc, _Metadata) ->
    %% Mock implementation - return error since no server
    {error, <<"Mock stream not implemented">>}.

%% Send data on a stream (mock for testing)
send(_Stream, _Data) ->
    %% Mock implementation
    {error, <<"Mock send not implemented">>}.

%% Receive data from a stream (mock for testing)
recv(_Stream, _Timeout) ->
    %% Mock implementation - timeout
    {error, timeout}.

%% Close a stream (mock for testing)
close_stream(_Stream) ->
    %% Mock implementation
    ok.

%% Close a channel (mock for testing)
close_channel(_Channel) ->
    %% Mock implementation
    ok.

%% Dummy functions for mock/testing
dummy_channel() -> dummy.
dummy_stream() -> dummy.
