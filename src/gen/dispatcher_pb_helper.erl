-module(dispatcher_pb_helper).
-export([new_map/0,
         put_string/3, put_int/3, put_list/3,
         get_string/2,
         encode_msg/2, decode_msg/2]).

%% Create a new empty map
new_map() -> #{}.

%% Put a string value with atom key
put_string(Map, Key, Value) when is_binary(Key) ->
    AtomKey = binary_to_atom(Key, utf8),
    Map#{AtomKey => Value}.

%% Put an int value with atom key
put_int(Map, Key, Value) when is_binary(Key) ->
    AtomKey = binary_to_atom(Key, utf8),
    Map#{AtomKey => Value}.

%% Put a list value with atom key
put_list(Map, Key, Value) when is_binary(Key) ->
    AtomKey = binary_to_atom(Key, utf8),
    Map#{AtomKey => Value}.

%% Get a string value by atom key (also accept string key for lookup)
get_string(Map, Key) when is_binary(Key) ->
    AtomKey = binary_to_atom(Key, utf8),
    case maps:find(AtomKey, Map) of
        {ok, V} when is_binary(V) -> {ok, V};
        _ -> {error, nil}
    end.

%% Encode msg - convert binary message name to atom for gpb
encode_msg(MsgNameBin, Map) when is_binary(MsgNameBin) ->
    MsgName = binary_to_atom(MsgNameBin, utf8),
    dispatcher_pb:encode_msg(Map, MsgName).

%% Decode msg - convert binary message name to atom for gpb
decode_msg(MsgNameBin, Binary) when is_binary(MsgNameBin) ->
    MsgName = binary_to_atom(MsgNameBin, utf8),
    dispatcher_pb:decode_msg(Binary, MsgName).
