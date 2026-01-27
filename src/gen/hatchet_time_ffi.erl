-module(hatchet_time_ffi).
-export([system_time_ms/0]).

%% Get the current system time in milliseconds
system_time_ms() ->
    erlang:system_time(millisecond).
