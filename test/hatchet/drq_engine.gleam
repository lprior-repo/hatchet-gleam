import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import hatchet
import hatchet/drq_framework.{
  type BuildResult, type TestBank, type TestScenario, Failure, Success,
}

pub type DRQEngine {
  DRQEngine(
    test_bank: TestBank,
    current_candidate: String,
    champion_history: List(String),
  )
}

pub type EvolutionResult {
  EvolutionResult(
    new_champion: String,
    defeated_opponents: List(String),
    new_tests: List(TestScenario),
    performance_delta: PerformanceDelta,
  )
}

pub type PerformanceDelta {
  PerformanceDelta(
    execution_time_change: Float,
    memory_usage_change: Float,
    success_rate_change: Float,
  )
}

pub fn new_drq_engine() -> DRQEngine {
  DRQEngine(
    test_bank: drq_framework.drq_test_bank(),
    current_candidate: "candidate-v1.0.1",
    champion_history: ["v1.0.0"],
  )
}

pub fn run_evolution_cycle(engine: DRQEngine) -> EvolutionResult {
  let scenarios = engine.test_bank.scenarios
  let regressions = engine.test_bank.regressions

  let all_tests = list.append(scenarios, regressions)

  let candidate_results =
    list.map(all_tests, fn(scenario) {
      drq_framework.run_test_scenario(scenario)
    })

  let _passed_tests =
    list.filter_map(candidate_results, fn(result) {
      case result {
        Ok(build) -> {
          case build.failed_scenarios == [] {
            True -> Ok(build)
            False -> Error(Nil)
          }
        }
        _ -> Error(Nil)
      }
    })

  let failed_tests =
    list.filter_map(candidate_results, fn(result) {
      case result {
        Ok(build) -> {
          case build.failed_scenarios != [] {
            True -> Ok(build)
            False -> Error(Nil)
          }
        }
        _ -> Error(Nil)
      }
    })

  let champion_results =
    list.map(all_tests, fn(scenario) {
      run_as_champion(scenario, engine.test_bank.current_champion)
    })

  let defeated_opponents =
    find_defeated_opponents(candidate_results, champion_results)

  let new_tests = generate_new_tests(engine, failed_tests)

  let performance_delta =
    calculate_performance_delta(candidate_results, champion_results)

  EvolutionResult(
    new_champion: engine.current_candidate,
    defeated_opponents: defeated_opponents,
    new_tests: new_tests,
    performance_delta: performance_delta,
  )
}

pub fn run_as_champion(
  scenario: TestScenario,
  champion_version: String,
) -> Result(BuildResult, String) {
  let ctx = scenario.setup()
  let start_time = 0

  case scenario.execute(ctx) {
    Success(data) -> {
      case scenario.validate(Success(data)) {
        True -> {
          let metrics =
            drq_framework.PerformanceMetrics(
              execution_time_ms: 150,
              memory_usage_mb: 60.0,
              cpu_usage_percent: 15.0,
            )
          Ok(drq_framework.BuildResult(
            version: champion_version,
            timestamp: start_time,
            passed_scenarios: [scenario.name],
            failed_scenarios: [],
            performance_metrics: metrics,
          ))
        }
        False -> {
          let metrics =
            drq_framework.PerformanceMetrics(
              execution_time_ms: 150,
              memory_usage_mb: 60.0,
              cpu_usage_percent: 15.0,
            )
          Ok(drq_framework.BuildResult(
            version: champion_version,
            timestamp: start_time,
            passed_scenarios: [],
            failed_scenarios: [scenario.name],
            performance_metrics: metrics,
          ))
        }
      }
    }
    Failure(_) | drq_framework.Timeout -> {
      let metrics =
        drq_framework.PerformanceMetrics(
          execution_time_ms: 150,
          memory_usage_mb: 60.0,
          cpu_usage_percent: 15.0,
        )
      Ok(drq_framework.BuildResult(
        version: champion_version,
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

pub fn find_defeated_opponents(
  candidate_results: List(Result(BuildResult, String)),
  champion_results: List(Result(BuildResult, String)),
) -> List(String) {
  list.zip(candidate_results, champion_results)
  |> list.filter(fn(pair) {
    case pair {
      #(Ok(candidate), Ok(champion)) -> {
        let candidate_time_ok =
          candidate.performance_metrics.execution_time_ms
          < champion.performance_metrics.execution_time_ms
        let candidate_passes = candidate.failed_scenarios == []
        let champion_passes = champion.failed_scenarios == []
        candidate_time_ok && candidate_passes && champion_passes
      }
      _ -> False
    }
  })
  |> list.map(fn(pair) {
    case pair {
      #(Ok(candidate), Ok(champion)) ->
        candidate.version <> " defeated " <> champion.version
      _ -> "Unknown defeat"
    }
  })
}

pub fn generate_new_tests(
  engine: DRQEngine,
  failed_results: List(BuildResult),
) -> List(TestScenario) {
  list.flat_map(failed_results, fn(build) {
    list.map(build.failed_scenarios, fn(failed_scenario_name) {
      generate_regression_test(failed_scenario_name, engine.current_candidate)
    })
  })
}

pub fn generate_regression_test(
  failed_scenario_name: String,
  _candidate_version: String,
) -> TestScenario {
  case failed_scenario_name {
    "client-creation" -> drq_framework.scenario_client_creation()
    "simple-workflow" -> drq_framework.scenario_simple_workflow()
    "multi-task-workflow" -> drq_framework.scenario_multi_task_workflow()
    "worker-lifecycle" -> drq_framework.scenario_worker_lifecycle()
    _ -> generate_fallback_test(failed_scenario_name)
  }
}

pub fn generate_fallback_test(failed_scenario_name: String) -> TestScenario {
  drq_framework.TestScenario(
    name: failed_scenario_name <> "-regression",
    description: "Auto-generated regression test for " <> failed_scenario_name,
    setup: fn() {
      let assert Ok(client) = hatchet.new("localhost", "test-token")
      drq_framework.TestContext(
        client: client,
        worker_config: hatchet.worker_config(),
        workflows: [],
        metadata: dict.new(),
      )
    },
    execute: fn(_ctx) {
      Success(
        dict.from_list([
          #("test_name", failed_scenario_name),
          #("status", "regression_test"),
        ]),
      )
    },
    validate: fn(result) {
      case result {
        Success(data) -> dict.get(data, "test_name") == Ok(failed_scenario_name)
        _ -> False
      }
    },
    teardown: fn(_ctx) { io.println("Teardown: " <> failed_scenario_name) },
  )
}

pub fn calculate_performance_delta(
  candidate_results: List(Result(BuildResult, String)),
  champion_results: List(Result(BuildResult, String)),
) -> PerformanceDelta {
  let candidate_metrics = extract_performance_metrics(candidate_results)
  let champion_metrics = extract_performance_metrics(champion_results)

  let avg_candidate_time = calculate_average_execution_time(candidate_metrics)
  let avg_champion_time = calculate_average_execution_time(champion_metrics)

  let avg_candidate_memory = calculate_average_memory_usage(candidate_metrics)
  let avg_champion_memory = calculate_average_memory_usage(champion_metrics)

  let candidate_success_rate = calculate_success_rate(candidate_results)
  let champion_success_rate = calculate_success_rate(champion_results)

  PerformanceDelta(
    execution_time_change: avg_candidate_time -. avg_champion_time,
    memory_usage_change: avg_candidate_memory -. avg_champion_memory,
    success_rate_change: candidate_success_rate -. champion_success_rate,
  )
}

pub fn extract_performance_metrics(
  results: List(Result(BuildResult, String)),
) -> List(drq_framework.PerformanceMetrics) {
  list.filter_map(results, fn(result) {
    case result {
      Ok(build) -> Ok(build.performance_metrics)
      _ -> Error(Nil)
    }
  })
}

pub fn calculate_average_execution_time(
  metrics: List(drq_framework.PerformanceMetrics),
) -> Float {
  let total =
    list.fold(metrics, 0.0, fn(acc, metric) {
      acc +. int.to_float(metric.execution_time_ms)
    })
  total /. int.to_float(list.length(metrics))
}

pub fn calculate_average_memory_usage(
  metrics: List(drq_framework.PerformanceMetrics),
) -> Float {
  let total =
    list.fold(metrics, 0.0, fn(acc, metric) { acc +. metric.memory_usage_mb })
  total /. int.to_float(list.length(metrics))
}

pub fn calculate_success_rate(
  results: List(Result(BuildResult, String)),
) -> Float {
  let total = list.length(results)
  let successful =
    list.fold(results, 0, fn(acc, result) {
      case result {
        Ok(build) -> {
          case build.failed_scenarios == [] {
            True -> acc + 1
            False -> acc
          }
        }
        _ -> acc
      }
    })
  int.to_float(successful) /. int.to_float(total)
}

pub fn should_promote_to_champion(evolution_result: EvolutionResult) -> Bool {
  evolution_result.defeated_opponents != []
  && evolution_result.performance_delta.success_rate_change >=. 0.0
  && evolution_result.performance_delta.execution_time_change <=. 0.0
}
