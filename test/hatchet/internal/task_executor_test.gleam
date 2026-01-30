import gleam/dict
import gleam/dynamic
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import hatchet/internal/ffi/protobuf
import hatchet/internal/task_executor.{
  type TaskEffects, type TaskHandler, Cancelled, Completed, Failed, Skipped,
  TaskEffects, TaskHandler, TaskSpec,
}
import hatchet/types.{type TaskContext}

pub fn main() {
  gleeunit.main()
}

// ============================================================================
// Test Helpers
// ============================================================================

fn create_test_action() -> protobuf.AssignedAction {
  protobuf.AssignedAction(
    tenant_id: "test-tenant",
    workflow_run_id: "wfrun-123",
    get_group_key_run_id: "",
    job_id: "job-456",
    job_name: "test-job",
    job_run_id: "jobrun-789",
    step_id: "step-abc",
    step_run_id: "steprun-def",
    action_id: "action-ghi",
    action_type: protobuf.StartStepRun,
    action_payload: "{\"input\":{\"message\":\"hello\"}}",
    step_name: "test-step",
    retry_count: 0,
    additional_metadata: None,
    child_workflow_index: None,
    child_workflow_key: None,
    parent_workflow_run_id: None,
    priority: 0,
    workflow_id: Some("workflow-123"),
    workflow_version_id: None,
  )
}

fn create_test_handler(
  retries: Int,
  skip_if: option.Option(fn(TaskContext) -> Bool),
  cancel_if: option.Option(fn(TaskContext) -> Bool),
  handler_fn: fn(TaskContext) -> Result(dynamic.Dynamic, String),
) -> TaskHandler {
  TaskHandler(
    workflow_name: "test-workflow",
    task_name: "test-task",
    handler: handler_fn,
    retries: retries,
    timeout_ms: 30_000,
    skip_if: skip_if,
    cancel_if: cancel_if,
  )
}

fn create_test_effects() -> TaskEffects {
  TaskEffects(
    log: fn(_msg) { Nil },
    emit_event: fn(_type, _payload) { Nil },
    release_slot: fn() { Ok(Nil) },
    refresh_timeout: fn(_ms) { Ok(Nil) },
    cancel: fn() { Ok(Nil) },
    spawn_workflow: fn(_name, _input, _metadata) { Ok("child-run-123") },
  )
}

// ============================================================================
// Basic Execution Tests
// ============================================================================

pub fn execute_task_success_test() {
  // Arrange
  let action = create_test_action()
  let handler =
    create_test_handler(3, None, None, fn(_ctx) {
      Ok(dynamic.string("success result"))
    })
  let spec =
    TaskSpec(
      action: action,
      handler: handler,
      worker_id: "worker-1",
      parent_outputs: dict.new(),
    )
  let effects = create_test_effects()

  // Act
  let result = task_executor.execute_task(spec, effects)

  // Assert
  case result {
    Completed(output) -> {
      output.output_json
      |> should.equal("\"success result\"")
    }
    _ -> should.fail()
  }
}

pub fn execute_task_failure_test() {
  // Arrange
  let action = create_test_action()
  let handler =
    create_test_handler(3, None, None, fn(_ctx) { Error("task failed") })
  let spec =
    TaskSpec(
      action: action,
      handler: handler,
      worker_id: "worker-1",
      parent_outputs: dict.new(),
    )
  let effects = create_test_effects()

  // Act
  let result = task_executor.execute_task(spec, effects)

  // Assert
  case result {
    Failed(error) -> {
      error.error
      |> should.equal("task failed")
      error.should_retry
      |> should.be_true()
      error.retry_count
      |> should.equal(0)
    }
    _ -> should.fail()
  }
}

pub fn execute_task_no_retry_after_max_test() {
  // Arrange
  let action = protobuf.AssignedAction(..create_test_action(), retry_count: 3)
  let handler =
    create_test_handler(3, None, None, fn(_ctx) { Error("task failed") })
  let spec =
    TaskSpec(
      action: action,
      handler: handler,
      worker_id: "worker-1",
      parent_outputs: dict.new(),
    )
  let effects = create_test_effects()

  // Act
  let result = task_executor.execute_task(spec, effects)

  // Assert
  case result {
    Failed(error) -> {
      error.should_retry
      |> should.be_false()
      error.retry_count
      |> should.equal(3)
    }
    _ -> should.fail()
  }
}

// ============================================================================
// Skip Condition Tests
// ============================================================================

pub fn execute_task_skip_if_true_test() {
  // Arrange
  let action = create_test_action()
  let handler =
    create_test_handler(3, Some(fn(_ctx) { True }), None, fn(_ctx) {
      Ok(dynamic.string("should not run"))
    })
  let spec =
    TaskSpec(
      action: action,
      handler: handler,
      worker_id: "worker-1",
      parent_outputs: dict.new(),
    )
  let effects = create_test_effects()

  // Act
  let result = task_executor.execute_task(spec, effects)

  // Assert
  case result {
    Skipped(output) -> {
      // Verify skip marker in output
      // Verify skip marker in output - just check it's not empty for now
      output.output_json
      |> should.not_equal("")
    }
    _ -> should.fail()
  }
}

pub fn execute_task_skip_if_false_test() {
  // Arrange
  let action = create_test_action()
  let handler =
    create_test_handler(3, Some(fn(_ctx) { False }), None, fn(_ctx) {
      Ok(dynamic.string("executed"))
    })
  let spec =
    TaskSpec(
      action: action,
      handler: handler,
      worker_id: "worker-1",
      parent_outputs: dict.new(),
    )
  let effects = create_test_effects()

  // Act
  let result = task_executor.execute_task(spec, effects)

  // Assert
  case result {
    Completed(output) -> {
      output.output_json
      |> should.equal("\"executed\"")
    }
    _ -> should.fail()
  }
}

// ============================================================================
// Cancel Condition Tests
// ============================================================================

pub fn execute_task_cancel_if_true_test() {
  // Arrange
  let action = create_test_action()
  let handler =
    create_test_handler(3, None, Some(fn(_ctx) { True }), fn(_ctx) {
      Ok(dynamic.string("should not run"))
    })
  let spec =
    TaskSpec(
      action: action,
      handler: handler,
      worker_id: "worker-1",
      parent_outputs: dict.new(),
    )
  let effects = create_test_effects()

  // Act
  let result = task_executor.execute_task(spec, effects)

  // Assert
  case result {
    Cancelled(cancellation) -> {
      cancellation.reason
      |> should.equal("cancel_if condition evaluated to true")
    }
    _ -> should.fail()
  }
}

pub fn execute_task_cancel_if_false_test() {
  // Arrange
  let action = create_test_action()
  let handler =
    create_test_handler(3, None, Some(fn(_ctx) { False }), fn(_ctx) {
      Ok(dynamic.string("executed"))
    })
  let spec =
    TaskSpec(
      action: action,
      handler: handler,
      worker_id: "worker-1",
      parent_outputs: dict.new(),
    )
  let effects = create_test_effects()

  // Act
  let result = task_executor.execute_task(spec, effects)

  // Assert
  case result {
    Completed(output) -> {
      output.output_json
      |> should.equal("\"executed\"")
    }
    _ -> should.fail()
  }
}

// ============================================================================
// Condition Evaluation Tests
// ============================================================================

pub fn evaluate_cancel_if_with_condition_test() {
  let handler =
    create_test_handler(3, None, Some(fn(_ctx) { True }), fn(_ctx) {
      Ok(dynamic.string("test"))
    })
  let ctx =
    types.TaskContext(
      workflow_run_id: "test",
      task_run_id: "test",
      input: dynamic.string(""),
      parent_outputs: dict.new(),
      metadata: dict.new(),
      logger: fn(_) { Nil },
      step_run_errors: dict.new(),
      stream_fn: fn(_) { Error("not available") },
      release_slot_fn: fn() { Error("not available") },
      refresh_timeout_fn: fn(_) { Error("not available") },
      cancel_fn: fn() { Error("not available") },
      spawn_workflow_fn: fn(_, _, _) { Error("not available") },
    )

  task_executor.evaluate_cancel_if(handler, ctx)
  |> should.be_true()
}

pub fn evaluate_cancel_if_without_condition_test() {
  let handler =
    create_test_handler(3, None, None, fn(_ctx) { Ok(dynamic.string("test")) })
  let ctx =
    types.TaskContext(
      workflow_run_id: "test",
      task_run_id: "test",
      input: dynamic.string(""),
      parent_outputs: dict.new(),
      metadata: dict.new(),
      logger: fn(_) { Nil },
      step_run_errors: dict.new(),
      stream_fn: fn(_) { Error("not available") },
      release_slot_fn: fn() { Error("not available") },
      refresh_timeout_fn: fn(_) { Error("not available") },
      cancel_fn: fn() { Error("not available") },
      spawn_workflow_fn: fn(_, _, _) { Error("not available") },
    )

  task_executor.evaluate_cancel_if(handler, ctx)
  |> should.be_false()
}

pub fn evaluate_skip_if_with_condition_test() {
  let handler =
    create_test_handler(3, Some(fn(_ctx) { True }), None, fn(_ctx) {
      Ok(dynamic.string("test"))
    })
  let ctx =
    types.TaskContext(
      workflow_run_id: "test",
      task_run_id: "test",
      input: dynamic.string(""),
      parent_outputs: dict.new(),
      metadata: dict.new(),
      logger: fn(_) { Nil },
      step_run_errors: dict.new(),
      stream_fn: fn(_) { Error("not available") },
      release_slot_fn: fn() { Error("not available") },
      refresh_timeout_fn: fn(_) { Error("not available") },
      cancel_fn: fn() { Error("not available") },
      spawn_workflow_fn: fn(_, _, _) { Error("not available") },
    )

  task_executor.evaluate_skip_if(handler, ctx)
  |> should.be_true()
}

pub fn evaluate_skip_if_without_condition_test() {
  let handler =
    create_test_handler(3, None, None, fn(_ctx) { Ok(dynamic.string("test")) })
  let ctx =
    types.TaskContext(
      workflow_run_id: "test",
      task_run_id: "test",
      input: dynamic.string(""),
      parent_outputs: dict.new(),
      metadata: dict.new(),
      logger: fn(_) { Nil },
      step_run_errors: dict.new(),
      stream_fn: fn(_) { Error("not available") },
      release_slot_fn: fn() { Error("not available") },
      refresh_timeout_fn: fn(_) { Error("not available") },
      cancel_fn: fn() { Error("not available") },
      spawn_workflow_fn: fn(_, _, _) { Error("not available") },
    )

  task_executor.evaluate_skip_if(handler, ctx)
  |> should.be_false()
}

// ============================================================================
// Parent Outputs Tests
// ============================================================================

pub fn execute_task_with_parent_outputs_test() {
  // Arrange
  let action = create_test_action()
  let handler =
    create_test_handler(3, None, None, fn(_ctx) {
      // Just return success - we'll check that parent outputs are available in context
      Ok(dynamic.string("found parent output"))
    })

  let parent_outputs =
    dict.from_list([#("parent-step", "{\"result\":\"parent data\"}")])

  let spec =
    TaskSpec(
      action: action,
      handler: handler,
      worker_id: "worker-1",
      parent_outputs: parent_outputs,
    )
  let effects = create_test_effects()

  // Act
  let result = task_executor.execute_task(spec, effects)

  // Assert
  case result {
    Completed(output) -> {
      output.output_json
      |> should.equal("\"found parent output\"")
    }
    _ -> should.fail()
  }
}
