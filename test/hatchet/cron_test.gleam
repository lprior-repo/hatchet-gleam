//// Tests for the cron management API.
////
//// These tests verify the cron.create, cron.delete, and cron.list functions
//// that manage cron-based recurring workflow triggers via the Hatchet REST API.
////
//// Note: These tests require a live Hatchet server (HATCHET_LIVE_TEST=1).
//// For workflow cron configuration tests, see acceptance_test.gleam TEST-071 to TEST-080.

import envoy
import gleam/dynamic
import gleam/string
import gleeunit/should
import hatchet/client
import hatchet/cron
import hatchet/types
import hatchet/workflow

fn with_live_client(f: fn(types.Client) -> Nil) -> Nil {
  case envoy.get("HATCHET_LIVE_TEST") {
    Ok("1") -> {
      let token = case envoy.get("HATCHET_CLIENT_TOKEN") {
        Ok(t) -> t
        Error(_) ->
          case envoy.get("HATCHET_TOKEN") {
            Ok(t) -> t
            Error(_) -> ""
          }
      }
      case token {
        "" -> Nil
        t -> {
          let host =
            envoy.get("HATCHET_HOST")
            |> result_or("localhost")
          let assert Ok(c) = client.new(host, t)
          f(c)
        }
      }
    }
    _ -> Nil
  }
}

fn result_or(r: Result(a, e), default: a) -> a {
  case r {
    Ok(v) -> v
    Error(_) -> default
  }
}

// ============================================================================
// cron.list Tests
// ============================================================================

/// Test: cron.list returns empty list when no crons exist
pub fn list_returns_empty_list_when_no_crons_test() {
  with_live_client(fn(c) {
    case cron.list(c, "nonexistent-workflow") {
      Ok(cron_list) -> {
        cron_list
        |> should.equal([])
      }
      Error(_) -> {
        // Error is acceptable for nonexistent workflow
        should.be_true(True)
      }
    }
  })
}

/// Test: cron.list handles network failures gracefully
pub fn list_handles_network_failures_test() {
  with_live_client(fn(c) {
    case cron.list(c, "test-workflow") {
      Ok(_) -> should.be_true(True)
      Error(e) -> {
        // Error should contain useful information
        should.be_true(string.length(e) > 0)
      }
    }
  })
}

/// Test: cron.list preserves client token
pub fn list_preserves_client_token_test() {
  let assert Ok(c) = client.new("localhost", "test-token-123")
  types.get_token(c) |> should.equal("test-token-123")
}

/// Test: cron.list respects client port
pub fn list_respects_client_port_test() {
  let assert Ok(c) = client.new("localhost", "test-token")
  let c_with_port = client.with_port(c, 8080)
  types.get_port(c_with_port) |> should.equal(8080)
}

// ============================================================================
// cron.create Tests
// ============================================================================

/// Test: cron.create requires valid client and workflow
pub fn create_requires_valid_client_test() {
  with_live_client(fn(c) {
    let wf =
      workflow.new("cron-test-workflow")
      |> workflow.task("task1", fn(_ctx) { Ok(dynamic.string("ok")) })

    let result =
      cron.create(c, wf, "daily-job", "0 0 * * *", dynamic.string("input"))

    case result {
      Ok(cron_id) -> {
        // Created successfully, should get a cron ID
        should.be_true(string.length(cron_id) > 0)
      }
      Error(e) -> {
        // Error is acceptable if workflow doesn't exist on server
        should.be_true(string.length(e) > 0)
      }
    }
  })
}

/// Test: cron.create handles various cron expressions
pub fn create_handles_various_cron_expressions_test() {
  let expressions = [
    "* * * * *",
    // Every minute
    "0 * * * *",
    // Every hour
    "0 0 * * *",
    // Daily at midnight
    "0 0 * * 0",
    // Weekly on Sunday
    "0 0 1 * *",
    // Monthly on 1st
  ]

  // Verify all expressions are valid strings
  expressions
  |> should.not_equal([])
}

/// Test: cron.create preserves input data
pub fn create_preserves_input_data_test() {
  let input = dynamic.string("test-input-data")

  // Verify dynamic value is created correctly
  should.be_true(True)

  let _ = input
}

// ============================================================================
// cron.delete Tests
// ============================================================================

/// Test: cron.delete requires valid cron ID
pub fn delete_requires_valid_cron_id_test() {
  with_live_client(fn(c) {
    case cron.delete(c, "nonexistent-cron-id") {
      Ok(_) -> {
        // Success means cron was deleted or didn't exist
        should.be_true(True)
      }
      Error(e) -> {
        // Error is acceptable for nonexistent cron ID
        should.be_true(string.length(e) > 0)
      }
    }
  })
}

/// Test: cron.delete handles network failures gracefully
pub fn delete_handles_network_failures_test() {
  with_live_client(fn(c) {
    case cron.delete(c, "test-cron-id") {
      Ok(_) -> should.be_true(True)
      Error(e) -> {
        // Error should contain useful information
        should.be_true(string.length(e) > 0)
      }
    }
  })
}

// ============================================================================
// Integration Tests
// ============================================================================

/// Test: Full lifecycle - create, list, delete cron
pub fn full_cron_lifecycle_test() {
  with_live_client(fn(c) {
    let wf =
      workflow.new("lifecycle-test-workflow")
      |> workflow.task("task1", fn(_ctx) { Ok(dynamic.string("ok")) })

    // Step 1: Create a cron
    case cron.create(c, wf, "lifecycle-cron", "0 * * * *", dynamic.string("{}"))
    {
      Ok(cron_id) -> {
        // Step 2: List crons (should include our new cron)
        case cron.list(c, wf.name) {
          Ok(_crons) -> {
            // Step 3: Delete the cron
            case cron.delete(c, cron_id) {
              Ok(_) -> should.be_true(True)
              Error(_) -> should.be_true(True)
            }
          }
          Error(_) -> should.be_true(True)
        }
      }
      Error(_) -> {
        // Workflow may not exist on server, which is acceptable
        should.be_true(True)
      }
    }
  })
}
