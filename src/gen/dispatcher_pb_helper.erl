-module(dispatcher_pb_helper).
-export([new_map/0,
         put_string/3, put_int/3, put_list/3, put_bool/3, put_nested/3, put_label_map/3,
         put_enum/3,
         get_string/2, get_string_default/3, get_string_option/2,
         get_int/2, get_int_default/3, get_int_option/2,
         encode_msg/2, decode_msg/2]).

%% ============================================================================
%% Map Construction
%% ============================================================================

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

%% Put a boolean value with atom key
put_bool(Map, Key, Value) when is_binary(Key), is_boolean(Value) ->
    AtomKey = binary_to_atom(Key, utf8),
    Map#{AtomKey => Value}.

%% Put an enum value with atom key (for gpb enum fields)
%% EnumValue is a binary that gets converted to an atom for gpb
put_enum(Map, Key, EnumValue) when is_binary(Key), is_binary(EnumValue) ->
    AtomKey = binary_to_atom(Key, utf8),
    EnumAtom = binary_to_atom(EnumValue, utf8),
    Map#{AtomKey => EnumAtom}.

%% Put a nested map with atom key
put_nested(Map, Key, NestedMap) when is_binary(Key), is_map(NestedMap) ->
    AtomKey = binary_to_atom(Key, utf8),
    Map#{AtomKey => NestedMap}.

%% Put a label map (for WorkerLabels map<string, WorkerLabels>)
%% gpb expects labels as #{BinaryKey => WorkerLabelsMap} where keys stay as binaries
%% because the proto map<string, WorkerLabels> encodes keys via e_type_string
put_label_map(Map, Key, Labels) when is_binary(Key), is_list(Labels) ->
    AtomKey = binary_to_atom(Key, utf8),
    %% Convert [{BinaryKey, LabelMap}] to #{BinaryKey => LabelMap}
    %% Keep label name keys as binaries - gpb's e_type_string expects binaries
    LabelMap = lists:foldl(fun({LabelKey, LabelValue}, Acc) ->
        Acc#{LabelKey => LabelValue}
    end, #{}, Labels),
    Map#{AtomKey => LabelMap}.

%% ============================================================================
%% Map Access - String
%% ============================================================================

%% Get a string value by atom key (returns Result)
get_string(Map, Key) when is_binary(Key) ->
    AtomKey = binary_to_atom(Key, utf8),
    case maps:find(AtomKey, Map) of
        {ok, V} when is_binary(V) -> {ok, V};
        {ok, V} when is_list(V) -> {ok, list_to_binary(V)};
        _ -> {error, nil}
    end.

%% Get a string value with a default
get_string_default(Map, Key, Default) when is_binary(Key), is_binary(Default) ->
    AtomKey = binary_to_atom(Key, utf8),
    case maps:find(AtomKey, Map) of
        {ok, V} when is_binary(V) -> V;
        {ok, V} when is_list(V) -> list_to_binary(V);
        {ok, undefined} -> Default;
        _ -> Default
    end.

%% Get a string value as Option (returns {some, Value} or none)
get_string_option(Map, Key) when is_binary(Key) ->
    AtomKey = binary_to_atom(Key, utf8),
    case maps:find(AtomKey, Map) of
        {ok, V} when is_binary(V), V =/= <<>> -> {some, V};
        {ok, V} when is_list(V), V =/= [] -> {some, list_to_binary(V)};
        _ -> none
    end.

%% ============================================================================
%% Map Access - Integer
%% ============================================================================

%% Get an int value by atom key (returns Result)
get_int(Map, Key) when is_binary(Key) ->
    AtomKey = binary_to_atom(Key, utf8),
    case maps:find(AtomKey, Map) of
        {ok, V} when is_integer(V) -> {ok, V};
        _ -> {error, nil}
    end.

%% Get an int value with a default
get_int_default(Map, Key, Default) when is_binary(Key), is_integer(Default) ->
    AtomKey = binary_to_atom(Key, utf8),
    case maps:find(AtomKey, Map) of
        {ok, V} when is_integer(V) -> V;
        {ok, undefined} -> Default;
        _ -> Default
    end.

%% Get an int value as Option (returns {some, Value} or none)
get_int_option(Map, Key) when is_binary(Key) ->
    AtomKey = binary_to_atom(Key, utf8),
    case maps:find(AtomKey, Map) of
        {ok, V} when is_integer(V) -> {some, V};
        _ -> none
    end.

%% ============================================================================
%% Protobuf Encoding/Decoding
%% ============================================================================

%% Encode msg - convert binary message name to atom for gpb
encode_msg(MsgNameBin, Map) when is_binary(MsgNameBin) ->
    MsgName = binary_to_atom(MsgNameBin, utf8),
    dispatcher_pb:encode_msg(Map, MsgName).

%% Decode msg - convert binary message name to atom for gpb
decode_msg(MsgNameBin, Binary) when is_binary(MsgNameBin) ->
    MsgName = binary_to_atom(MsgNameBin, utf8),
    dispatcher_pb:decode_msg(Binary, MsgName).
