//// Live integration tests against a running Hatchet Docker instance.
////
//// These tests are skipped unless HATCHET_LIVE_TEST=1 is set.
//// To run:
////   docker compose up -d
////   HATCHET_LIVE_TEST=1 gleam test

import envoy
import gleam/dict
import gleam/dynamic.{string}
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/io
import gleam/option.{Some}
import gleam/string
import gleeunit/should
import hatchet/client
import hatchet/run
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
        "" -> io.println("Skipping: No HATCHET_CLIENT_TOKEN set")
        t -> {
          let host =
            envoy.get("HATCHET_HOST")
            |> result_or("localhost")
          let assert Ok(c) = client.new(host, t)
          f(c)
        }
      }
    }
    _ -> io.println("Skipping: HATCHET_LIVE_TEST not set to 1")
  }
}

fn result_or(r: Result(a, e), default: a) -> a {
  case r {
    Ok(v) -> v
    Error(_) -> default
  }
}

pub fn end_to_end_workflow_execution_test() {
  with_live_client(fn(client) {
    io.println("\n=== E2E Workflow Execution Test ===\n")

    io.println("1. Creating test workflow...")
    let test_workflow =
      workflow.new("e2e-test-workflow")
      |> workflow.with_description("End-to-end integration test")
      |> workflow.task("greet", fn(ctx) {
        case decode.run(ctx.input, decode.string) {
          Ok(name) -> {
            io.println("   [Task greet] Executing with: " <> name)
            let greeting = "Hello, " <> name <> "!"
            io.println("   [Task greet] Result: " <> greeting)
            Ok(string(greeting))
          }
          Error(_) -> {
            io.println("   [Task greet] Failed: invalid input")
            Error("Invalid input: expected string")
          }
        }
      })
      |> workflow.task_after("uppercase", ["greet"], fn(ctx) {
        case decode.run(ctx.input, decode.string) {
          Ok(msg) -> {
            io.println("   [Task uppercase] Executing with: " <> msg)
            let result = string.uppercase(msg)
            io.println("   [Task uppercase] Result: " <> result)
            Ok(string(result))
          }
          Error(_) -> {
            io.println("   [Task uppercase] Failed: invalid input")
            Error("Invalid input: expected string")
          }
        }
      })
      |> workflow.with_retries(2)

    io.println("   ✅ Workflow created\n")

    io.println("2. Creating worker...")
    let config =
      types.WorkerConfig(
        name: Some("e2e-test-worker"),
        slots: 5,
        durable_slots: 0,
        labels: dict.from_list([#("env", "test"), #("version", "1.0.0")]),
      )

    let assert Ok(worker) =
      client.new_worker_with_grpc_port(client, config, [test_workflow], 7077)

    io.println("   ✅ Worker created\n")

    io.println("3. Starting worker...")
    let assert Ok(stop_worker) = client.start_worker(worker)
    io.println("   ✅ Worker started\n")

    io.println("4. Waiting for worker registration...")
    process.sleep(3000)
    io.println("   ✅ Worker should be registered\n")

    io.println("5. Triggering workflow execution...")
    let input_data = dynamic.string("World")
    let assert Ok(_result) = run.run(client, test_workflow, input_data)
    io.println("   ✅ Workflow triggered\n")

    io.println("6. Waiting for task execution (5 seconds)...")
    process.sleep(5000)
    io.println("   ✅ Tasks should have executed\n")

    io.println("7. Stopping worker...")
    stop_worker()
    process.sleep(500)
    io.println("   ✅ Worker stopped\n")

    io.println("=== E2E Test Complete ===\n")
  })
}

pub fn worker_registration_and_connection_test() {
  with_live_client(fn(client) {
    io.println("\n=== Worker Registration Test ===\n")

    io.println("1. Creating simple workflow...")
    let simple_workflow =
      workflow.new("registration-test-workflow")
      |> workflow.task("echo", fn(ctx) {
        case decode.run(ctx.input, decode.string) {
          Ok(msg) -> Ok(string(msg))
          Error(_) -> Ok(string("default"))
        }
      })

    io.println("   ✅ Workflow created\n")

    io.println("2. Creating worker with labels...")
    let config =
      types.WorkerConfig(
        name: Some("registration-test-worker"),
        slots: 1,
        durable_slots: 0,
        labels: dict.from_list([
          #("env", "test"),
          #("region", "us-east-1"),
          #("pool", "default"),
        ]),
      )

    let assert Ok(worker) =
      client.new_worker_with_grpc_port(client, config, [simple_workflow], 7077)

    io.println("   ✅ Worker created\n")

    io.println("3. Starting and stopping worker...")
    client.start_worker_blocking(worker)
    |> should.be_ok()

    io.println("   ✅ Worker ran successfully\n")

    io.println("=== Registration Test Complete ===\n")
  })
}
