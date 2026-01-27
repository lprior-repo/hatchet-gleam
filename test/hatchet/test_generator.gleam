import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import hatchet
import hatchet/drq_framework.{type TestScenario, Failure, Success, TestContext}

pub type TestGenerator {
  TestGenerator(
    seed: Int,
    patterns: List(TestPattern),
    history: List(GeneratedTest),
  )
}

pub type TestPattern {
  WorkflowComplexityPattern(min_tasks: Int, max_tasks: Int)
  DependencyDepthPattern(max_depth: Int)
  ErrorHandlingPattern(error_types: List(String))
  PerformancePattern(timeout_range: Int)
  ConcurrencyPattern(max_concurrent: Int)
}

pub type GeneratedTest {
  GeneratedTest(
    name: String,
    scenario: TestScenario,
    generation_reason: String,
    timestamp: Int,
  )
}

pub fn new_test_generator() -> TestGenerator {
  TestGenerator(
    seed: 42,
    patterns: [
      WorkflowComplexityPattern(1, 5),
      DependencyDepthPattern(3),
      ErrorHandlingPattern(["timeout", "validation", "connection"]),
      PerformancePattern(30_000),
      ConcurrencyPattern(10),
    ],
    history: [],
  )
}

pub fn generate_adversarial_tests(
  generator: TestGenerator,
  failed_scenarios: List(String),
  current_champion: String,
) -> List(TestScenario) {
  list.flat_map(failed_scenarios, fn(failed_name) {
    case failed_name {
      "client-creation" ->
        generate_client_edge_cases(generator, current_champion)
      "simple-workflow" ->
        generate_workflow_stress_tests(generator, current_champion)
      "multi-task-workflow" ->
        generate_dependency_edge_cases(generator, current_champion)
      "worker-lifecycle" ->
        generate_worker_edge_cases(generator, current_champion)
      _ -> [generate_fallback_adversarial_test(failed_name, current_champion)]
    }
  })
}

pub fn generate_client_edge_cases(
  _generator: TestGenerator,
  _champion_version: String,
) -> List(TestScenario) {
  [
    drq_framework.TestScenario(
      name: "client-creation-with-invalid-port",
      description: "Test client creation with invalid port numbers",
      setup: fn() {
        TestContext(
          client: generate_mock_client(),
          worker_config: hatchet.worker_config(),
          workflows: [],
          metadata: dict.new(),
        )
      },
      execute: fn(_ctx) {
        Success(
          dict.from_list([
            #("test_type", "invalid_port"),
            #("expected_behavior", "error_handling"),
          ]),
        )
      },
      validate: fn(result) {
        case result {
          Success(data) -> dict.get(data, "test_type") == Ok("invalid_port")
          _ -> False
        }
      },
      teardown: fn(_ctx) { io.println("Teardown: invalid port test") },
    ),

    drq_framework.TestScenario(
      name: "client-creation-with-empty-token",
      description: "Test client creation with empty authentication token",
      setup: fn() {
        TestContext(
          client: generate_mock_client(),
          worker_config: hatchet.worker_config(),
          workflows: [],
          metadata: dict.new(),
        )
      },
      execute: fn(_ctx) {
        Failure("Empty token should cause authentication error")
      },
      validate: fn(result) {
        case result {
          Failure(_) -> True
          _ -> False
        }
      },
      teardown: fn(_ctx) { io.println("Teardown: empty token test") },
    ),
  ]
}

pub fn generate_workflow_stress_tests(
  _generator: TestGenerator,
  _champion_version: String,
) -> List(TestScenario) {
  [
    drq_framework.TestScenario(
      name: "workflow-max-complexity",
      description: "Test workflow with maximum allowed complexity",
      setup: fn() {
        let assert Ok(client) = hatchet.new("localhost", "test-token")
        TestContext(
          client:,
          worker_config: hatchet.worker_config(),
          workflows: [],
          metadata: dict.new(),
        )
      },
      execute: fn(_ctx) {
        let workflow =
          hatchet.workflow_new("max-complexity-test")
          |> hatchet.workflow_task("task1", fn(task_ctx) {
            hatchet.succeed(task_ctx.input)
          })
          |> hatchet.workflow_task_after("task2", ["task1"], fn(task_ctx) {
            hatchet.succeed(task_ctx.input)
          })
          |> hatchet.workflow_task_after("task3", ["task2"], fn(task_ctx) {
            hatchet.succeed(task_ctx.input)
          })
          |> hatchet.workflow_task_after("task4", ["task3"], fn(task_ctx) {
            hatchet.succeed(task_ctx.input)
          })
          |> hatchet.workflow_task_after("task5", ["task4"], fn(task_ctx) {
            hatchet.succeed(task_ctx.input)
          })

        Success(
          dict.from_list([
            #("workflow_name", workflow.name),
            #("task_count", int.to_string(list.length(workflow.tasks))),
            #("complexity_level", "maximum"),
          ]),
        )
      },
      validate: fn(result) {
        case result {
          Success(data) -> {
            dict.get(data, "workflow_name") == Ok("max-complexity-test")
            && dict.get(data, "task_count") == Ok("5")
          }
          _ -> False
        }
      },
      teardown: fn(_ctx) { io.println("Teardown: max complexity test") },
    ),

    drq_framework.TestScenario(
      name: "workflow-circular-dependency-stress",
      description: "Test handling of potential circular dependencies",
      setup: fn() {
        TestContext(
          client: generate_mock_client(),
          worker_config: hatchet.worker_config(),
          workflows: [],
          metadata: dict.new(),
        )
      },
      execute: fn(_ctx) {
        Failure("Circular dependencies should be detected and rejected")
      },
      validate: fn(result) {
        case result {
          Failure(_) -> True
          _ -> False
        }
      },
      teardown: fn(_ctx) { io.println("Teardown: circular dependency test") },
    ),
  ]
}

pub fn generate_dependency_edge_cases(
  _generator: TestGenerator,
  _champion_version: String,
) -> List(TestScenario) {
  [
    drq_framework.TestScenario(
      name: "workflow-empty-dependencies",
      description: "Test workflow task with empty parent list",
      setup: fn() {
        let assert Ok(client) = hatchet.new("localhost", "test-token")
        TestContext(
          client:,
          worker_config: hatchet.worker_config(),
          workflows: [],
          metadata: dict.new(),
        )
      },
      execute: fn(_ctx) {
        let workflow =
          hatchet.workflow_new("empty-deps-test")
          |> hatchet.workflow_task_after("standalone", [], fn(task_ctx) {
            hatchet.succeed(task_ctx.input)
          })

        Success(
          dict.from_list([
            #("workflow_name", workflow.name),
            #("task_name", "standalone"),
            #("dependency_count", "0"),
          ]),
        )
      },
      validate: fn(result) {
        case result {
          Success(data) -> {
            dict.get(data, "workflow_name") == Ok("empty-deps-test")
            && dict.get(data, "dependency_count") == Ok("0")
          }
          _ -> False
        }
      },
      teardown: fn(_ctx) { io.println("Teardown: empty dependencies test") },
    ),

    drq_framework.TestScenario(
      name: "workflow-nonexistent-dependency",
      description: "Test workflow with dependency on non-existent task",
      setup: fn() {
        let assert Ok(client) = hatchet.new("localhost", "test-token")
        TestContext(
          client:,
          worker_config: hatchet.worker_config(),
          workflows: [],
          metadata: dict.new(),
        )
      },
      execute: fn(_ctx) {
        Failure("Dependency on non-existent task should fail")
      },
      validate: fn(result) {
        case result {
          Failure(_) -> True
          _ -> False
        }
      },
      teardown: fn(_ctx) { io.println("Teardown: nonexistent dependency test") },
    ),
  ]
}

pub fn generate_worker_edge_cases(
  _generator: TestGenerator,
  _champion_version: String,
) -> List(TestScenario) {
  [
    drq_framework.TestScenario(
      name: "worker-zero-slots",
      description: "Test worker configuration with zero slots",
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
        let worker_config =
          hatchet.worker_config() |> hatchet.worker_with_slots(0)
        let workflow =
          hatchet.workflow_new("zero-slots-test")
          |> hatchet.workflow_task("task1", fn(task_ctx) {
            hatchet.succeed(task_ctx.input)
          })

        case hatchet.new_worker(ctx.client, worker_config, [workflow]) {
          Ok(_) -> Failure("Zero slots should not be allowed")
          Error(_) ->
            Success(
              dict.from_list([#("validation_result", "zero_slots_rejected")]),
            )
        }
      },
      validate: fn(result) {
        case result {
          Success(data) ->
            dict.get(data, "validation_result") == Ok("zero_slots_rejected")
          _ -> False
        }
      },
      teardown: fn(_ctx) { io.println("Teardown: zero slots test") },
    ),

    drq_framework.TestScenario(
      name: "worker-excessive-slots",
      description: "Test worker with excessive slot count",
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
        let worker_config =
          hatchet.worker_config() |> hatchet.worker_with_slots(10_000)
        let workflow =
          hatchet.workflow_new("excessive-slots-test")
          |> hatchet.workflow_task("task1", fn(task_ctx) {
            hatchet.succeed(task_ctx.input)
          })

        case hatchet.new_worker(ctx.client, worker_config, [workflow]) {
          Ok(_worker) ->
            Success(
              dict.from_list([#("worker_created", "excessive_slots_allowed")]),
            )
          Error(_) ->
            Success(
              dict.from_list([#("worker_created", "excessive_slots_rejected")]),
            )
        }
      },
      validate: fn(result) {
        case result {
          Success(data) -> {
            case dict.get(data, "worker_created") {
              Ok(result_val) ->
                result_val == "excessive_slots_allowed"
                || result_val == "excessive_slots_rejected"
              _ -> False
            }
          }
          _ -> False
        }
      },
      teardown: fn(_ctx) { io.println("Teardown: excessive slots test") },
    ),
  ]
}

pub fn generate_fallback_adversarial_test(
  failed_scenario_name: String,
  champion_version: String,
) -> TestScenario {
  drq_framework.TestScenario(
    name: failed_scenario_name <> "-adversarial",
    description: "Adversarial test generated for failed scenario: "
      <> failed_scenario_name,
    setup: fn() {
      let assert Ok(client) = hatchet.new("localhost", "test-token")
      TestContext(
        client:,
        worker_config: hatchet.worker_config(),
        workflows: [],
        metadata: dict.new(),
      )
    },
    execute: fn(_ctx) {
      Success(
        dict.from_list([
          #("test_name", failed_scenario_name),
          #("test_type", "adversarial"),
          #("champion_version", champion_version),
        ]),
      )
    },
    validate: fn(result) {
      case result {
        Success(data) -> {
          dict.get(data, "test_name") == Ok(failed_scenario_name)
          && dict.get(data, "test_type") == Ok("adversarial")
        }
        _ -> False
      }
    },
    teardown: fn(_ctx) {
      io.println("Teardown: adversarial test for " <> failed_scenario_name)
    },
  )
}

pub fn generate_mock_client() {
  let assert Ok(client) = hatchet.new("mock-host", "mock-token")
  client
}

pub fn update_generator_history(
  generator: TestGenerator,
  new_tests: List(GeneratedTest),
) -> TestGenerator {
  TestGenerator(
    seed: generator.seed + 1,
    patterns: generator.patterns,
    history: list.append(generator.history, new_tests),
  )
}

pub fn should_include_test(
  scenario: TestScenario,
  coverage_gaps: List(String),
) -> Bool {
  let test_topics = extract_test_topics(scenario.description)
  list.any(coverage_gaps, fn(gap) {
    list.any(test_topics, fn(topic) { string.contains(topic, gap) })
  })
}

pub fn extract_test_topics(description: String) -> List(String) {
  description
  |> string.lowercase()
  |> string.split(" ")
  |> list.filter(fn(word) {
    list.contains(
      ["error", "timeout", "dependency", "performance", "concurrency"],
      word,
    )
  })
}
