# DRQ (Dynamic Relative Quality) Framework for Hatchet SDK

This document explains how to use the DRQ framework implemented for the Hatchet distributed task orchestration Gleam SDK.

## Overview

The DRQ framework implements a test evolution system where each candidate implementation must defeat all previous opponents (past builds) by passing an ever-growing set of end-user scenarios. The framework continuously adapts to changing objectives defined by prior opponents.

## Primary End-User Interface

The DRQ framework treats the **Hatchet SDK public API** as the end-user arena:
- Client creation and configuration
- Workflow definition with tasks and dependencies
- Worker lifecycle management  
- Event publishing
- Workflow execution and result handling

## Core Components

### 1. Test Framework (`drq_framework.gleam`)

Provides the basic testing infrastructure:

```gleam
import hatchet/drq_framework

// Create test scenarios
let scenario = drq_framework.scenario_client_creation()

// Run individual scenarios
let result = drq_framework.run_test_scenario(scenario)
```

**Key Types:**
- `TestScenario`: Setup, execute, validate, teardown lifecycle
- `TestContext`: Client, worker config, workflows, metadata
- `TestResult`: Success, Failure, Timeout outcomes
- `TestBank`: Scenarios, regressions, champion, build history

### 2. Evolution Engine (`drq_engine.gleam`)

Manages the DRQ evolution cycles:

```gleam
import hatchet/drq_engine

let engine = drq_engine.new_drq_engine()
let evolution_result = drq_engine.run_evolution_cycle(engine)

// Check if candidate should become champion
let should_promote = drq_engine.should_promote_to_champion(evolution_result)
```

**Evolution Process:**
1. Run all current scenarios against candidate
2. Run same scenarios against champion  
3. Identify defeated opponents (better performance + no failures)
4. Generate new regression tests for failures
5. Calculate performance deltas

### 3. Test Generator (`test_generator.gleam`)

Creates adversarial tests to find edge cases:

```gleam
import hatchet/test_generator

let generator = test_generator.new_test_generator()
let adversarial_tests = test_generator.generate_adversarial_tests(
  generator, 
  ["client-creation"], 
  "v1.0.1"
)
```

**Generated Test Types:**
- **Edge Cases**: Invalid ports, empty tokens, zero slots
- **Stress Tests**: Maximum complexity, circular dependencies
- **Boundary Tests**: Empty dependencies, excessive resources
- **Pattern Matching**: Timeout, memory, validation errors

### 4. Quality Gates (`quality_gates.gleam`)

Implements CI-like quality enforcement:

```gleam
import hatchet/quality_gates

let build = drq_framework.run_test_scenario(scenario)
let gates = quality_gates.default_quality_gates()
let report = quality_gates.run_quality_gates(build, gates)

// Check overall quality gate status
case report.overall_result {
  quality_gates.Pass(_) -> "All gates passed"
  quality_gates.Fail(msg) -> "Quality gate failed: " <> msg
  quality_gates.Skip(_) -> "Quality gate skipped"
}
```

**Quality Gates:**
- **Execution Time**: ≤30 seconds
- **Memory Usage**: ≤512MB  
- **Success Rate**: ≥95%
- **CPU Usage**: ≤80%
- **Test Coverage**: ≥4 scenarios

### 5. Failure Logger (`failure_logger.gleam`)

Provides comprehensive failure analysis and artifact generation:

```gleam
import hatchet/failure_logger

let logger = failure_logger.new_failure_logger("./logs")
let failure_report = failure_logger.log_test_failure(
  logger,
  scenario,
  result,
  build_result
)

// Generate reproduction environment
let repro_env = failure_logger.create_reproducible_test_environment(failure_report)
```

**Failure Analysis:**
- **Classification**: Timeout, memory leak, concurrency, validation, network, corruption
- **Artifacts**: Stdout, stderr, trace, reproduction script
- **Patterns**: Historical failure trend analysis
- **Reproduction**: Step-by-step recreation instructions

## Usage Examples

### Basic DRQ Workflow

```gleam
// 1. Initialize DRQ engine
let engine = drq_engine.new_drq_engine()

// 2. Run evolution cycle
let evolution_result = drq_engine.run_evolution_cycle(engine)

// 3. Check quality gates
let quality_report = quality_gates.run_quality_gates(
  build_result, 
  quality_gates.default_quality_gates()
)

// 4. Generate regression tests for failures
let new_tests = test_generator.generate_adversarial_tests(
  test_generator.new_test_generator(),
  evolution_result.new_tests,
  evolution_result.new_champion
)

// 5. Log any failures for analysis
list.each(evolution_result.failed_scenarios, fn(scenario_name) {
  let report = failure_logger.log_test_failure(logger, scenario, result, build)
  io.println(failure_logger.generate_failure_summary([report]))
})
```

### End-to-End Testing Demo

```gleam
pub fn drq_evolution_demo_test() {
  // Complete workflow from client creation to execution
  let assert Ok(client) = hatchet.new("localhost", "demo-token")
  
  let workflow =
    hatchet.workflow_new("user-registration")
    |> hatchet.workflow_task("validate-email", fn(ctx) { 
      hatchet.succeed(ctx.input) 
    })
    |> hatchet.workflow_task_after("create-user", ["validate-email"], fn(ctx) { 
      hatchet.succeed(ctx.input) 
    })
    |> hatchet.workflow_with_retries(3)
  
  // Run through DRQ framework
  let scenario = drq_framework.scenario_multi_task_workflow()
  let result = drq_framework.run_test_scenario(scenario)
  
  result |> should.be_ok()
}
```

## Evolution Loop Simulation

The framework supports multi-iteration evolution:

```gleam
pub fn run_drq_iterations(iterations: Int) {
  let engine = drq_engine.new_drq_engine()
  
  list.range(1, iterations)
  |> list.fold(engine, fn(current_engine, iteration) {
    io.println("=== Evolution " <> int.to_string(iteration) <> " ===")
    
    let evolution_result = drq_engine.run_evolution_cycle(current_engine)
    
    case drq_engine.should_promote_to_champion(evolution_result) {
      True -> io.println("✅ Candidate promoted")
      False -> io.println("❌ Candidate rejected")
    }
    
    current_engine
  })
}
```

## Key Principles

### 1. Red Queen Objective
The framework constantly moves the target - each new test becomes a permanent opponent, ensuring continuous improvement.

### 2. History-Based Pressure  
All prior builds remain active opponents, creating compound pressure to maintain quality across all dimensions.

### 3. End-User Realism
Tests only use the public SDK surface, ensuring results reflect real user experience.

### 4. Anti-Flake Design
- Deterministic seeds for reproducible failures
- Environment snapshots for exact recreation
- Multiple artifact types for comprehensive debugging

### 5. Quality Gate Enforcement
Hard promotion rules prevent regressions and performance degradation.

## Integration with Existing Tests

The DRQ framework complements existing unit tests:

```gleam
// Traditional unit tests
import gleeunit/should
import hatchet/client_test

pub fn existing_unit_test() {
  client_test.client_creation_test()
}

// DRQ end-to-end tests  
import hatchet/drq_demo_test

pub fn drq_integration_test() {
  drq_demo_test.drq_evolution_demo_test()
}
```

## Running the Framework

```bash
# Run all DRQ tests
gleam test test/hatchet/drq_*.gleam

# Run specific demo
gleam test test/hatchet/drq_demo_test.gleam

# Check code quality
gleam format src test
gleam build
```

## Expected Output

```
Starting DRQ Evolution Demo...
Initial test bank has 4 scenarios
Evolution completed:
  New champion: candidate-v1.0.1
  Defeated opponents: 4
  New tests generated: 0
  Success rate change: 0.0
  Should promote to champion: True

✅ All quality gates passed - candidate can be promoted
```

## Configuration

The framework can be customized by modifying:

- **Test Scenarios**: Add new `TestScenario` definitions
- **Quality Gates**: Adjust thresholds in `default_quality_gates()`
- **Failure Patterns**: Extend `FailurePattern` types
- **Adversarial Tests**: Add new generation patterns

This DRQ implementation provides a robust foundation for continuous quality improvement through competitive test evolution.