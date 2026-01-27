import gleam/bool
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/string
import gleeunit/should
import hatchet
import hatchet/drq_engine
import hatchet/drq_framework

pub fn drq_evolution_demo_test() {
  io.println("Starting DRQ Evolution Demo...")

  let engine = drq_engine.new_drq_engine()

  io.println(
    "Initial test bank has "
    <> int.to_string(list.length(engine.test_bank.scenarios))
    <> " scenarios",
  )

  let evolution_result = drq_engine.run_evolution_cycle(engine)

  io.println("Evolution completed:")
  io.println("  New champion: " <> evolution_result.new_champion)
  io.println(
    "  Defeated opponents: "
    <> int.to_string(list.length(evolution_result.defeated_opponents)),
  )
  io.println(
    "  New tests generated: "
    <> int.to_string(list.length(evolution_result.new_tests)),
  )
  io.println(
    "  Success rate change: "
    <> float.to_string(evolution_result.performance_delta.success_rate_change),
  )

  let should_promote = drq_engine.should_promote_to_champion(evolution_result)
  io.println("  Should promote to champion: " <> bool.to_string(should_promote))

  should_promote
  |> should.equal(True)
}

pub fn end_user_workflow_test() {
  io.println("Testing complete end-user workflow...")

  let assert Ok(client) = hatchet.new("localhost", "demo-token")

  let workflow =
    hatchet.workflow_new("user-registration")
    |> hatchet.workflow_with_description("Complete user registration workflow")
    |> hatchet.workflow_task("validate-email", fn(ctx) {
      hatchet.succeed(ctx.input)
    })
    |> hatchet.workflow_task_after("create-user", ["validate-email"], fn(ctx) {
      hatchet.succeed(ctx.input)
    })
    |> hatchet.workflow_task_after("send-welcome", ["create-user"], fn(ctx) {
      hatchet.succeed(ctx.input)
    })
    |> hatchet.workflow_with_retries(3)
    |> hatchet.workflow_with_timeout(30_000)

  workflow.name
  |> should.equal("user-registration")

  list.length(workflow.tasks)
  |> should.equal(3)

  workflow.description
  |> should.equal(option.Some("Complete user registration workflow"))

  let worker_config =
    hatchet.worker_config()
    |> hatchet.worker_with_name("registration-worker")
    |> hatchet.worker_with_slots(10)

  let assert Ok(_worker) = hatchet.new_worker(client, worker_config, [workflow])

  io.println(
    "Successfully created complete workflow with "
    <> int.to_string(list.length(workflow.tasks))
    <> " tasks",
  )
}

pub fn regression_test_generation_test() {
  io.println("Testing regression test generation...")

  let scenario = drq_framework.scenario_client_creation()
  let result = drq_framework.run_test_scenario(scenario)

  case result {
    Ok(build_result) -> {
      io.println("Scenario result:")
      io.println("  Version: " <> build_result.version)
      io.println(
        "  Passed: "
        <> string.concat(
          list.map(build_result.passed_scenarios, fn(s) { s <> ", " }),
        ),
      )
      io.println(
        "  Failed: "
        <> string.concat(
          list.map(build_result.failed_scenarios, fn(s) { s <> ", " }),
        ),
      )

      list.length(build_result.passed_scenarios)
      + list.length(build_result.failed_scenarios)
      |> should.equal(1)
    }
    Error(err) -> {
      io.println("Test execution failed: " <> err)
      True |> should.equal(False)
    }
  }
}

pub fn performance_metrics_test() {
  io.println("Testing performance metrics collection...")

  let scenario = drq_framework.scenario_simple_workflow()
  let result = drq_framework.run_test_scenario(scenario)

  case result {
    Ok(build_result) -> {
      let metrics = build_result.performance_metrics

      metrics.execution_time_ms
      |> should.equal(100)

      metrics.memory_usage_mb
      |> should.equal(50.0)

      metrics.cpu_usage_percent
      |> should.equal(10.0)

      io.println("Performance metrics collected:")
      io.println(
        "  Execution time: " <> int.to_string(metrics.execution_time_ms) <> "ms",
      )
      io.println(
        "  Memory usage: " <> float.to_string(metrics.memory_usage_mb) <> "MB",
      )
      io.println(
        "  CPU usage: " <> float.to_string(metrics.cpu_usage_percent) <> "%",
      )
    }
    Error(_) -> True |> should.equal(False)
  }
}

pub fn drq_quality_gates_test() {
  io.println("Testing DRQ quality gates...")

  let engine = drq_engine.new_drq_engine()
  let evolution_result = drq_engine.run_evolution_cycle(engine)

  let passes_all_gates = drq_engine.should_promote_to_champion(evolution_result)

  case passes_all_gates {
    True -> io.println("✅ All quality gates passed - candidate can be promoted")
    False -> io.println("❌ Quality gates failed - candidate rejected")
  }

  passes_all_gates
  |> should.equal(True)
}

pub fn test_evolution_loop_simulation() {
  io.println("Running multi-iteration evolution loop simulation...")

  let engine = drq_engine.new_drq_engine()

  let final_state =
    list.range(1, 3)
    |> list.fold(engine, fn(current_engine, iteration) {
      io.println(
        "\n=== Evolution Iteration " <> int.to_string(iteration) <> " ===",
      )

      let evolution_result = drq_engine.run_evolution_cycle(current_engine)

      io.println(
        "Defeated "
        <> int.to_string(list.length(evolution_result.defeated_opponents))
        <> " opponents",
      )
      io.println(
        "Generated "
        <> int.to_string(list.length(evolution_result.new_tests))
        <> " new regression tests",
      )

      case drq_engine.should_promote_to_champion(evolution_result) {
        True -> io.println("✅ Candidate promoted to champion")
        False -> io.println("❌ Candidate rejected")
      }

      current_engine
    })

  io.println("\n=== Evolution Loop Complete ===")
  io.println("Final champion: " <> final_state.current_candidate)

  final_state.current_candidate
  |> should.equal("candidate-v1.0.1")
}
