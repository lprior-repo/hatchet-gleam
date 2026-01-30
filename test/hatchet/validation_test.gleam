import gleam/option
import gleeunit/should
import hatchet/types.{RateLimitConfig}
import hatchet/workflow

// ============================================================================
// Workflow Name Validation Tests
// These tests document that workflow validation is NOT implemented (CODE SMELL)
// ============================================================================

pub fn empty_workflow_name_rejected_test() {
  // CONTRACT: Empty workflow name should be rejected
  // GIVEN: An attempt to create workflow with empty name
  // WHEN: workflow.new("") is called
  // THEN: Returns Error with validation message
  // NOTE: Currently fails - returns valid workflow with empty name (CODE SMELL)

  let wf = workflow.new("")

  // CODE SMELL: Empty names should be rejected
  // Current behavior: Accepts empty string
  wf.name
  |> should.equal("")

  should.fail()
  // Test indicates validation is missing
}

// ============================================================================
// Cron Expression Validation Tests
// These tests document that cron validation is NOT implemented (CODE SMELL)
// ============================================================================

pub fn invalid_cron_rejected_test() {
  // CONTRACT: Invalid cron expression should be rejected
  // GIVEN: An attempt to set invalid cron expression
  // WHEN: workflow.with_cron(wf, "invalid") is called
  // THEN: Returns Error with validation message
  // NOTE: Currently fails - accepts any string (CODE SMELL)

  let wf = workflow.new("test-workflow")
  let _updated = workflow.with_cron(wf, "invalid")

  // CODE SMELL: Invalid cron should be rejected
  // Current behavior: Accepts any string
  should.fail()
  // Test indicates validation is missing
}

// ============================================================================
// Rate Limit Validation Tests
// These tests document that rate limit validation is NOT implemented (CODE SMELL)
// ============================================================================

pub fn negative_rate_limit_rejected_test() {
  // CONTRACT: Negative rate limit values should be rejected
  // GIVEN: An attempt to set rate limit with negative values
  // WHEN: workflow.with_rate_limit(wf, "key", -1, 60_000) is called
  // THEN: Returns Error with validation message
  // NOTE: Currently fails - accepts negative values (CODE SMELL)

  let wf = workflow.new("test-workflow")
  let _updated = workflow.with_rate_limit(wf, "test-limit", -1, 60_000)

  // CODE SMELL: Negative rate limits should be rejected
  // Current behavior: Accepts negative values
  should.fail()
  // Test indicates validation is missing
}

pub fn valid_values_accepted_test() {
  // CONTRACT: Valid workflow configurations should be accepted
  // GIVEN: Valid workflow configurations
  // WHEN: Creating workflows with valid values
  // THEN: Returns valid Workflow

  let wf1 = workflow.new("test-workflow-1")
  let wf2 = workflow.new("test-workflow-2")
  let wf3 = workflow.new("test-workflow-3")

  // Expected: All valid workflows accepted
  wf1.name
  |> should.equal("test-workflow-1")

  wf2.name
  |> should.equal("test-workflow-2")

  wf3.name
  |> should.equal("test-workflow-3")
}
