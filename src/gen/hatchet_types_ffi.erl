-module(hatchet_types_ffi).
-export([identity/1]).

%% Identity function for type coercion (safe on BEAM where types are erased)
identity(X) -> X.
