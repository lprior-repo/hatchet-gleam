//// Live integration tests against a running Hatchet Docker instance.
////
//// These tests are skipped when HATCHET_CLIENT_TOKEN is not set.
//// To run:
////   HATCHET_CLIENT_TOKEN=<token> gleam test

import envoy
import gleam/dict
import gleam/dynamic
import gleam/erlang/process
import gleam/option.{None, Some}
import gleeunit/should
import hatchet/client
import hatchet/types

/// Helper: skip test if no token is available
fn with_live_client(f: fn(types.Client) -> Nil) -> Nil {
  case envoy.get("HATCHET_CLIENT_TOKEN") {
    Error(_) ->
      case envoy.get("HATCHET_TOKEN") {
        Error(_) -> Nil
        Ok(token) -> run_with_token(token, f)
      }
    Ok(token) -> run_with_token(token, f)
  }
}

fn run_with_token(token: String, f: fn(types.Client) -> Nil) -> Nil {
  let host =
    envoy.get("HATCHET_HOST")
    |> result_or("localhost")
  let assert Ok(c) = client.new(host, token)
  f(c)
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
            wait_for: None,
          ),
        ],
        on_failure: None,
        cron: None,
        events: [],
        concurrency: None,
      )

    // Create worker with gRPC port 7077
    let worker_result =
      client.new_worker_with_grpc_port(c, config, [workflow], 7077)
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
