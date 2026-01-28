import envoy
import gleam/dict
import gleam/dynamic.{int, string}
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import hatchet/client
import hatchet/internal/protocol as p
import hatchet/run
import hatchet/types
import hatchet/workflow

// ============================================================================
// Test: Workflow Registration API Structure
// ============================================================================

/// Test workflow registration API structure
/// Verifies that workflow definitions can be converted to protocol format
pub fn workflow_registration_test() {
  // Define a simple workflow
  let workflow =
    workflow.new("test-simple-workflow")
    |> workflow.with_description("Simple test workflow")
    |> workflow.with_version("1.0.0")
    |> workflow.task("echo", fn(_ctx) { Ok(string("hello")) })

  // Verify workflow structure
  workflow.name
  |> should.equal("test-simple-workflow")

  workflow.version
  |> should.equal(Some("1.0.0"))

  list.length(workflow.tasks)
  |> should.equal(1)
}

// ============================================================================
// Test: Workflow Conversion API
// ============================================================================

/// Test that workflows can be converted to protocol format
pub fn workflow_conversion_test() {
  let workflow =
    workflow.new("conversion-test")
    |> workflow.with_version("1.0.0")
    |> workflow.task("task1", fn(_ctx) { Ok(string("output1")) })
    |> workflow.task_after("task2", ["task1"], fn(_ctx) {
      Ok(string("output2"))
    })

  let converted: p.WorkflowCreateRequest =
    run.convert_workflow_to_protocol_for_test(workflow)

  // Verify conversion
  converted.name
  |> should.equal("conversion-test")

  converted.version
  |> should.equal(Some("1.0.0"))

  list.length(converted.tasks)
  |> should.equal(2)
}

// ============================================================================
// Live End-to-End Tests
// ============================================================================

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

/// Test: End-to-end task execution - Happy Path
///
/// 1. Register workflow via REST API
/// 2. Start worker
/// 3. Trigger workflow run via REST
/// 4. Worker receives and executes task
/// 5. Run completes successfully with correct output
pub fn e2e_happy_path_test() {
  with_live_client(fn(c) {
    let workflow_name = "e2e-happy-path-workflow"
    let task_name = "echo-task"

    let workflow =
      workflow.new(workflow_name)
      |> workflow.with_description("E2E test workflow")
      |> workflow.with_version("1.0.0")
      |> workflow.task(task_name, fn(ctx) {
        case decode.run(ctx.input, decode.string) {
          Ok("hello") -> {
            Ok(string("hello echoed"))
          }
          Ok(_) -> Ok(string("unknown input"))
          Error(_) -> Error("Expected 'message' field")
        }
      })

    let register_result = client.register_workflow(c, workflow)
    register_result |> should.be_ok()

    let worker_config =
      types.WorkerConfig(
        name: Some("e2e-test-worker"),
        slots: 1,
        durable_slots: 0,
        labels: dict.from_list([#("env", "e2e"), #("test", "happy-path")]),
      )

    let worker_result =
      client.new_worker_with_grpc_port(c, worker_config, [workflow], 7077, None)
    worker_result |> should.be_ok()

    let assert Ok(worker) = worker_result

    process.sleep(1000)

    let input = string("hello")

    let run_result = run.run_no_wait(c, workflow, input)
    run_result |> should.be_ok()

    let assert Ok(run_ref) = run_result

    let wait_result = run.await_result(run_ref)

    client.stop_worker(worker)
    process.sleep(500)

    case wait_result {
      Ok(output) -> {
        case decode.run(output, decode.string) {
          Ok("hello echoed") -> True
          Ok(_) -> False
          Error(_) -> False
        }
        |> should.be_true()
      }
      Error(_) -> should.be_true(False)
    }
  })
}

/// Test: End-to-end task execution with input processing
///
/// 1. Register workflow that processes input
/// 2. Start worker
/// 3. Trigger workflow with numeric input
/// 4. Worker doubles the input value
/// 5. Verify correct output
pub fn e2e_numeric_processing_test() {
  with_live_client(fn(c) {
    let workflow_name = "e2e-numeric-workflow"
    let task_name = "double-task"

    let workflow =
      workflow.new(workflow_name)
      |> workflow.with_description("E2E numeric test workflow")
      |> workflow.with_version("1.0.0")
      |> workflow.task(task_name, fn(ctx) {
        case decode.run(ctx.input, decode.int) {
          Ok(value) -> Ok(int(value * 2))
          Error(_) -> Error("Expected integer input")
        }
      })

    let register_result = client.register_workflow(c, workflow)
    register_result |> should.be_ok()

    let worker_config =
      types.WorkerConfig(
        name: Some("e2e-numeric-worker"),
        slots: 1,
        durable_slots: 0,
        labels: dict.from_list([#("env", "e2e"), #("test", "numeric")]),
      )

    let worker_result =
      client.new_worker_with_grpc_port(c, worker_config, [workflow], 7077, None)
    worker_result |> should.be_ok()

    let assert Ok(worker) = worker_result

    process.sleep(1000)

    let input = int(21)

    let run_result = run.run_no_wait(c, workflow, input)
    run_result |> should.be_ok()

    let assert Ok(run_ref) = run_result

    let wait_result = run.await_result(run_ref)

    client.stop_worker(worker)
    process.sleep(500)

    case wait_result {
      Ok(output) -> {
        case decode.run(output, decode.int) {
          Ok(42) -> True
          Ok(_) -> False
          Error(_) -> False
        }
        |> should.be_true()
      }
      Error(_) -> should.be_true(False)
    }
  })
}

/// Test: End-to-end multi-step workflow execution
///
/// 1. Register workflow with dependent tasks
/// 2. Start worker
/// 3. Trigger workflow run
/// 4. Worker executes tasks in correct order
/// 5. Verify final output is correct
pub fn e2e_multi_step_workflow_test() {
  with_live_client(fn(c) {
    let workflow_name = "e2e-multi-step-workflow"

    let workflow =
      workflow.new(workflow_name)
      |> workflow.with_description("E2E multi-step test workflow")
      |> workflow.with_version("1.0.0")
      |> workflow.task("step1", fn(ctx) {
        case decode.run(ctx.input, decode.int) {
          Ok(value) -> Ok(int(value * 2))
          Error(_) -> Error("Expected 'value' field")
        }
      })
      |> workflow.task_after("step2", ["step1"], fn(ctx) {
        case dict.get(ctx.parent_outputs, "step1") {
          Ok(step1_result) -> {
            case decode.run(step1_result, decode.int) {
              Ok(value) -> Ok(int(value + 10))
              Error(_) -> Error("Failed to decode step1 output")
            }
          }
          Error(_) -> Error("Expected step1 output")
        }
      })

    let register_result = client.register_workflow(c, workflow)
    register_result |> should.be_ok()

    let worker_config =
      types.WorkerConfig(
        name: Some("e2e-multi-step-worker"),
        slots: 2,
        durable_slots: 0,
        labels: dict.from_list([#("env", "e2e"), #("test", "multi-step")]),
      )

    let worker_result =
      client.new_worker_with_grpc_port(c, worker_config, [workflow], 7077, None)
    worker_result |> should.be_ok()

    let assert Ok(worker) = worker_result

    process.sleep(1000)

    let input = int(5)

    let run_result = run.run_no_wait(c, workflow, input)
    run_result |> should.be_ok()

    let assert Ok(run_ref) = run_result

    let wait_result = run.await_result(run_ref)

    client.stop_worker(worker)
    process.sleep(500)

    case wait_result {
      Ok(output) -> {
        case decode.run(output, decode.int) {
          Ok(20) -> True
          Ok(_) -> False
          Error(_) -> False
        }
        |> should.be_true()
      }
      Error(_) -> should.be_true(False)
    }
  })
}
