//// Live integration tests against a running Hatchet Docker instance.
////
//// These tests are skipped unless HATCHET_LIVE_TEST=1 is set.
//// To run:
////   HATCHET_LIVE_TEST=1 HATCHET_CLIENT_TOKEN=<token> gleam test
////
//// For comprehensive live integration tests covering the full Manual Testing
//// Checklist from HATCHET_TESTING.md, see: test/integration/live_test.gleam

import envoy
import gleam/dict
import gleam/dynamic
import gleam/erlang/process
import gleam/option.{None, Some}
import gleeunit/should
import hatchet/client
import hatchet/types

/// Helper: skip test unless HATCHET_LIVE_TEST=1 is explicitly set
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

/// Test: Worker can connect, register, and be stopped gracefully
pub fn live_worker_registration_test() {
  with_live_client(fn(c) {
    let config =
      types.WorkerConfig(
        name: Some("live-test-worker"),
        slots: 1,
        durable_slots: 0,
        labels: dict.from_list([#("env", "test"), #("version", "1.0.0")]),
      )

    let workflow =
      types.Workflow(
        name: "live-test-workflow",
        description: Some("Integration test workflow"),
        version: Some("1.0.0"),
        tasks: [
          types.TaskDef(
            name: "test-task",
            handler: fn(_ctx: types.TaskContext) { Ok(dynamic.string("ok")) },
            parents: [],
            retries: 0,
            retry_backoff: None,
            execution_timeout_ms: None,
            schedule_timeout_ms: None,
            rate_limits: [],
            concurrency: None,
            skip_if: None,
            cancel_if: None,
            wait_for: None,
            is_durable: False,
            checkpoint_key: None,
          ),
        ],
        on_failure: None,
        on_success: None,
        cron: None,
        events: [],
        concurrency: None,
      )

    // Create worker with gRPC port 7077
    let worker_result =
      client.new_worker_with_grpc_port(c, config, [workflow], 7077, None)
    worker_result |> should.be_ok()

    let assert Ok(worker) = worker_result

    // Give worker time to connect and register
    process.sleep(2000)

    // Stop the worker gracefully
    client.stop_worker(worker)

    // Give time for shutdown
    process.sleep(500)
  })
}
