import gleam/dynamic
import gleam/list
import gleam/option
import gleeunit/should
import hatchet/internal/protocol as p
import hatchet/run
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
    |> workflow.task("echo", fn(_ctx) { Ok(dynamic.string("hello")) })

  // Verify workflow structure
  workflow.name
  |> should.equal("test-simple-workflow")

  workflow.version
  |> should.equal(option.Some("1.0.0"))

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
    |> workflow.task("task1", fn(_ctx) { Ok(dynamic.string("output1")) })
    |> workflow.task_after("task2", ["task1"], fn(_ctx) {
      Ok(dynamic.string("output2"))
    })

  let converted: p.WorkflowCreateRequest =
    run.convert_workflow_to_protocol_for_test(workflow)

  // Verify conversion
  converted.name
  |> should.equal("conversion-test")

  converted.version
  |> should.equal(option.Some("1.0.0"))

  list.length(converted.tasks)
  |> should.equal(2)
}
