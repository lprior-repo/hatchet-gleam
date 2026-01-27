import gleam/float
import gleam/int
import gleam/list
import gleam/string
import hatchet/drq_framework.{type BuildResult}

pub type QualityGate {
  QualityGate(
    name: String,
    description: String,
    validator: fn(BuildResult) -> GateResult,
    threshold: Threshold,
  )
}

pub type Threshold {
  TimeoutThreshold(max_ms: Int)
  MemoryThreshold(max_mb: Float)
  LatencyThreshold(max_ms: Int)
  SuccessRateThreshold(min_rate: Float)
  ThroughputThreshold(min_ops_per_sec: Float)
  ErrorRateThreshold(max_rate: Float)
}

pub type GateResult {
  Pass(message: String)
  Fail(message: String)
  Skip(reason: String)
}

pub type QualityGateReport {
  QualityGateReport(
    build_id: String,
    timestamp: Int,
    gates: List(GateEvaluation),
    overall_result: GateResult,
    recommendations: List(String),
  )
}

pub type GateEvaluation {
  GateEvaluation(
    gate_name: String,
    result: GateResult,
    measured_value: String,
    threshold_value: String,
  )
}

pub fn default_quality_gates() -> List(QualityGate) {
  [
    QualityGate(
      name: "execution-time",
      description: "Test execution must complete within acceptable time limits",
      validator: fn(build) { validate_execution_time(build) },
      threshold: TimeoutThreshold(30_000),
    ),

    QualityGate(
      name: "memory-usage",
      description: "Memory usage must stay within reasonable limits",
      validator: fn(build) { validate_memory_usage(build) },
      threshold: MemoryThreshold(512.0),
    ),

    QualityGate(
      name: "success-rate",
      description: "Tests must maintain minimum success rate",
      validator: fn(build) { validate_success_rate(build) },
      threshold: SuccessRateThreshold(0.95),
    ),

    QualityGate(
      name: "cpu-usage",
      description: "CPU usage must not exceed maximum threshold",
      validator: fn(build) { validate_cpu_usage(build) },
      threshold: LatencyThreshold(80),
    ),

    QualityGate(
      name: "test-coverage",
      description: "Test coverage must meet minimum requirements",
      validator: fn(build) { validate_test_coverage(build) },
      threshold: ThroughputThreshold(0.8),
    ),
  ]
}

pub fn validate_execution_time(build: BuildResult) -> GateResult {
  let metrics = build.performance_metrics
  case metrics.execution_time_ms <= 30_000 {
    True -> {
      Pass("Execution time within acceptable limits")
    }
    False -> {
      Fail(
        "Execution time exceeded 30 seconds: "
        <> int.to_string(metrics.execution_time_ms)
        <> "ms",
      )
    }
  }
}

pub fn validate_memory_usage(build: BuildResult) -> GateResult {
  let metrics = build.performance_metrics
  case metrics.memory_usage_mb <=. 512.0 {
    True -> {
      Pass("Memory usage within acceptable limits")
    }
    False -> {
      Fail(
        "Memory usage exceeded 512MB: "
        <> string.append(float.to_string(metrics.memory_usage_mb), "MB"),
      )
    }
  }
}

pub fn validate_success_rate(build: BuildResult) -> GateResult {
  let total_tests =
    list.length(build.passed_scenarios) + list.length(build.failed_scenarios)
  case total_tests > 0 {
    True -> {
      let success_rate =
        int.to_float(list.length(build.passed_scenarios))
        /. int.to_float(total_tests)
      case success_rate >=. 0.95 {
        True -> {
          Pass(
            "Success rate acceptable: "
            <> float.to_string(success_rate *. 100.0)
            <> "%",
          )
        }
        False -> {
          Fail(
            "Success rate too low: "
            <> float.to_string(success_rate *. 100.0)
            <> "%",
          )
        }
      }
    }
    False -> Skip("No tests to evaluate")
  }
}

pub fn validate_cpu_usage(build: BuildResult) -> GateResult {
  let metrics = build.performance_metrics
  case metrics.cpu_usage_percent <=. 80.0 {
    True -> {
      Pass("CPU usage within acceptable limits")
    }
    False -> {
      Fail(
        "CPU usage exceeded 80%: "
        <> float.to_string(metrics.cpu_usage_percent)
        <> "%",
      )
    }
  }
}

pub fn validate_test_coverage(build: BuildResult) -> GateResult {
  let total_scenarios =
    list.length(build.passed_scenarios) + list.length(build.failed_scenarios)
  case total_scenarios >= 4 {
    True -> {
      Pass("Test coverage meets minimum requirements")
    }
    False -> {
      Fail(
        "Insufficient test coverage: "
        <> int.to_string(total_scenarios)
        <> " scenarios",
      )
    }
  }
}

pub fn run_quality_gates(
  build: BuildResult,
  gates: List(QualityGate),
) -> QualityGateReport {
  let evaluations =
    list.map(gates, fn(gate) {
      let result = gate.validator(build)
      let measured_value = extract_measured_value(build, gate.name)
      let threshold_value = extract_threshold_value(gate.threshold)

      GateEvaluation(
        gate_name: gate.name,
        result: result,
        measured_value: measured_value,
        threshold_value: threshold_value,
      )
    })

  let failed_gates =
    list.filter(evaluations, fn(eval) {
      case eval.result {
        Fail(_) -> True
        _ -> False
      }
    })

  let overall_result = case list.length(failed_gates) {
    0 -> Pass("All quality gates passed")
    _ ->
      Fail(int.to_string(list.length(failed_gates)) <> " quality gates failed")
  }

  let recommendations = generate_recommendations(evaluations)

  QualityGateReport(
    build_id: build.version,
    timestamp: build.timestamp,
    gates: evaluations,
    overall_result: overall_result,
    recommendations: recommendations,
  )
}

pub fn extract_measured_value(build: BuildResult, gate_name: String) -> String {
  case gate_name {
    "execution-time" ->
      int.to_string(build.performance_metrics.execution_time_ms) <> "ms"
    "memory-usage" ->
      float.to_string(build.performance_metrics.memory_usage_mb) <> "MB"
    "cpu-usage" ->
      float.to_string(build.performance_metrics.cpu_usage_percent) <> "%"
    "success-rate" -> {
      let total =
        list.length(build.passed_scenarios)
        + list.length(build.failed_scenarios)
      case total > 0 {
        True -> {
          let rate =
            int.to_float(list.length(build.passed_scenarios))
            /. int.to_float(total)
          float.to_string(rate *. 100.0) <> "%"
        }
        False -> "N/A"
      }
    }
    "test-coverage" -> {
      let total =
        list.length(build.passed_scenarios)
        + list.length(build.failed_scenarios)
      int.to_string(total) <> " scenarios"
    }
    _ -> "Unknown"
  }
}

pub fn extract_threshold_value(threshold: Threshold) -> String {
  case threshold {
    TimeoutThreshold(max_ms) -> int.to_string(max_ms) <> "ms"
    MemoryThreshold(max_mb) -> float.to_string(max_mb) <> "MB"
    LatencyThreshold(max_ms) -> int.to_string(max_ms) <> "ms"
    SuccessRateThreshold(min_rate) -> float.to_string(min_rate *. 100.0) <> "%"
    ThroughputThreshold(min_ops) -> float.to_string(min_ops)
    ErrorRateThreshold(max_rate) -> float.to_string(max_rate *. 100.0) <> "%"
  }
}

pub fn generate_recommendations(
  evaluations: List(GateEvaluation),
) -> List(String) {
  list.filter_map(evaluations, fn(eval) {
    case eval.result {
      Fail(_message) -> {
        let recommendation = case eval.gate_name {
          "execution-time" ->
            "Consider optimizing test execution or increasing timeout limits"
          "memory-usage" ->
            "Investigate memory leaks or optimize data structures"
          "success-rate" -> "Fix failing tests and improve test reliability"
          "cpu-usage" -> "Optimize CPU-intensive operations or add delays"
          "test-coverage" -> "Add more test scenarios to improve coverage"
          _ -> "Review and address quality gate failure"
        }
        Ok(recommendation)
      }
      _ -> Error(Nil)
    }
  })
}

pub fn should_promote_candidate(report: QualityGateReport) -> Bool {
  case report.overall_result {
    Pass(_) -> True
    Fail(_) -> {
      let critical_failures =
        list.filter(report.gates, fn(eval) {
          case eval.result {
            Fail(_) -> {
              list.contains(
                ["execution-time", "memory-usage", "success-rate"],
                eval.gate_name,
              )
            }
            _ -> False
          }
        })
      critical_failures == []
    }
    Skip(_) -> False
  }
}

pub fn ci_quality_gate_pipeline(
  builds: List(BuildResult),
) -> List(QualityGateReport) {
  let gates = default_quality_gates()
  list.map(builds, fn(build) { run_quality_gates(build, gates) })
}

pub fn generate_quality_summary(reports: List(QualityGateReport)) -> String {
  let total_builds = list.length(reports)
  let passed_builds =
    list.count(reports, fn(report) {
      case report.overall_result {
        Pass(_) -> True
        _ -> False
      }
    })

  let success_rate = int.to_float(passed_builds) /. int.to_float(total_builds)

  "Quality Gate Summary:\n"
  <> "  Total builds: "
  <> int.to_string(total_builds)
  <> "\n"
  <> "  Passed: "
  <> int.to_string(passed_builds)
  <> "\n"
  <> "  Failed: "
  <> int.to_string(total_builds - passed_builds)
  <> "\n"
  <> "  Success rate: "
  <> float.to_string(success_rate *. 100.0)
  <> "%\n"
}
