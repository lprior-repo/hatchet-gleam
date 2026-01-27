-module(hatchet_os_ffi).
-export([get_os_info/0]).

%% Get OS information as a string
get_os_info() ->
    {OsFamily, OsName} = os:type(),
    OsVersion = case os:version() of
        {Major, Minor, Patch} ->
            io_lib:format("~p.~p.~p", [Major, Minor, Patch]);
        VersionString when is_list(VersionString) ->
            VersionString;
        _ ->
            "unknown"
    end,
    iolist_to_binary([
        atom_to_binary(OsFamily, utf8),
        <<"/">>,
        atom_to_binary(OsName, utf8),
        <<" ">>,
        iolist_to_binary(OsVersion)
    ]).
