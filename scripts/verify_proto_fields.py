#!/usr/bin/env python3
"""
Test to verify proto field names match upstream Hatchet.

This test ensures our proto/dispatcher.proto uses camelCase field names
matching upstream Hatchet's naming convention.
"""

import subprocess
import sys


def fetch_upstream_proto():
    """Fetch upstream proto from GitHub"""
    import urllib.request

    url = "https://raw.githubusercontent.com/hatchet-dev/hatchet/main/api-contracts/dispatcher/dispatcher.proto"
    with urllib.request.urlopen(url) as response:
        return response.read().decode("utf-8")


def extract_field_names(proto_content):
    """Extract field names from proto content"""
    import re

    # Match lines like:  string worker_name = 1;
    field_pattern = r"\b(\w+)\s+=\s+\d+;"
    fields = re.findall(field_pattern, proto_content)
    return set(fields)


def main():
    # Read local proto
    with open("proto/dispatcher.proto", "r") as f:
        local_proto = f.read()

    # Fetch upstream proto
    print("Fetching upstream proto...")
    upstream_proto = fetch_upstream_proto()

    # Remove go_package line for comparison (we don't use it)
    upstream_proto_lines = [
        line
        for line in upstream_proto.split("\n")
        if not line.strip().startswith("option go_package")
    ]

    # Extract field names
    local_fields = extract_field_names(local_proto)
    upstream_fields = extract_field_names("\n".join(upstream_proto_lines))

    # Check for snake_case fields (should NOT exist in aligned proto)
    # Exclude enum values (typically ALL_CAPS_WITH_UNDERSCORES)
    snake_case_fields = [f for f in local_fields if "_" in f and not f.isupper()]
    if snake_case_fields:
        print(f"❌ FAIL: Found snake_case field names: {snake_case_fields}")
        print("Expected: All fields should be camelCase to match upstream")
        return False

    # Check for differences
    if local_fields != upstream_fields:
        only_local = local_fields - upstream_fields
        only_upstream = upstream_fields - local_fields
        if only_local or only_upstream:
            print(f"❌ FAIL: Field name mismatch")
            if only_local:
                print(f"  Only in local proto: {only_local}")
            if only_upstream:
                print(f"  Only in upstream proto: {only_upstream}")
            return False

    print(
        f"✅ PASS: All {len(local_fields)} field names match upstream and use camelCase"
    )
    return True


if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
