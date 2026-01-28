-module(grpcbox_helper).
-export([connect/3, unary/5, start_stream/4, server_stream/5, send/2, recv/2, close_stream/1, close_channel/1,
         dummy_channel/0, dummy_stream/0]).

%% ==============================================================================
%% gRPC Client using gun (HTTP/2) and gpb (protobuf)
%% ==============================================================================

%% Connect to a gRPC server
connect(Uri, TimeoutMs, _TLSConfig) ->
    %% Parse URI to get host and port
    case parse_uri(Uri) of
        {ok, Host, Port, IsSecure} ->
            %% Try to use gun, handle if not available
            try
                %% Gun options for HTTP/2
                GunOpts = #{
                    protocols => [http2],
                    transport => if IsSecure -> tls; true -> tcp end,
                    retry => 0,
                    retry_timeout => TimeoutMs
                },

                HostStr = if is_binary(Host) -> binary_to_list(Host); true -> Host end,
                case gun:open(HostStr, Port, GunOpts) of
                    {ok, GunPid} ->
                        %% Wait for connection to be up
                        case gun:await_up(GunPid, TimeoutMs) of
                            {ok, http2} ->
                                {ok, {gun_channel, GunPid, Host, Port, IsSecure}};
                            {error, Reason} ->
                                gun:close(GunPid),
                                {error, format_error(Reason)};
                            {error, Reason, _} ->
                                gun:close(GunPid),
                                {error, format_error(Reason)}
                        end;
                    {error, Reason} ->
                        {error, format_error(Reason)}
                end
            catch
                error:undef ->
                    {error, <<"gun library not available in test runner">>};
                _:Err ->
                    {error, format_error(Err)}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%% Parse URI (e.g., "http://localhost:7077" or "localhost:7077")
parse_uri(Uri) when is_list(Uri) ->
    parse_uri(list_to_binary(Uri));
parse_uri(Uri) when is_binary(Uri) ->
    case Uri of
        <<"http://", Rest/binary>> ->
            parse_host_port(Rest, false);
        <<"https://", Rest/binary>> ->
            parse_host_port(Rest, true);
        _ ->
            %% No scheme, assume http
            parse_host_port(Uri, false)
    end.

parse_host_port(Address, IsSecure) ->
    case binary:split(Address, <<":">>) of
        [Host] ->
            {ok, Host, 50051, IsSecure};  %% Default gRPC port
        [Host, PortBin] ->
            case binary_to_integer(PortBin) of
                Port when is_integer(Port), Port > 0, Port < 65536 ->
                    {ok, Host, Port, IsSecure};
                _ ->
                    {error, <<"Invalid port">>}
            end
    end.

%% ==============================================================================
%% Unary RPC Calls
%% ==============================================================================

%% Make a unary RPC call
unary(dummy, _Service, _Rpc, _Request, _Opts) ->
    {error, <<"Mock channel">>};
unary(Channel, Service, Rpc, Request, Opts) ->
    {gun_channel, GunPid, _Host, _Port, _IsSecure} = Channel,
    %% Opts is a Gleam RpcOptions record: {timeout_ms, metadata}
    {Timeout, Metadata} = extract_rpc_opts(Opts),

    %% Build gRPC path: /package.service/method
    Path = "/" ++ binary_to_list(Service) ++ "/" ++ binary_to_list(Rpc),

    %% Build request body with gRPC frame prefix
    Body = grpc_frame_encode(Request),

    %% Build headers
    Headers = [
        {<<"content-type">>, <<"application/grpc+proto">>},
        {<<"grpc-accept-encoding">>, <<"identity,deflate,gzip">>},
        {<<"te">>, <<"trailers">>}
        | metadata_to_headers(Metadata)
    ],

    %% Make request
    StreamRef = gun:request(GunPid, <<"POST">>, list_to_binary(Path), Headers, Body),

    %% Await response
    case gun:await(GunPid, StreamRef, Timeout) of
        {response, nofin, 200, _RespHeaders} ->
            %% Normal response with body following
            case gun:await_body(GunPid, StreamRef, Timeout) of
                {ok, ResponseBody} ->
                    case grpc_frame_decode(ResponseBody) of
                        {ok, Data} -> {ok, Data};
                        {error, _} = E -> E
                    end;
                {ok, ResponseBody, _Trailers} ->
                    %% Response with trailers (gRPC typically sends trailers)
                    case grpc_frame_decode(ResponseBody) of
                        {ok, Data} -> {ok, Data};
                        {error, _} = E -> E
                    end;
                {error, Reason} ->
                    {error, format_error(Reason)}
            end;
        {response, nofin, Status, _RespHeaders} ->
            %% Non-200 with body
            gun:await_body(GunPid, StreamRef, Timeout),
            {error, iolist_to_binary([<<"HTTP status ">>, integer_to_binary(Status)])};
        {response, fin, _Status, RespHeaders} ->
            %% Trailers-only response (common for gRPC errors)
            GrpcStatus = proplists:get_value(<<"grpc-status">>, RespHeaders, <<"0">>),
            case GrpcStatus of
                <<"0">> -> {ok, <<>>};
                _ ->
                    GrpcMsg = proplists:get_value(<<"grpc-message">>, RespHeaders, <<"unknown gRPC error">>),
                    {error, iolist_to_binary([<<"gRPC error ">>, GrpcStatus, <<": ">>, GrpcMsg])}
            end;
        {error, Reason} ->
            {error, format_error(Reason)}
    end.

%% Encode data with gRPC frame prefix (1 byte compressed + 4 byte length)
grpc_frame_encode(Data) when is_binary(Data) ->
    Size = byte_size(Data),
    <<0:8, Size:32/big-unsigned, Data/binary>>.

%% Decode data with gRPC frame prefix
grpc_frame_decode(<<0:8, Size:32/big-unsigned, Data:Size/binary, Rest/binary>>) ->
    case Rest of
        <<>> -> {ok, Data};
        _ -> {error, <<"Trailing data">>}
    end;
grpc_frame_decode(_) ->
    {error, <<"Invalid gRPC frame">>}.

%% Convert metadata list to gun headers
%% Gleam strings are already binaries, so ensure we handle both
metadata_to_headers(Metadata) ->
    [{ensure_binary(K), ensure_binary(V)} || {K, V} <- Metadata].

ensure_binary(V) when is_binary(V) -> V;
ensure_binary(V) when is_list(V) -> list_to_binary(V);
ensure_binary(V) -> iolist_to_binary(io_lib:format("~p", [V])).

%% Extract options from Gleam RpcOptions record
%% Gleam records compile to Erlang tuples: {rpc_options, TimeoutMs, Metadata}
extract_rpc_opts({rpc_options, TimeoutMs, Metadata}) ->
    {TimeoutMs, Metadata};
extract_rpc_opts(_) ->
    {5000, []}.

%% ==============================================================================
%% Bidirectional Streaming
%% ==============================================================================

%% Start a bidirectional stream (headers only, body sent later via send/2)
start_stream(dummy, _Service, _Rpc, _Metadata) ->
    {error, <<"Mock channel">>};
start_stream(Channel, Service, Rpc, Metadata) ->
    {gun_channel, GunPid, _Host, _Port, _IsSecure} = Channel,

    %% Build gRPC path
    Path = "/" ++ binary_to_list(Service) ++ "/" ++ binary_to_list(Rpc),

    %% Build headers
    Headers = [
        {<<"content-type">>, <<"application/grpc+proto">>},
        {<<"grpc-accept-encoding">>, <<"identity,deflate,gzip">>},
        {<<"te">>, <<"trailers">>}
        | metadata_to_headers(Metadata)
    ],

    %% Open stream with headers only (no body yet) for bidirectional streaming
    StreamRef = gun:headers(GunPid, <<"POST">>, list_to_binary(Path), Headers),

    %% Return as 2-tuple matching Gleam's #(Stream, StreamRef)
    Stream = {gun_stream, GunPid, StreamRef},
    {ok, {Stream, StreamRef}}.

%% Start a server-streaming RPC (send request body, then read responses)
server_stream(dummy, _Service, _Rpc, _Request, _Metadata) ->
    {error, <<"Mock channel">>};
server_stream(Channel, Service, Rpc, Request, Metadata) ->
    {gun_channel, GunPid, _Host, _Port, _IsSecure} = Channel,

    %% Build gRPC path
    Path = "/" ++ binary_to_list(Service) ++ "/" ++ binary_to_list(Rpc),

    %% Build headers
    Headers = [
        {<<"content-type">>, <<"application/grpc+proto">>},
        {<<"grpc-accept-encoding">>, <<"identity,deflate,gzip">>},
        {<<"te">>, <<"trailers">>}
        | metadata_to_headers(Metadata)
    ],

    %% Send request with full body (server-streaming: one request, stream of responses)
    Body = grpc_frame_encode(Request),
    StreamRef = gun:request(GunPid, <<"POST">>, list_to_binary(Path), Headers, Body),

    Stream = {gun_stream, GunPid, StreamRef},
    {ok, {Stream, StreamRef}}.

%% Send data on a stream
send(Stream, Data) when is_tuple(Stream) ->
    {gun_stream, GunPid, StreamRef} = Stream,
    Body = grpc_frame_encode(Data),
    case gun:data(GunPid, StreamRef, nofin, Body) of
        {error, Reason} -> {error, format_error(Reason)};
        _ -> {ok, nil}
    end;
send(dummy, _Data) ->
    {error, <<"Mock stream">>}.

%% Receive data from a stream
recv(Stream, Timeout) when is_tuple(Stream) ->
    {gun_stream, GunPid, StreamRef} = Stream,
    case gun:await(GunPid, StreamRef, Timeout) of
        {data, nofin, Data} ->
            case grpc_frame_decode(Data) of
                {ok, Payload} -> {ok, Payload};
                {error, _} = E -> E
            end;
        {data, fin, Data} ->
            case grpc_frame_decode(Data) of
                {ok, Payload} -> {ok, Payload};
                {error, _} = E -> E
            end;
        {trailers, _Trailers} ->
            {error, <<"stream closed">>};
        {error, timeout} ->
            {error, <<"timeout">>};
        {error, Reason} ->
            {error, format_error(Reason)}
    end;
recv(dummy, _Timeout) ->
    {error, <<"timeout">>}.

%% ==============================================================================
%% Cleanup
%% ==============================================================================

%% Close a stream
close_stream(Stream) when is_tuple(Stream) ->
    {gun_stream, GunPid, StreamRef} = Stream,
    try gun:cancel(GunPid, StreamRef), nil catch _:_ -> nil end;
close_stream(dummy) ->
    nil.

%% Close a channel
close_channel(Channel) when is_tuple(Channel) ->
    {gun_channel, GunPid, _Host, _Port, _IsSecure} = Channel,
    try gun:close(GunPid), nil catch _:_ -> nil end;
close_channel(dummy) ->
    nil.

%% ==============================================================================
%% Dummy functions for mock/testing (kept for compatibility)
%% ==============================================================================

dummy_channel() -> dummy.
dummy_stream() -> dummy.

%% ==============================================================================
%% Error Formatting
%% ==============================================================================

format_error(Reason) when is_binary(Reason) ->
    Reason;
format_error(Reason) when is_atom(Reason) ->
    atom_to_binary(Reason, utf8);
format_error(Reason) when is_list(Reason) ->
    iolist_to_binary(Reason);
format_error(Reason) ->
    iolist_to_binary(io_lib:format("~p", [Reason])).
