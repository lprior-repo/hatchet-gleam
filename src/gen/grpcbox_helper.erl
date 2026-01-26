-module(grpcbox_helper).
-export([connect/3, unary/5, start_stream/4, send/2, recv/2, close_stream/1, close_channel/1,
         dummy_channel/0, dummy_stream/0]).

%% Connect to a gRPC server
connect(Uri, TimeoutMs, TLSConfig) ->
    Opts = case TLSConfig of
        undefined -> [];
        {tls, Config} ->
            SslOpts = ssl_opts(Config),
            [{ssl_options, SslOpts}]
    end,
    case grpcbox:connect_uri(list_to_binary(Uri), Opts) of
        {ok, Ch, _} -> {ok, Ch};
        {error, Reason} -> {error, format_error(Reason)}
    end.

ssl_opts(undefined) -> [];
ssl_opts({tls, Config}) ->
    Opts0 = case maps:get(<<"ca_file">>, Config, undefined) of
        undefined -> [];
        CaFile -> [{cacertfile, binary_to_list(CaFile)}]
    end,
    Opts1 = case maps:get(<<"cert_file">>, Config, undefined) of
        undefined -> Opts0;
        CertFile -> [{certfile, binary_to_list(CertFile)} | Opts0]
    end,
    Opts2 = case maps:get(<<"key_file">>, Config, undefined) of
        undefined -> Opts1;
        KeyFile -> [{keyfile, binary_to_list(KeyFile)} | Opts1]
    end,
    case maps:get(<<"verify">>, Config, undefined) of
        undefined -> Opts2;
        true -> [{verify, verify_peer} | Opts2];
        false -> [{verify, verify_none} | Opts2]
    end.

%% Make a unary RPC call
unary(Channel, Service, Rpc, Request, Opts) ->
    ServiceAtom = binary_to_atom(Service, utf8),
    RpcAtom = binary_to_atom(Rpc, utf8),
    RpcOpts = rpc_opts(Opts),
    case grpcbox:unary(Channel, ServiceAtom, RpcAtom, Request, RpcOpts) of
        {ok, _Headers, Response, _Trailers} -> {ok, Response};
        {error, Reason} -> {error, format_error(Reason)}
    end.

rpc_opts(#{<<"timeout_ms">> := Timeout}) -> [{timeout, Timeout}];
rpc_opts(_) -> [].

%% Start a bidirectional stream
start_stream(Channel, Service, Rpc, Metadata) ->
    ServiceAtom = binary_to_atom(Service, utf8),
    RpcAtom = binary_to_atom(Rpc, utf8),
    Opts = [{stream_to, self()}],
    case grpcbox:start_stream(Channel, ServiceAtom, RpcAtom, Metadata, Opts) of
        {ok, Stream, Ref} -> {ok, {Stream, Ref}};
        {error, Reason} -> {error, format_error(Reason)}
    end.

%% Send data on a stream
send(Stream, Data) ->
    case grpcbox:send(Stream, Data) of
        ok -> {ok, nil};
        {error, Reason} -> {error, format_error(Reason)}
    end.

%% Receive data from a stream
recv(Stream, Timeout) ->
    receive
        {grpcbox, Stream, Ref, Response} ->
            {ok, Response};
        {grpcbox_closed, Stream} ->
            {error, stream_closed};
        {grpc_error, Stream, _, Reason} ->
            {error, format_error(Reason)}
    after Timeout ->
        {error, timeout}
    end.

%% Close a stream
close_stream(Stream) ->
    grpcbox:stop_stream(Stream),
    ok.

%% Close a channel
close_channel(Channel) ->
    grpcbox:ch(Channel, close),
    ok.

%% Format error reasons
format_error(Reason) when is_binary(Reason) -> Reason;
format_error(Reason) when is_atom(Reason) -> atom_to_binary(Reason, utf8);
format_error(Reason) -> list_to_binary(io_lib:format("~p", [Reason])).

%% Dummy functions for mock/testing
dummy_channel() -> dummy.
dummy_stream() -> dummy.
