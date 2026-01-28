#!/usr/bin/env bash
# Regenerate dispatcher_pb.erl from proto/dispatcher.proto using gpb
#
# Prerequisites: gpb must be built at /tmp/gpb_build or set GPB_PATH
# To build gpb:
#   git clone --depth 1 https://github.com/tomas-abrahamsson/gpb.git /tmp/gpb_build
#   make -C /tmp/gpb_build

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
GPB_PATH="${GPB_PATH:-/tmp/gpb_build}"

if [ ! -d "$GPB_PATH/ebin" ]; then
    echo "gpb not found at $GPB_PATH. Building..."
    git clone --depth 1 https://github.com/tomas-abrahamsson/gpb.git "$GPB_PATH"
    make -C "$GPB_PATH"
fi

echo "Compiling proto/dispatcher.proto..."
erl -noshell -pa "$GPB_PATH/ebin" -eval "
    Opts = [maps, {maps_oneof, flat}, strings_as_binaries,
            {module_name_suffix, \"_pb\"},
            {o_erl, \"$PROJECT_DIR/src/gen\"},
            {o_hrl, \"$PROJECT_DIR/src/gen\"},
            {i, \"$PROJECT_DIR/proto\"}],
    case gpb_compile:file(\"dispatcher.proto\", Opts) of
        ok -> io:format(\"Success: src/gen/dispatcher_pb.erl generated~n\"), halt(0);
        {error, Reason} -> io:format(\"Error: ~p~n\", [Reason]), halt(1)
    end."

echo "Done."
