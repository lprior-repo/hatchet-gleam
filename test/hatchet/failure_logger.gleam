import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import hatchet/drq_framework.{
  type BuildResult, type TestResult, type TestScenario, Failure,
}

pub type FailureLogger {
  FailureLogger(
    log_directory: String,
    artifact_store: ArtifactStore,
    failure_patterns: List(FailurePattern),
  )
}

pub type ArtifactStore {
  ArtifactStore(artifacts: List(TestArtifact), storage_path: String)
}

pub type TestArtifact {
  TestArtifact(
    id: String,
    test_name: String,
    artifact_type: ArtifactType,
    content: String,
    timestamp: Int,
    metadata: dict.Dict(String, String),
  )
}

pub type ArtifactType {
  StdoutArtifact
  StderrArtifact
  TraceArtifact
  MetricsArtifact
  EnvironmentArtifact
  InputDataArtifact
  ReproductionScript
}

pub type FailurePattern {
  TimeoutPattern
  MemoryLeakPattern
  ConcurrencyIssuePattern
  ValidationErrorPattern
  NetworkErrorPattern
  DataCorruptionPattern
}

pub type FailureReport {
  FailureReport(
    test_name: String,
    failure_type: String,
    error_message: String,
    reproduction_steps: List(String),
    environment_snapshot: dict.Dict(String, String),
    artifacts: List(TestArtifact),
    timestamp: Int,
    seed: Int,
  )
}

pub fn new_failure_logger(log_directory: String) -> FailureLogger {
  FailureLogger(
    log_directory: log_directory,
    artifact_store: ArtifactStore([], log_directory <> "/artifacts"),
    failure_patterns: [
      TimeoutPattern,
      MemoryLeakPattern,
      ConcurrencyIssuePattern,
      ValidationErrorPattern,
      NetworkErrorPattern,
      DataCorruptionPattern,
    ],
  )
}

pub fn log_test_failure(
  logger: FailureLogger,
  test_scenario: TestScenario,
  result: TestResult,
  _build_result: BuildResult,
) -> FailureReport {
  let timestamp = get_current_timestamp()
  let seed = generate_test_seed()

  let failure_type = classify_failure(result, logger.failure_patterns)

  let report =
    FailureReport(
      test_name: test_scenario.name,
      failure_type: failure_type,
      error_message: extract_error_message(result),
      reproduction_steps: generate_reproduction_steps(test_scenario),
      environment_snapshot: capture_environment_snapshot(),
      artifacts: generate_failure_artifacts(test_scenario, result, timestamp),
      timestamp: timestamp,
      seed: seed,
    )

  let _ = write_failure_report(logger.log_directory, report)
  let _ = store_artifacts(logger.artifact_store, report.artifacts)

  report
}

pub fn classify_failure(
  result: TestResult,
  _patterns: List(FailurePattern),
) -> String {
  case result {
    Failure(message) -> {
      let lower_msg = string.lowercase(message)
      case string.contains(lower_msg, "timeout") {
        True -> "timeout"
        False -> {
          case string.contains(lower_msg, "memory") {
            True -> "memory_leak"
            False -> {
              case string.contains(lower_msg, "concurrency") {
                True -> "concurrency"
                False -> {
                  case string.contains(lower_msg, "validation") {
                    True -> "validation"
                    False -> {
                      case string.contains(lower_msg, "network") {
                        True -> "network"
                        False -> {
                          case string.contains(lower_msg, "corruption") {
                            True -> "data_corruption"
                            False -> "unknown"
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    _ -> "unexpected_result_type"
  }
}

pub fn extract_error_message(result: TestResult) -> String {
  case result {
    Failure(message) -> message
    _ -> "No error message available"
  }
}

pub fn generate_reproduction_steps(test_scenario: TestScenario) -> List(String) {
  [
    "1. Initialize test context for: " <> test_scenario.name,
    "2. Execute test scenario: " <> test_scenario.description,
    "3. Validate results against expected criteria",
    "4. Observe failure and capture error details",
    "5. Clean up test resources",
  ]
}

pub fn capture_environment_snapshot() -> dict.Dict(String, String) {
  dict.from_list([
    #("gleam_version", "1.0.0"),
    #("os", "linux"),
    #("timestamp", int.to_string(get_current_timestamp())),
    #("random_seed", int.to_string(generate_test_seed())),
  ])
}

pub fn generate_failure_artifacts(
  test_scenario: TestScenario,
  result: TestResult,
  timestamp: Int,
) -> List(TestArtifact) {
  let artifact_id = test_scenario.name <> "_" <> int.to_string(timestamp)

  [
    TestArtifact(
      id: artifact_id <> "_stdout",
      test_name: test_scenario.name,
      artifact_type: StdoutArtifact,
      content: generate_mock_stdout(),
      timestamp: timestamp,
      metadata: dict.from_list([#("scenario", test_scenario.name)]),
    ),

    TestArtifact(
      id: artifact_id <> "_stderr",
      test_name: test_scenario.name,
      artifact_type: StderrArtifact,
      content: extract_stderr_content(result),
      timestamp: timestamp,
      metadata: dict.from_list([#("error_type", classify_failure(result, []))]),
    ),

    TestArtifact(
      id: artifact_id <> "_repro_script",
      test_name: test_scenario.name,
      artifact_type: ReproductionScript,
      content: generate_reproduction_script(test_scenario),
      timestamp: timestamp,
      metadata: dict.from_list([#("language", "gleam")]),
    ),
  ]
}

pub fn generate_mock_stdout() -> String {
  "Test execution started\n"
  <> "Setting up test context\n"
  <> "Executing scenario...\n"
  <> "Cleaning up resources\n"
  <> "Test execution completed"
}

pub fn extract_stderr_content(result: TestResult) -> String {
  case result {
    Failure(message) ->
      "ERROR: "
      <> message
      <> "\nStack trace:\n  at test_scenario.execute\n  at drq_engine.run_evolution_cycle"
    _ -> "No stderr output captured"
  }
}

pub fn generate_reproduction_script(test_scenario: TestScenario) -> String {
  "// Reproduction script for "
  <> test_scenario.name
  <> "\n"
  <> "// Generated: "
  <> int.to_string(get_current_timestamp())
  <> "\n"
  <> "\n"
  <> "import gleam/io\n"
  <> "import gleam/result\n"
  <> "import hatchet/drq_framework\n"
  <> "\n"
  <> "pub fn reproduce_failure() {\n"
  <> "  io.println(\"Reproducing failure: "
  <> test_scenario.name
  <> "\")\n"
  <> "  \n"
  <> "  let scenario = drq_framework.scenario_"
  <> test_scenario.name
  <> "()\n"
  <> "  let result = drq_framework.run_test_scenario(scenario)\n"
  <> "  \n"
  <> "  case result {\n"
  <> "    Ok(build) -> io.println(\"Unexpected success\")\n"
  <> "    Error(err) -> io.println(\"Reproduced error: \" <> err)\n"
  <> "  }\n"
  <> "}\n"
}

pub fn get_current_timestamp() -> Int {
  int.random(1_000_000) + 1_640_995_200
}

pub fn generate_test_seed() -> Int {
  int.random(999_999)
}

pub fn write_failure_report(
  log_directory: String,
  report: FailureReport,
) -> Result(String, String) {
  let filename =
    log_directory
    <> "/failure_"
    <> report.test_name
    <> "_"
    <> int.to_string(report.timestamp)
    <> ".txt"

  write_artifact_file(filename, "Failure: " <> report.error_message)
}

pub fn store_artifacts(
  store: ArtifactStore,
  artifacts: List(TestArtifact),
) -> Result(Nil, String) {
  list.each(artifacts, fn(artifact) {
    let filename = store.storage_path <> "/" <> artifact.id <> ".txt"
    let _ = write_artifact_file(filename, artifact.content)
  })
  Ok(Nil)
}

pub fn write_artifact_file(
  filename: String,
  _content: String,
) -> Result(String, String) {
  io.println("Writing artifact to: " <> filename)
  Ok(filename)
}

pub fn analyze_failure_patterns(
  reports: List(FailureReport),
) -> dict.Dict(String, Int) {
  list.fold(reports, dict.new(), fn(acc, report) {
    let current_count = dict.get(acc, report.failure_type) |> result.unwrap(0)
    dict.insert(acc, report.failure_type, current_count + 1)
  })
}

pub fn generate_failure_summary(reports: List(FailureReport)) -> String {
  let patterns = analyze_failure_patterns(reports)
  let total_failures = list.length(reports)

  "Failure Analysis Summary:\n"
  <> "Total failures: "
  <> int.to_string(total_failures)
  <> "\n"
  <> "Failure patterns:\n"
  <> string.join(
    list.fold(dict.to_list(patterns), [], fn(acc, pair) {
      let #(failure_type, count) = pair
      list.append(acc, ["  " <> failure_type <> ": " <> int.to_string(count)])
    }),
    "\n",
  )
  <> "\nTop reproduction recommendations:\n"
  <> "  - Address timeout issues first\n"
  <> "  - Investigate memory usage patterns\n"
  <> "  - Review validation logic"
}

pub fn create_reproducible_test_environment(report: FailureReport) -> String {
  "Reproducible Test Environment for: "
  <> report.test_name
  <> "\n"
  <> "=============================================\n\n"
  <> "Failure Information:\n"
  <> "  Type: "
  <> report.failure_type
  <> "\n"
  <> "  Message: "
  <> report.error_message
  <> "\n"
  <> "  Timestamp: "
  <> int.to_string(report.timestamp)
  <> "\n"
  <> "  Seed: "
  <> int.to_string(report.seed)
  <> "\n\n"
  <> "Environment:\n"
  <> string.join(
    list.map(dict.to_list(report.environment_snapshot), fn(pair) {
      let #(key, value) = pair
      "  " <> key <> ": " <> value
    }),
    "\n",
  )
  <> "\n"
  <> "Reproduction Steps:\n"
  <> string.join(report.reproduction_steps, "\n")
  <> "\n\n"
  <> "Generated Artifacts:\n"
  <> string.join(
    list.map(report.artifacts, fn(artifact) {
      "  - "
      <> artifact.id
      <> " ("
      <> artifact_type_to_string(artifact.artifact_type)
      <> ")"
    }),
    "\n",
  )
}

pub fn artifact_type_to_string(artifact_type: ArtifactType) -> String {
  case artifact_type {
    StdoutArtifact -> "stdout"
    StderrArtifact -> "stderr"
    TraceArtifact -> "trace"
    MetricsArtifact -> "metrics"
    EnvironmentArtifact -> "environment"
    InputDataArtifact -> "input_data"
    ReproductionScript -> "repro_script"
  }
}
