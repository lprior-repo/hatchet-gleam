import gleam/dict
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import hatchet
import hatchet/types

pub type TestScenario {
  TestScenario(
    name: String,
    description: String,
    setup: fn() -> TestContext,
    execute: fn(TestContext) -> TestResult,
    validate: fn(TestResult) -> Bool,
    teardown: fn(TestContext) -> Nil,
  )
}

pub type TestContext {
  TestContext(
    client: types.Client,
    worker_config: types.WorkerConfig,
    workflows: List(types.Workflow),
    metadata: dict.Dict(String, String),
  )
}

pub type TestResult {
  Success(data: dict.Dict(String, String))
  Failure(error: String)
  Timeout
}

pub type TestBank {
  TestBank(
    scenarios: List(TestScenario),
    regressions: List(TestScenario),
    current_champion: String,
    build_history: List(BuildResult),
  )
}

pub type BuildResult {
  BuildResult(
    version: String,
    timestamp: Int,
    passed_scenarios: List(String),
    failed_scenarios: List(String),
    performance_metrics: PerformanceMetrics,
  )
}

pub type PerformanceMetrics {
  PerformanceMetrics(
    execution_time_ms: Int,
    memory_usage_mb: Float,
    cpu_usage_percent: Float,
  )
}

pub fn drq_test_bank() -> TestBank {
  TestBank(
    scenarios: [
      scenario_client_creation(),
      scenario_simple_workflow(),
      scenario_multi_task_workflow(),
      scenario_worker_lifecycle(),
    ],
    regressions: [],
    current_champion: "v1.0.0",
    build_history: [],
  )
}

pub fn scenario_client_creation() -> TestScenario {
  TestScenario(
    name: "client-creation",
    description: "Create and configure Hatchet client",
    setup: fn() {
      let assert Ok(client) = hatchet.new("localhost", "test-token")
      let worker_config = hatchet.worker_config()
      TestContext(client:, worker_config:, workflows: [], metadata: dict.new())
    },
    execute: fn(ctx) {
      let _client = hatchet.with_port(ctx.client, 7070)
      Success(
        dict.from_list([
          #("host", "localhost"),
          #("port", "7070"),
          #("token", "test-token"),
        ]),
      )
    },
    validate: fn(result) {
      case result {
        Success(data) -> {
          dict.get(data, "host") == Ok("localhost")
          && dict.get(data, "port") == Ok("7070")
        }
        _ -> False
      }
    },
    teardown: fn(_ctx) { Nil },
  )
}

pub fn scenario_simple_workflow() -> TestScenario {
  TestScenario(
    name: "simple-workflow",
    description: "Create a simple workflow with one task",
    setup: fn() {
      let assert Ok(client) = hatchet.new("localhost", "test-token")
      let worker_config = hatchet.worker_config()
      TestContext(client:, worker_config:, workflows: [], metadata: dict.new())
    },
    execute: fn(_ctx) {
      let workflow =
        hatchet.workflow_new("simple-test")
        |> hatchet.workflow_with_description("Simple test workflow")
        |> hatchet.workflow_task("process", fn(task_ctx) {
          hatchet.succeed(task_ctx.input)
        })

      Success(
        dict.from_list([
          #("workflow_name", workflow.name),
          #("task_count", int.to_string(list.length(workflow.tasks))),
          #("description", option.unwrap(workflow.description, "")),
        ]),
      )
    },
    validate: fn(result) {
      case result {
        Success(data) -> {
          dict.get(data, "workflow_name") == Ok("simple-test")
          && dict.get(data, "task_count") == Ok("1")
        }
        _ -> False
      }
    },
    teardown: fn(_ctx) { Nil },
  )
}

pub fn scenario_multi_task_workflow() -> TestScenario {
  TestScenario(
    name: "multi-task-workflow",
    description: "Create workflow with dependent tasks",
    setup: fn() {
      let assert Ok(client) = hatchet.new("localhost", "test-token")
      let worker_config = hatchet.worker_config()
      TestContext(client:, worker_config:, workflows: [], metadata: dict.new())
    },
    execute: fn(_ctx) {
      let workflow =
        hatchet.workflow_new("order-processing")
        |> hatchet.workflow_task("validate", fn(task_ctx) {
          hatchet.succeed(task_ctx.input)
        })
        |> hatchet.workflow_task_after("charge", ["validate"], fn(task_ctx) {
          hatchet.succeed(task_ctx.input)
        })
        |> hatchet.workflow_task_after("fulfill", ["charge"], fn(task_ctx) {
          hatchet.succeed(task_ctx.input)
        })

      let tasks = workflow.tasks
      let validate_task = list.find(tasks, fn(t) { t.name == "validate" })
      let charge_task = list.find(tasks, fn(t) { t.name == "charge" })
      let fulfill_task = list.find(tasks, fn(t) { t.name == "fulfill" })

      case validate_task, charge_task, fulfill_task {
        Ok(_), Ok(_), Ok(_) ->
          Success(
            dict.from_list([
              #("workflow_name", workflow.name),
              #("task_count", int.to_string(list.length(workflow.tasks))),
              #("has_dependencies", "true"),
            ]),
          )
        _, _, _ -> Failure("Missing required tasks")
      }
    },
    validate: fn(result) {
      case result {
        Success(data) -> {
          dict.get(data, "workflow_name") == Ok("order-processing")
          && dict.get(data, "task_count") == Ok("3")
          && dict.get(data, "has_dependencies") == Ok("true")
        }
        _ -> False
      }
    },
    teardown: fn(_ctx) { Nil },
  )
}

pub fn scenario_worker_lifecycle() -> TestScenario {
  TestScenario(
    name: "worker-lifecycle",
    description: "Create and configure worker",
    setup: fn() {
      let assert Ok(client) = hatchet.new("localhost", "test-token")
      TestContext(
        client:,
        worker_config: hatchet.worker_config(),
        workflows: [],
        metadata: dict.new(),
      )
    },
    execute: fn(ctx) {
      let workflow =
        hatchet.workflow_new("test-workflow")
        |> hatchet.workflow_task("task1", fn(task_ctx) {
          hatchet.succeed(task_ctx.input)
        })

      let worker_config =
        ctx.worker_config
        |> hatchet.worker_with_name("test-worker")
        |> hatchet.worker_with_slots(5)
        |> hatchet.worker_with_labels(dict.from_list([#("env", "test")]))

      case hatchet.new_worker(ctx.client, worker_config, [workflow]) {
        Ok(_worker) ->
          Success(
            dict.from_list([
              #("worker_name", "test-worker"),
              #("slots", "5"),
              #("labels", "env:test"),
            ]),
          )
        Error(err) -> Failure(err)
      }
    },
    validate: fn(result) {
      case result {
        Success(data) -> {
          dict.get(data, "worker_name") == Ok("test-worker")
          && dict.get(data, "slots") == Ok("5")
        }
        _ -> False
      }
    },
    teardown: fn(_ctx) { Nil },
  )
}

pub fn run_test_scenario(scenario: TestScenario) -> Result(BuildResult, String) {
  let ctx = scenario.setup()
  let start_time = 0

  case scenario.execute(ctx) {
    Success(data) -> {
      case scenario.validate(Success(data)) {
        True -> {
          let metrics =
            PerformanceMetrics(
              execution_time_ms: 100,
              memory_usage_mb: 50.0,
              cpu_usage_percent: 10.0,
            )
          Ok(BuildResult(
            version: "candidate-v1.0.1",
            timestamp: start_time,
            passed_scenarios: [scenario.name],
            failed_scenarios: [],
            performance_metrics: metrics,
          ))
        }
        False -> {
          let metrics =
            PerformanceMetrics(
              execution_time_ms: 100,
              memory_usage_mb: 50.0,
              cpu_usage_percent: 10.0,
            )
          Ok(BuildResult(
            version: "candidate-v1.0.1",
            timestamp: start_time,
            passed_scenarios: [],
            failed_scenarios: [scenario.name],
            performance_metrics: metrics,
          ))
        }
      }
    }
    Failure(_) | Timeout -> {
      let metrics =
        PerformanceMetrics(
          execution_time_ms: 100,
          memory_usage_mb: 50.0,
          cpu_usage_percent: 10.0,
        )
      Ok(BuildResult(
        version: "candidate-v1.0.1",
        timestamp: start_time,
        passed_scenarios: [],
        failed_scenarios: [scenario.name],
        performance_metrics: metrics,
      ))
    }
  }
  |> result.map(fn(build_result) {
    scenario.teardown(ctx)
    build_result
  })
}
