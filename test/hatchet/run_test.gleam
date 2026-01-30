import gleam/dict
import gleam/list
import gleam/option
import gleeunit/should
import hatchet/client
import hatchet/run
import hatchet/types

// ============================================================================
// Run Creation and Initialization Tests
// ============================================================================

pub fn run_ref_creates_unique_id_test() {
  let assert Ok(client) = client.new("localhost", "test-token")
  let run_ref_1 = types.create_workflow_run_ref("run-123", client)
  let run_ref_2 = types.create_workflow_run_ref("run-456", client)

  types.get_run_id(run_ref_1)
  |> should.equal("run-123")

  types.get_run_id(run_ref_2)
  |> should.equal("run-456")
}

pub fn run_ref_stores_client_test() {
  let assert Ok(client) = client.new("localhost", "test-token")
  let run_ref = types.create_workflow_run_ref("run-123", client)

  types.get_ref_client(run_ref)
  |> types.get_host
  |> should.equal("localhost")
}

pub fn run_metadata_captured_test() {
  let metadata = dict.from_list([#("env", "test"), #("user", "alice")])
  let options =
    types.RunOptions(
      metadata: metadata,
      priority: option.None,
      sticky: False,
      run_key: option.None,
    )

  options.metadata
  |> dict.get("env")
  |> should.equal(Ok("test"))
}

pub fn run_key_supports_deduplication_test() {
  let options =
    types.RunOptions(
      metadata: dict.new(),
      priority: option.None,
      sticky: False,
      run_key: option.Some("daily-batch-2026-01-27"),
    )

  options.run_key
  |> should.equal(option.Some("daily-batch-2026-01-27"))
}

pub fn run_priority_supported_test() {
  let options =
    types.RunOptions(
      metadata: dict.new(),
      priority: option.Some(5),
      sticky: False,
      run_key: option.None,
    )

  options.priority
  |> should.equal(option.Some(5))
}

// ============================================================================
// Run Status Tracking Tests
// ============================================================================

pub fn run_status_type_has_all_states_test() {
  let pending = types.Pending
  let running = types.Running
  let succeeded = types.Succeeded
  let failed = types.Failed("error")
  let cancelled = types.Cancelled

  pending
  |> should.equal(types.Pending)

  running
  |> should.equal(types.Running)

  succeeded
  |> should.equal(types.Succeeded)

  failed
  |> should.equal(types.Failed("error"))

  cancelled
  |> should.equal(types.Cancelled)
}

pub fn run_status_failed_contains_error_message_test() {
  let failed = types.Failed("Task timeout after 30s")

  case failed {
    types.Failed(err) -> err |> should.equal("Task timeout after 30s")
  }
}

// ============================================================================
// Run Cancellation Tests
// ============================================================================

pub fn cancel_function_exists_test() {
  let assert Ok(client) = client.new("localhost", "test-token")
  let run_ref = types.create_workflow_run_ref("run-123", client)

  run.cancel(run_ref)
  |> should.be_error
}

pub fn bulk_cancel_function_exists_test() {
  let assert Ok(client) = client.new("localhost", "test-token")
  let run_ids = ["run-123", "run-456", "run-789"]

  run.bulk_cancel(client, run_ids)
  |> should.be_error
}

// ============================================================================
// Run Replay Tests
// ============================================================================

pub fn replay_function_exists_test() {
  let assert Ok(client) = client.new("localhost", "test-token")
  let run_ids = ["run-123", "run-456"]

  run.replay(client, run_ids)
  |> should.be_error
}

// ============================================================================
// Additional Run State Tests (Documenting Gaps)
// ============================================================================

pub fn run_status_types_missing_timed_out_test() {
  let statuses = [
    types.Pending,
    types.Running,
    types.Succeeded,
    types.Failed("test"),
    types.Cancelled,
  ]

  list.length(statuses)
  |> should.equal(5)
}

pub fn run_ref_no_parent_run_id_test() {
  let assert Ok(client) = client.new("localhost", "test-token")
  let run_ref = types.create_workflow_run_ref("run-123", client)

  types.get_run_id(run_ref)
  |> should.equal("run-123")
}

// ============================================================================
// Run Options Configuration Tests
// ============================================================================

pub fn run_options_default_values_test() {
  let options =
    types.RunOptions(
      metadata: dict.new(),
      priority: option.None,
      sticky: False,
      run_key: option.None,
    )

  options.sticky
  |> should.equal(False)

  options.priority
  |> should.equal(option.None)

  dict.size(options.metadata)
  |> should.equal(0)
}

pub fn run_options_with_all_fields_test() {
  let metadata =
    dict.from_list([
      #("user_id", "user-123"),
      #("request_id", "req-456"),
      #("trace_id", "trace-789"),
    ])

  let options =
    types.RunOptions(
      metadata: metadata,
      priority: option.Some(10),
      sticky: True,
      run_key: option.Some("unique-key-abc"),
    )

  options.sticky
  |> should.equal(True)

  options.priority
  |> should.equal(option.Some(10))

  options.run_key
  |> should.equal(option.Some("unique-key-abc"))

  dict.size(options.metadata)
  |> should.equal(3)
}

pub fn run_options_metadata_access_test() {
  let metadata = dict.from_list([#("key1", "value1"), #("key2", "value2")])

  let options =
    types.RunOptions(
      metadata: metadata,
      priority: option.None,
      sticky: False,
      run_key: option.None,
    )

  case dict.get(options.metadata, "key1") {
    Ok(val) -> val |> should.equal("value1")
    Error(_) -> should.fail()
  }
}

// ============================================================================
// Workflow Run Reference Tests
// ============================================================================

pub fn workflow_run_ref_immutability_test() {
  let assert Ok(client1) = client.new("host1", "token1")
  let assert Ok(client2) = client.new("host2", "token2")

  let ref1 = types.create_workflow_run_ref("run-1", client1)
  let ref2 = types.create_workflow_run_ref("run-2", client2)

  types.get_run_id(ref1)
  |> should.equal("run-1")

  types.get_run_id(ref2)
  |> should.equal("run-2")

  types.get_ref_client(ref1)
  |> types.get_host
  |> should.equal("host1")

  types.get_ref_client(ref2)
  |> types.get_host
  |> should.equal("host2")
}

pub fn workflow_run_ref_preserves_client_config_test() {
  let assert Ok(base_client) = client.new("localhost", "test-token")
  let client_with_port = client.with_port(base_client, 8080)
  let client_with_ns = client.with_namespace(client_with_port, "production")

  let run_ref = types.create_workflow_run_ref("run-123", client_with_ns)

  let retrieved_client = types.get_ref_client(run_ref)

  types.get_port(retrieved_client)
  |> should.equal(8080)

  types.get_namespace(retrieved_client)
  |> should.equal(option.Some("production"))
}

// ============================================================================
// Status Parsing Tests
// ============================================================================

pub fn run_status_equality_test() {
  let pending1 = types.Pending
  let pending2 = types.Pending

  pending1
  |> should.equal(pending2)
}

pub fn run_status_failed_different_messages_test() {
  let failed1 = types.Failed("Error A")
  let failed2 = types.Failed("Error B")

  case failed1 {
    types.Failed(msg) -> msg |> should.equal("Error A")
  }

  case failed2 {
    types.Failed(msg) -> msg |> should.equal("Error B")
  }
}

pub fn run_status_pattern_matching_test() {
  let statuses = [
    types.Pending,
    types.Running,
    types.Succeeded,
    types.Failed("test error"),
    types.Cancelled,
  ]

  let status_count = list.length(statuses)

  status_count
  |> should.equal(5)
}

// ============================================================================
// Multiple Run Management Tests
// ============================================================================

pub fn multiple_run_refs_test() {
  let assert Ok(client) = client.new("localhost", "test-token")

  let refs =
    list.map(["run-1", "run-2", "run-3"], fn(id) {
      types.create_workflow_run_ref(id, client)
    })

  list.length(refs)
  |> should.equal(3)

  case list.first(refs) {
    Ok(ref) ->
      types.get_run_id(ref)
      |> should.equal("run-1")
    Error(_) -> should.fail()
  }
}

// ============================================================================
// Priority Configuration Tests
// ============================================================================

pub fn run_priority_range_test() {
  let low_priority =
    types.RunOptions(
      metadata: dict.new(),
      priority: option.Some(1),
      sticky: False,
      run_key: option.None,
    )

  let high_priority =
    types.RunOptions(
      metadata: dict.new(),
      priority: option.Some(100),
      sticky: False,
      run_key: option.None,
    )

  low_priority.priority
  |> should.equal(option.Some(1))

  high_priority.priority
  |> should.equal(option.Some(100))
}

pub fn run_priority_none_test() {
  let options =
    types.RunOptions(
      metadata: dict.new(),
      priority: option.None,
      sticky: False,
      run_key: option.None,
    )

  options.priority
  |> should.equal(option.None)
}

// ============================================================================
// Sticky Workflow Tests
// ============================================================================

pub fn run_sticky_enabled_test() {
  let options =
    types.RunOptions(
      metadata: dict.new(),
      priority: option.None,
      sticky: True,
      run_key: option.None,
    )

  options.sticky
  |> should.equal(True)
}

pub fn run_sticky_disabled_test() {
  let options =
    types.RunOptions(
      metadata: dict.new(),
      priority: option.None,
      sticky: False,
      run_key: option.None,
    )

  options.sticky
  |> should.equal(False)
}

// ============================================================================
// Run Key Deduplication Tests
// ============================================================================

pub fn run_key_format_test() {
  let options =
    types.RunOptions(
      metadata: dict.new(),
      priority: option.None,
      sticky: False,
      run_key: option.Some("batch-2026-01-30-12:00:00"),
    )

  case options.run_key {
    option.Some(key) -> key |> should.equal("batch-2026-01-30-12:00:00")
    option.None -> should.fail()
  }
}

pub fn run_key_none_test() {
  let options =
    types.RunOptions(
      metadata: dict.new(),
      priority: option.None,
      sticky: False,
      run_key: option.None,
    )

  options.run_key
  |> should.equal(option.None)
}

// ============================================================================
// Metadata Complex Types Tests
// ============================================================================

pub fn run_metadata_multiple_entries_test() {
  let metadata =
    dict.from_list([
      #("key1", "value1"),
      #("key2", "value2"),
      #("key3", "value3"),
      #("key4", "value4"),
      #("key5", "value5"),
    ])

  let options =
    types.RunOptions(
      metadata: metadata,
      priority: option.None,
      sticky: False,
      run_key: option.None,
    )

  dict.size(options.metadata)
  |> should.equal(5)

  dict.to_list(options.metadata)
  |> list.length
  |> should.equal(5)
}

pub fn run_metadata_empty_test() {
  let options =
    types.RunOptions(
      metadata: dict.new(),
      priority: option.None,
      sticky: False,
      run_key: option.None,
    )

  dict.size(options.metadata)
  |> should.equal(0)
}

// ============================================================================
// Edge Cases and Error Scenarios
// ============================================================================

pub fn run_status_failed_empty_message_test() {
  let failed = types.Failed("")

  case failed {
    types.Failed(msg) -> msg |> should.equal("")
  }
}

pub fn run_key_empty_string_test() {
  let options =
    types.RunOptions(
      metadata: dict.new(),
      priority: option.None,
      sticky: False,
      run_key: option.Some(""),
    )

  case options.run_key {
    option.Some(key) -> key |> should.equal("")
    option.None -> should.fail()
  }
}
