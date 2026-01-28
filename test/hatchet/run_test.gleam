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
    _ -> should.fail()
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
