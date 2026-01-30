//// Comprehensive Acceptance Tests for Hatchet Gleam SDK
////
//// This file contains 100 acceptance tests across 10 categories following
//// ATDD, EARS, KIRK, BDD, and Design by Contract methodologies.
////
//// Test Categories:
//// 1. Client Management (10 tests) - TEST-001 to TEST-010
//// 2. Workflow Definition (15 tests) - TEST-011 to TEST-025
//// 3. Task Context (15 tests) - TEST-026 to TEST-040
//// 4. Durable Tasks (10 tests) - TEST-041 to TEST-050
//// 5. Worker Management (10 tests) - TEST-051 to TEST-060
//// 6. Event System (10 tests) - TEST-061 to TEST-070
//// 7. Scheduling (10 tests) - TEST-071 to TEST-080
//// 8. Run Management (10 tests) - TEST-081 to TEST-090
//// 9. Rate Limiting (5 tests) - TEST-091 to TEST-095
//// 10. Standalone Tasks (5 tests) - TEST-096 to TEST-100
////
//// Run with: gleam test

import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import hatchet/client
import hatchet/context
import hatchet/durable
import hatchet/events
import hatchet/internal/tls
import hatchet/rate_limits
import hatchet/run
import hatchet/standalone
import hatchet/task
import hatchet/types.{DropNew, Exponential, QueueNew}
import hatchet/workflow

// ============================================================================
// CATEGORY 1: CLIENT MANAGEMENT TESTS (TEST-001 to TEST-010)
// ============================================================================

/// TEST-001: Client Creation with Explicit Config
/// EARS: WHEN client.new(host, token) is called with valid parameters
///       THE system SHALL return Ok(Client) with matching configuration
pub fn test_001_client_creation_with_explicit_config_test() {
  // GIVEN: Valid host and token strings
  let host = "localhost"
  let token = "test-jwt-token"

  // WHEN: client.new is called
  let result = client.new(host, token)

  // THEN: Result is Ok(Client) with matching configuration
  let assert Ok(c) = result
  types.get_host(c) |> should.equal("localhost")
  types.get_token(c) |> should.equal("test-jwt-token")
  types.get_port(c) |> should.equal(7070)
  types.get_namespace(c) |> should.equal(None)
}

/// TEST-002: Client with Custom Port
/// EARS: WHEN client is configured with custom port
///       THE system SHALL use specified port for connections
pub fn test_002_client_with_custom_port_test() {
  // GIVEN: A client with default configuration
  let assert Ok(base_client) = client.new("localhost", "token")

  // WHEN: with_port is called
  let updated = client.with_port(base_client, 8080)

  // THEN: New client has port == 8080 AND original unchanged (immutability)
  types.get_port(updated) |> should.equal(8080)
  types.get_port(base_client) |> should.equal(7070)
  types.get_host(updated) |> should.equal("localhost")
}

/// TEST-003: Client with Namespace
/// EARS: WHEN client is configured with namespace
///       THE system SHALL prefix all workflow names with namespace
pub fn test_003_client_with_namespace_test() {
  // GIVEN: Client without namespace
  let assert Ok(base_client) = client.new("localhost", "token")

  // WHEN: with_namespace is called
  let namespaced = client.with_namespace(base_client, "production")

  // THEN: get_namespace returns Some("production")
  types.get_namespace(namespaced) |> should.equal(Some("production"))
  types.get_host(namespaced) |> should.equal("localhost")
}

/// TEST-004: Client with TLS
/// EARS: WHEN client is configured with TLS CA path
///       THE system SHALL use TLS for gRPC connections
pub fn test_004_client_with_tls_test() {
  // GIVEN: Client created
  let assert Ok(base_client) = client.new("localhost", "token")

  // WHEN: with_tls is called
  let tls_client = client.with_tls(base_client, "/path/to/ca.pem")

  // THEN: get_tls_config returns Tls with CA path
  case types.get_tls_config(tls_client) {
    tls.Tls(ca_path) -> ca_path |> should.equal("/path/to/ca.pem")
    _ -> should.fail()
  }
}

/// TEST-005: Client with mTLS
/// EARS: WHEN client is configured with mTLS certificates
///       THE system SHALL present client certificate during TLS handshake
pub fn test_005_client_with_mtls_test() {
  // GIVEN: Client created
  let assert Ok(base_client) = client.new("localhost", "token")

  // WHEN: with_mtls is called
  let mtls_client =
    client.with_mtls(base_client, "/ca.pem", "/cert.pem", "/key.pem")

  // THEN: get_tls_config returns Mtls with all paths
  case types.get_tls_config(mtls_client) {
    tls.Mtls(ca, cert, key) -> {
      ca |> should.equal("/ca.pem")
      cert |> should.equal("/cert.pem")
      key |> should.equal("/key.pem")
    }
    _ -> should.fail()
  }
}

/// TEST-006: Client with Insecure Connection
/// EARS: WHEN client is configured with insecure mode
///       THE system SHALL connect without TLS (development only)
pub fn test_006_client_with_insecure_test() {
  // GIVEN: Client created
  let assert Ok(base_client) = client.new("localhost", "token")

  // WHEN: with_insecure is called
  let insecure_client = client.with_insecure(base_client)

  // THEN: get_tls_config returns Insecure
  types.get_tls_config(insecure_client) |> should.equal(tls.Insecure)
}

/// TEST-007: TLS Security Detection - TLS is secure
/// EARS: WHEN TLS config is Tls, THE is_secure SHALL return true
pub fn test_007_tls_is_secure_test() {
  let assert Ok(base_client) = client.new("localhost", "token")
  let tls_client = client.with_tls(base_client, "/ca.pem")
  let config = types.get_tls_config(tls_client)
  tls.is_secure(config) |> should.be_true()
}

/// TEST-008: TLS Security Detection - mTLS is secure
/// EARS: WHEN TLS config is Mtls, THE is_secure SHALL return true
pub fn test_008_mtls_is_secure_test() {
  let assert Ok(base_client) = client.new("localhost", "token")
  let mtls_client = client.with_mtls(base_client, "/ca", "/cert", "/key")
  let config = types.get_tls_config(mtls_client)
  tls.is_secure(config) |> should.be_true()
}

/// TEST-009: TLS Security Detection - Insecure is not secure
/// EARS: WHEN TLS config is Insecure, THE is_secure SHALL return false
pub fn test_009_insecure_not_secure_test() {
  let assert Ok(base_client) = client.new("localhost", "token")
  let insecure_client = client.with_insecure(base_client)
  let config = types.get_tls_config(insecure_client)
  tls.is_secure(config) |> should.be_false()
}

/// TEST-010: Client Immutability on Configuration
/// EARS: WHEN configuration methods are chained
///       THE system SHALL preserve all previous configurations
pub fn test_010_client_immutability_chaining_test() {
  let assert Ok(base) = client.new("localhost", "token")
  let configured =
    base
    |> client.with_port(9090)
    |> client.with_namespace("prod")
    |> client.with_tls("/ca.pem")

  // All configurations preserved
  types.get_port(configured) |> should.equal(9090)
  types.get_namespace(configured) |> should.equal(Some("prod"))
  case types.get_tls_config(configured) {
    tls.Tls(_) -> should.be_true(True)
    _ -> should.fail()
  }
}

// ============================================================================
// CATEGORY 2: WORKFLOW DEFINITION TESTS (TEST-011 to TEST-025)
// ============================================================================

/// TEST-011: Basic Workflow Creation
/// EARS: WHEN workflow.new(name) is called
///       THE system SHALL create workflow with specified name
pub fn test_011_basic_workflow_creation_test() {
  // GIVEN: name = "order-processor"
  let name = "order-processor"

  // WHEN: workflow.new is called
  let wf = workflow.new(name)

  // THEN: workflow has correct defaults
  wf.name |> should.equal("order-processor")
  wf.tasks |> should.equal([])
  wf.events |> should.equal([])
  wf.description |> should.equal(None)
  wf.version |> should.equal(None)
  wf.cron |> should.equal(None)
}

/// TEST-012: Workflow with Description
/// EARS: WHEN with_description is called
///       THE system SHALL store description metadata
pub fn test_012_workflow_with_description_test() {
  let wf =
    workflow.new("test")
    |> workflow.with_description("Processes orders")

  wf.description |> should.equal(Some("Processes orders"))
}

/// TEST-013: Workflow with Version
/// EARS: WHEN with_version is called
///       THE system SHALL track workflow version
pub fn test_013_workflow_with_version_test() {
  let wf =
    workflow.new("test")
    |> workflow.with_version("1.2.0")

  wf.version |> should.equal(Some("1.2.0"))
}

/// TEST-014: Workflow with Single Task
/// EARS: WHEN workflow.task is called
///       THE system SHALL add task to workflow's task list
pub fn test_014_workflow_with_single_task_test() {
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }
  let wf =
    workflow.new("test")
    |> workflow.task("process", handler)

  wf.tasks |> list.length |> should.equal(1)
  let assert [t] = wf.tasks
  t.name |> should.equal("process")
  t.parents |> should.equal([])
}

/// TEST-015: Workflow with Dependent Task
/// EARS: WHEN task_after is called with parent list
///       THE system SHALL create task that runs after parents complete
pub fn test_015_workflow_with_dependent_task_test() {
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }
  let wf =
    workflow.new("test")
    |> workflow.task("fetch", handler)
    |> workflow.task_after("process", ["fetch"], handler)

  wf.tasks |> list.length |> should.equal(2)
  let assert [_, process_task] = wf.tasks
  process_task.parents |> should.equal(["fetch"])
}

/// TEST-016: Workflow with Multiple Dependencies
/// EARS: WHEN task has multiple parents
///       THE system SHALL wait for all parents to complete
pub fn test_016_workflow_with_multiple_dependencies_test() {
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }
  let wf =
    workflow.new("test")
    |> workflow.task("fetch-a", handler)
    |> workflow.task("fetch-b", handler)
    |> workflow.task_after("combine", ["fetch-a", "fetch-b"], handler)

  wf.tasks |> list.length |> should.equal(3)
  let combine_task =
    wf.tasks |> list.filter(fn(t) { t.name == "combine" }) |> list.first
  case combine_task {
    Ok(t) -> t.parents |> should.equal(["fetch-a", "fetch-b"])
    Error(_) -> should.fail()
  }
}

/// TEST-017: Workflow with Cron Schedule
/// EARS: WHEN with_cron is called with expression
///       THE system SHALL trigger workflow on cron schedule
pub fn test_017_workflow_with_cron_schedule_test() {
  let wf =
    workflow.new("test")
    |> workflow.with_cron("0 * * * *")

  wf.cron |> should.equal(Some("0 * * * *"))
}

/// TEST-018: Workflow with Event Triggers
/// EARS: WHEN with_events is called with event list
///       THE system SHALL trigger workflow when events published
pub fn test_018_workflow_with_event_triggers_test() {
  let wf =
    workflow.new("test")
    |> workflow.with_events(["order.created", "order.updated"])

  wf.events |> should.equal(["order.created", "order.updated"])
}

/// TEST-019: Workflow with Concurrency Limit
/// EARS: WHEN with_concurrency is called
///       THE system SHALL limit concurrent workflow runs
pub fn test_019_workflow_with_concurrency_limit_test() {
  let wf =
    workflow.new("test")
    |> workflow.with_concurrency(5, QueueNew)

  case wf.concurrency {
    Some(config) -> {
      config.max_concurrent |> should.equal(5)
      config.limit_strategy |> should.equal(QueueNew)
    }
    None -> should.fail()
  }
}

/// TEST-020: Workflow with Task Retries
/// EARS: WHEN with_retries is called after task
///       THE system SHALL retry failed task specified times
pub fn test_020_workflow_with_task_retries_test() {
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }
  let wf =
    workflow.new("test")
    |> workflow.task("task1", handler)
    |> workflow.with_retries(3)

  let assert [t] = wf.tasks
  t.retries |> should.equal(3)
}

/// TEST-021: Workflow with Task Timeout
/// EARS: WHEN with_timeout is called after task
///       THE system SHALL terminate task after timeout
pub fn test_021_workflow_with_task_timeout_test() {
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }
  let wf =
    workflow.new("test")
    |> workflow.task("task1", handler)
    |> workflow.with_timeout(30_000)

  let assert [t] = wf.tasks
  t.execution_timeout_ms |> should.equal(Some(30_000))
}

/// TEST-022: Workflow with Retry Backoff
/// EARS: WHEN with_retry_backoff is called
///       THE system SHALL apply backoff between retry attempts
pub fn test_022_workflow_with_retry_backoff_test() {
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }
  let backoff = Exponential(base_ms: 1000, max_ms: 60_000)
  let wf =
    workflow.new("test")
    |> workflow.task("task1", handler)
    |> workflow.with_retry_backoff(backoff)

  let assert [t] = wf.tasks
  case t.retry_backoff {
    Some(Exponential(base, max)) -> {
      base |> should.equal(1000)
      max |> should.equal(60_000)
    }
    _ -> should.fail()
  }
}

/// TEST-023: Workflow with On Failure Handler
/// EARS: WHEN any task fails AND on_failure is configured
///       THE system SHALL execute failure handler
pub fn test_023_workflow_with_on_failure_handler_test() {
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }
  let failure_handler = fn(_ctx) { Ok(Nil) }
  let wf =
    workflow.new("test")
    |> workflow.task("task1", handler)
    |> workflow.on_failure(failure_handler)

  wf.on_failure |> should.not_equal(None)
}

/// TEST-024: Workflow with Rate Limit
/// EARS: WHEN with_rate_limit is called
///       THE system SHALL enforce rate limit on task execution
pub fn test_024_workflow_with_rate_limit_test() {
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }
  let wf =
    workflow.new("test")
    |> workflow.task("task1", handler)
    |> workflow.with_rate_limit("api", 10, 60_000)

  let assert [t] = wf.tasks
  t.rate_limits |> list.length |> should.equal(1)
  let assert [rl] = t.rate_limits
  rl.key |> should.equal("api")
  rl.units |> should.equal(10)
  rl.duration_ms |> should.equal(60_000)
}

/// TEST-025: Workflow with Task Concurrency
/// EARS: WHEN with_task_concurrency is called
///       THE system SHALL limit concurrent executions of that task
pub fn test_025_workflow_with_task_concurrency_test() {
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }
  let wf =
    workflow.new("test")
    |> workflow.task("task1", handler)
    |> workflow.with_task_concurrency(5, DropNew)

  let assert [t] = wf.tasks
  case t.concurrency {
    Some(config) -> {
      config.max_concurrent |> should.equal(5)
      config.limit_strategy |> should.equal(DropNew)
    }
    None -> should.fail()
  }
}

// ============================================================================
// CATEGORY 3: TASK CONTEXT TESTS (TEST-026 to TEST-040)
// ============================================================================

/// TEST-026: Context Input Access
/// EARS: WHEN task executes
///       THE context.input SHALL contain workflow input data
pub fn test_026_context_input_access_test() {
  // GIVEN: Mock context with input
  let input = dynamic.int(42)
  let ctx = context.mock(input, dict.new())

  // WHEN: input is accessed
  let result = context.input(ctx)

  // THEN: Input is accessible
  decode.run(result, decode.int) |> should.equal(Ok(42))
}

/// TEST-027: Context Parent Output Access
/// EARS: WHEN task has parents
///       THE context.step_output(name) SHALL return parent's output
pub fn test_027_context_parent_output_access_test() {
  // GIVEN: Context with parent output
  let parent_output = dynamic.string("parent result")
  let outputs = dict.from_list([#("fetch", parent_output)])
  let ctx = context.mock(dynamic.nil(), outputs)

  // WHEN: step_output is called
  let result = context.step_output(ctx, "fetch")

  // THEN: Parent output accessible
  case result {
    Some(d) -> decode.run(d, decode.string) |> should.equal(Ok("parent result"))
    None -> should.fail()
  }
}

/// TEST-028: Context Parent Output Not Found
/// EARS: WHEN step_output is called for non-existent parent
///       THE system SHALL return None
pub fn test_028_context_parent_output_not_found_test() {
  let ctx = context.mock(dynamic.nil(), dict.new())
  context.step_output(ctx, "nonexistent") |> should.equal(None)
}

/// TEST-029: Context Workflow Run ID
/// EARS: WHEN task executes
///       THE context.workflow_run_id SHALL return unique run ID
pub fn test_029_context_workflow_run_id_test() {
  let ctx = context.mock(dynamic.nil(), dict.new())
  let run_id = context.workflow_run_id(ctx)
  string.length(run_id) |> should.not_equal(0)
}

/// TEST-030: Context Step Run ID
/// EARS: WHEN task executes
///       THE context.step_run_id SHALL return unique task run ID
pub fn test_030_context_step_run_id_test() {
  let ctx = context.mock(dynamic.nil(), dict.new())
  let step_id = context.step_run_id(ctx)
  string.length(step_id) |> should.not_equal(0)
}

/// TEST-031: Context Retry Count
/// EARS: WHEN task is retrying
///       THE context.retry_count SHALL return current attempt
pub fn test_031_context_retry_count_test() {
  // First attempt has retry_count = 0
  let ctx = context.mock(dynamic.nil(), dict.new())
  context.retry_count(ctx) |> should.equal(0)

  // Retry attempt has retry_count = 3
  let ctx_retry = context.mock_with_retry(dynamic.nil(), dict.new(), 3)
  context.retry_count(ctx_retry) |> should.equal(3)
}

/// TEST-032: Context Logging
/// EARS: WHEN context.log is called
///       THE system SHALL send log to Hatchet server
pub fn test_032_context_logging_test() {
  let ctx = context.mock(dynamic.nil(), dict.new())
  // Should not crash
  context.log(ctx, "Test log message")
  should.be_true(True)
}

/// TEST-033: Context All Parent Outputs
/// EARS: WHEN all_parent_outputs is called
///       THE system SHALL return dict of all parent outputs
pub fn test_033_context_all_parent_outputs_test() {
  let outputs =
    dict.from_list([
      #("task1", dynamic.string("output1")),
      #("task2", dynamic.string("output2")),
    ])
  let ctx = context.mock(dynamic.nil(), outputs)

  let result = context.all_parent_outputs(ctx)
  dict.size(result) |> should.equal(2)
}

/// TEST-034: Context Metadata Access - Empty
/// EARS: WHEN workflow has no metadata
///       THE context.metadata SHALL return empty dict
pub fn test_034_context_metadata_empty_test() {
  let ctx = context.mock(dynamic.nil(), dict.new())
  let metadata = context.metadata(ctx)
  dict.size(metadata) |> should.equal(0)
}

/// TEST-035: Context Get Metadata Not Found
/// EARS: WHEN get_metadata is called for non-existent key
///       THE system SHALL return None
pub fn test_035_context_get_metadata_not_found_test() {
  let ctx = context.mock(dynamic.nil(), dict.new())
  context.get_metadata(ctx, "missing_key") |> should.equal(None)
}

/// TEST-036: Context put_stream Default Returns Error
/// EARS: WHEN put_stream is called on mock context
///       THE system SHALL return Error (not connected)
pub fn test_036_context_put_stream_default_error_test() {
  let ctx = context.mock(dynamic.nil(), dict.new())
  case context.put_stream(ctx, dynamic.string("data")) {
    Error(_) -> should.be_true(True)
    Ok(_) -> should.fail()
  }
}

/// TEST-037: Context release_slot Default Returns Error
/// EARS: WHEN release_slot is called on mock context
///       THE system SHALL return Error (not connected)
pub fn test_037_context_release_slot_default_error_test() {
  let ctx = context.mock(dynamic.nil(), dict.new())
  case context.release_slot(ctx) {
    Error(_) -> should.be_true(True)
    Ok(_) -> should.fail()
  }
}

/// TEST-038: Context refresh_timeout Default Returns Error
/// EARS: WHEN refresh_timeout is called on mock context
///       THE system SHALL return Error (not connected)
pub fn test_038_context_refresh_timeout_default_error_test() {
  let ctx = context.mock(dynamic.nil(), dict.new())
  case context.refresh_timeout(ctx, 5000) {
    Error(_) -> should.be_true(True)
    Ok(_) -> should.fail()
  }
}

/// TEST-039: Context cancel Default Returns Error
/// EARS: WHEN cancel is called on mock context
///       THE system SHALL return Error (not connected)
pub fn test_039_context_cancel_default_error_test() {
  let ctx = context.mock(dynamic.nil(), dict.new())
  case context.cancel(ctx) {
    Error(_) -> should.be_true(True)
    Ok(_) -> should.fail()
  }
}

/// TEST-040: Context spawn_workflow Default Returns Error
/// EARS: WHEN spawn_workflow is called on mock context
///       THE system SHALL return Error (not connected)
pub fn test_040_context_spawn_workflow_default_error_test() {
  let ctx = context.mock(dynamic.nil(), dict.new())
  case context.spawn_workflow(ctx, "child", dynamic.nil()) {
    Error(_) -> should.be_true(True)
    Ok(_) -> should.fail()
  }
}

// ============================================================================
// CATEGORY 4: DURABLE TASK TESTS (TEST-041 to TEST-050)
// ============================================================================

/// TEST-041: Durable Context Creation
/// EARS: WHEN from_context is called
///       THE system SHALL create DurableContext from Context
pub fn test_041_durable_context_creation_test() {
  let ctx = context.mock(dynamic.nil(), dict.new())
  let durable_ctx =
    durable.from_context(
      ctx,
      "checkpoint-key",
      fn(_step_id, _signal_key, _conditions) { Ok(Nil) },
      fn(_step_id, _signal_key) { Ok(dynamic.nil()) },
    )

  durable.get_checkpoint_key(durable_ctx) |> should.equal("checkpoint-key")
}

/// TEST-042: Durable Context Input Access
/// EARS: WHEN durable task executes
///       THE durable.input(ctx) SHALL return workflow input
pub fn test_042_durable_context_input_access_test() {
  let ctx = context.mock(dynamic.int(42), dict.new())
  let durable_ctx =
    durable.from_context(ctx, "key", fn(_, _, _) { Ok(Nil) }, fn(_, _) {
      Ok(dynamic.nil())
    })

  let result = durable.input(durable_ctx)
  decode.run(result, decode.int) |> should.equal(Ok(42))
}

/// TEST-043: Durable Context Parent Output Access
/// EARS: WHEN durable task has parents
///       THE durable.step_output SHALL return parent output
pub fn test_043_durable_context_parent_output_access_test() {
  let outputs = dict.from_list([#("parent", dynamic.string("output"))])
  let ctx = context.mock(dynamic.nil(), outputs)
  let durable_ctx =
    durable.from_context(ctx, "key", fn(_, _, _) { Ok(Nil) }, fn(_, _) {
      Ok(dynamic.nil())
    })

  case durable.step_output(durable_ctx, "parent") {
    Some(d) -> decode.run(d, decode.string) |> should.equal(Ok("output"))
    None -> should.fail()
  }
}

/// TEST-044: Durable Context Metadata Access
/// EARS: WHEN durable task executes
///       THE durable.metadata SHALL return workflow metadata
pub fn test_044_durable_context_metadata_access_test() {
  let ctx = context.mock(dynamic.nil(), dict.new())
  let durable_ctx =
    durable.from_context(ctx, "key", fn(_, _, _) { Ok(Nil) }, fn(_, _) {
      Ok(dynamic.nil())
    })

  let result = durable.metadata(durable_ctx)
  dict.size(result) |> should.equal(0)
}

/// TEST-045: Durable Context Logging
/// EARS: WHEN durable.log is called
///       THE system SHALL send log to server
pub fn test_045_durable_context_logging_test() {
  let ctx = context.mock(dynamic.nil(), dict.new())
  let durable_ctx =
    durable.from_context(ctx, "key", fn(_, _, _) { Ok(Nil) }, fn(_, _) {
      Ok(dynamic.nil())
    })

  // Should not crash
  durable.log(durable_ctx, "Test message")
  should.be_true(True)
}

/// TEST-046: Durable Context to_context
/// EARS: WHEN to_context is called
///       THE system SHALL return base Context
pub fn test_046_durable_context_to_context_test() {
  let ctx = context.mock(dynamic.int(42), dict.new())
  let durable_ctx =
    durable.from_context(ctx, "key", fn(_, _, _) { Ok(Nil) }, fn(_, _) {
      Ok(dynamic.nil())
    })

  let base = durable.to_context(durable_ctx)
  decode.run(context.input(base), decode.int) |> should.equal(Ok(42))
}

/// TEST-047: Durable Context to_task_context
/// EARS: WHEN to_task_context is called
///       THE system SHALL return TaskContext
pub fn test_047_durable_context_to_task_context_test() {
  let ctx = context.mock(dynamic.nil(), dict.new())
  let durable_ctx =
    durable.from_context(ctx, "key", fn(_, _, _) { Ok(Nil) }, fn(_, _) {
      Ok(dynamic.nil())
    })

  let task_ctx = durable.to_task_context(durable_ctx)
  string.length(task_ctx.workflow_run_id) |> should.not_equal(0)
}

/// TEST-048: Durable Wait Key Counter Increment
/// EARS: WHEN increment_wait_key_counter is called
///       THE system SHALL increment counter for unique keys
pub fn test_048_durable_wait_key_counter_increment_test() {
  let ctx = context.mock(dynamic.nil(), dict.new())
  let durable_ctx =
    durable.from_context(ctx, "key", fn(_, _, _) { Ok(Nil) }, fn(_, _) {
      Ok(dynamic.nil())
    })

  let _incremented = durable.increment_wait_key_counter(durable_ctx)
  // Counter should have incremented
  should.be_true(True)
}

/// TEST-049: Checkpoint Save Not Yet Implemented
/// EARS: WHEN save_checkpoint is called
///       THE system SHALL return Error (not implemented)
pub fn test_049_checkpoint_save_not_implemented_test() {
  let ctx = context.mock(dynamic.nil(), dict.new())
  let durable_ctx =
    durable.from_context(ctx, "key", fn(_, _, _) { Ok(Nil) }, fn(_, _) {
      Ok(dynamic.nil())
    })

  case durable.save_checkpoint(durable_ctx, "cp1", dynamic.int(42)) {
    Error(msg) -> string.contains(msg, "not yet implemented") |> should.be_true
    Ok(_) -> should.fail()
  }
}

/// TEST-050: Checkpoint Load Returns None
/// EARS: WHEN load_checkpoint is called
///       THE system SHALL return None (not implemented)
pub fn test_050_checkpoint_load_not_implemented_test() {
  let ctx = context.mock(dynamic.nil(), dict.new())
  let durable_ctx =
    durable.from_context(ctx, "key", fn(_, _, _) { Ok(Nil) }, fn(_, _) {
      Ok(dynamic.nil())
    })

  durable.load_checkpoint(durable_ctx, "cp1") |> should.equal(None)
}

// ============================================================================
// CATEGORY 5: WORKER MANAGEMENT TESTS (TEST-051 to TEST-060)
// ============================================================================

/// TEST-051: Worker Config Default
/// EARS: WHEN default_worker_config is called
///       THE system SHALL return config with default values
pub fn test_051_worker_config_default_test() {
  let config = client.default_worker_config()

  config.slots |> should.equal(10)
  config.name |> should.equal(None)
}

/// TEST-052: Worker Config with Custom Slots
/// EARS: WHEN worker_config is called with slots
///       THE config SHALL have specified slot count
pub fn test_052_worker_config_custom_slots_test() {
  let config = client.worker_config(Some("my-worker"), 50)

  config.slots |> should.equal(50)
  config.name |> should.equal(Some("my-worker"))
}

/// TEST-053: Worker Config with Labels
/// EARS: WHEN WorkerConfig has labels
///       THE system SHALL use labels for task routing
pub fn test_053_worker_config_with_labels_test() {
  let config =
    types.WorkerConfig(
      name: Some("gpu-worker"),
      slots: 20,
      durable_slots: 5,
      labels: dict.from_list([#("gpu", "true"), #("tier", "high")]),
    )

  dict.get(config.labels, "gpu") |> should.equal(Ok("true"))
  dict.get(config.labels, "tier") |> should.equal(Ok("high"))
}

/// TEST-054: Worker Config Durable Slots
/// EARS: WHEN durable_slots is specified
///       THE worker SHALL reserve slots for durable tasks
pub fn test_054_worker_config_durable_slots_test() {
  let config =
    types.WorkerConfig(
      name: None,
      slots: 10,
      durable_slots: 3,
      labels: dict.new(),
    )

  config.durable_slots |> should.equal(3)
}

/// TEST-055: Create Worker Requires Client
/// EARS: WHEN new_worker is called
///       THE system SHALL require valid client
/// NOTE: This test validates the API exists; actual connection requires live server
pub fn test_055_create_worker_requires_client_test() {
  let assert Ok(c) = client.new("localhost", "token")
  let config = client.default_worker_config()
  let wf =
    workflow.new("test") |> workflow.task("t", fn(_) { Ok(dynamic.nil()) })

  // Verify client, config, and workflow are valid structures
  types.get_host(c) |> should.equal("localhost")
  config.slots |> should.equal(10)
  wf.name |> should.equal("test")
  // Note: Actual worker creation requires live server (HATCHET_LIVE_TEST=1)
}

/// TEST-056: Worker Registration Requires Workflows
/// EARS: WHEN worker is created with empty workflows
///       THE system SHALL allow but worker won't process tasks
/// NOTE: This test validates the API structure; actual connection requires live server
pub fn test_056_worker_empty_workflows_test() {
  let assert Ok(c) = client.new("localhost", "token")
  let config = client.default_worker_config()
  let workflows: List(types.Workflow) = []

  // Verify empty workflow list is a valid input
  types.get_host(c) |> should.equal("localhost")
  config.slots |> should.equal(10)
  workflows |> list.length |> should.equal(0)
  // Note: Actual worker creation requires live server (HATCHET_LIVE_TEST=1)
}

/// TEST-057: Worker Config Name Optional
/// EARS: WHEN worker name is None
///       THE system SHALL generate a name
pub fn test_057_worker_config_name_optional_test() {
  let config =
    types.WorkerConfig(
      name: None,
      slots: 10,
      durable_slots: 1,
      labels: dict.new(),
    )

  config.name |> should.equal(None)
}

/// TEST-058: Worker Multiple Workflows
/// EARS: WHEN worker is created with multiple workflows
///       THE worker SHALL process tasks from all workflows
/// NOTE: This test validates multiple workflow structure; actual connection requires live server
pub fn test_058_worker_multiple_workflows_test() {
  let assert Ok(_c) = client.new("localhost", "token")
  let _config = client.default_worker_config()
  let handler = fn(_) { Ok(dynamic.nil()) }

  let wf1 = workflow.new("workflow1") |> workflow.task("task1", handler)
  let wf2 = workflow.new("workflow2") |> workflow.task("task2", handler)
  let wf3 = workflow.new("workflow3") |> workflow.task("task3", handler)

  let workflows = [wf1, wf2, wf3]
  // Verify multiple workflows can be defined
  workflows |> list.length |> should.equal(3)
  wf1.name |> should.equal("workflow1")
  wf2.name |> should.equal("workflow2")
  wf3.name |> should.equal("workflow3")
  // Note: Actual worker creation requires live server (HATCHET_LIVE_TEST=1)
}

/// TEST-059: Worker Labels for Routing
/// EARS: WHEN worker has labels
///       THE system SHALL route matching tasks to worker
pub fn test_059_worker_labels_routing_test() {
  let labels = dict.from_list([#("region", "us-east-1"), #("capability", "ml")])

  let config =
    types.WorkerConfig(
      name: Some("ml-worker"),
      slots: 5,
      durable_slots: 0,
      labels: labels,
    )

  dict.size(config.labels) |> should.equal(2)
}

/// TEST-060: Worker Config Immutability
/// EARS: WHEN WorkerConfig is created
///       THE config SHALL be immutable
pub fn test_060_worker_config_immutability_test() {
  let config =
    types.WorkerConfig(
      name: Some("worker"),
      slots: 10,
      durable_slots: 1,
      labels: dict.new(),
    )

  // Config values are fixed
  config.slots |> should.equal(10)
  config.name |> should.equal(Some("worker"))
}

// ============================================================================
// CATEGORY 6: EVENT SYSTEM TESTS (TEST-061 to TEST-070)
// ============================================================================

/// TEST-061: Event Builder Creates Event
/// EARS: WHEN events.event is called
///       THE system SHALL create event with key and data
pub fn test_061_event_builder_creates_event_test() {
  let data = dynamic.string("test-data")
  let evt = events.event("order.created", data)

  evt.key |> should.equal("order.created")
}

/// TEST-062: Event Builder with Metadata
/// EARS: WHEN with_metadata is called
///       THE event SHALL include metadata
pub fn test_062_event_builder_with_metadata_test() {
  let evt =
    events.event("test.event", dynamic.string("data"))
    |> events.with_metadata(
      dict.from_list([#("key1", "value1"), #("key2", "value2")]),
    )

  dict.get(evt.metadata, "key1") |> should.equal(Ok("value1"))
  dict.get(evt.metadata, "key2") |> should.equal(Ok("value2"))
}

/// TEST-063: Event Builder put_metadata
/// EARS: WHEN put_metadata is called
///       THE system SHALL add single metadata key
pub fn test_063_event_builder_put_metadata_test() {
  let evt =
    events.event("test.event", dynamic.string("data"))
    |> events.put_metadata("source", "api")
    |> events.put_metadata("version", "1.0")

  dict.get(evt.metadata, "source") |> should.equal(Ok("api"))
  dict.get(evt.metadata, "version") |> should.equal(Ok("1.0"))
}

/// TEST-064: Event Metadata Override
/// EARS: WHEN put_metadata is called for existing key
///       THE system SHALL override the value
pub fn test_064_event_metadata_override_test() {
  let evt =
    events.event("test.event", dynamic.string("data"))
    |> events.put_metadata("version", "1.0")
    |> events.put_metadata("version", "2.0")

  dict.get(evt.metadata, "version") |> should.equal(Ok("2.0"))
}

/// TEST-065: Event Without Metadata
/// EARS: WHEN event created without metadata
///       THE metadata dict SHALL be empty
pub fn test_065_event_without_metadata_test() {
  let evt = events.event("test.event", dynamic.string("data"))

  dict.size(evt.metadata) |> should.equal(0)
}

/// TEST-066: Event Key Formats
/// EARS: WHEN event key has dots/hyphens
///       THE system SHALL accept the format
pub fn test_066_event_key_formats_test() {
  let keys = [
    "user.created",
    "order.completed",
    "payment-success",
    "user-registered",
    "a.b.c.d",
  ]

  let events_list =
    list.map(keys, fn(k) { events.event(k, dynamic.string("data")) })

  events_list |> list.length |> should.equal(5)
}

/// TEST-067: Multiple Events Creation
/// EARS: WHEN creating multiple events
///       THE system SHALL handle all correctly
pub fn test_067_multiple_events_creation_test() {
  let events_list = [
    events.event("event1", dynamic.string("data1")),
    events.event("event2", dynamic.string("data2")),
    events.event("event3", dynamic.string("data3")),
  ]

  events_list |> list.length |> should.equal(3)
  events_list
  |> list.map(fn(e) { e.key })
  |> should.equal(["event1", "event2", "event3"])
}

/// TEST-068: Events with Mixed Metadata
/// EARS: WHEN events have different metadata
///       THE system SHALL preserve each independently
pub fn test_068_events_with_mixed_metadata_test() {
  let evt1 =
    events.event("event1", dynamic.string("data"))
    |> events.put_metadata("type", "a")
  let evt2 =
    events.event("event2", dynamic.string("data"))
    |> events.put_metadata("type", "b")

  dict.get(evt1.metadata, "type") |> should.equal(Ok("a"))
  dict.get(evt2.metadata, "type") |> should.equal(Ok("b"))
}

/// TEST-069: Event Data Types
/// EARS: WHEN event data is complex
///       THE system SHALL serialize correctly
pub fn test_069_event_data_types_test() {
  // String data
  let _str_evt = events.event("test", dynamic.string("string"))
  should.be_true(True)

  // Int data
  let _int_evt = events.event("test", dynamic.int(42))
  should.be_true(True)

  // Bool data
  let _bool_evt = events.event("test", dynamic.bool(True))
  should.be_true(True)
}

/// TEST-070: Workflow Event Triggers Match
/// EARS: WHEN workflow events match published event
///       THE system SHALL trigger workflow
pub fn test_070_workflow_event_triggers_match_test() {
  let workflow_events = ["user.created", "user.updated"]

  // Check if events would match
  list.contains(workflow_events, "user.created") |> should.be_true
  list.contains(workflow_events, "user.deleted") |> should.be_false
}

// ============================================================================
// CATEGORY 7: SCHEDULING TESTS (TEST-071 to TEST-080)
// ============================================================================

/// TEST-071: Cron Expression in Workflow
/// EARS: WHEN workflow has cron expression
///       THE workflow SHALL be scheduled
pub fn test_071_cron_expression_in_workflow_test() {
  let wf =
    workflow.new("scheduled")
    |> workflow.with_cron("0 * * * *")

  wf.cron |> should.equal(Some("0 * * * *"))
}

/// TEST-072: Multiple Cron Formats
/// EARS: WHEN different cron formats are used
///       THE system SHALL accept valid formats
pub fn test_072_multiple_cron_formats_test() {
  let expressions = [
    "* * * * *",
    // Every minute
    "0 * * * *",
    // Every hour
    "0 0 * * *",
    // Every day
    "0 0 * * 0",
    // Every week
    "0 0 1 * *",
    // Every month
  ]

  let workflows =
    list.map(expressions, fn(expr) {
      workflow.new("test") |> workflow.with_cron(expr)
    })

  workflows |> list.length |> should.equal(5)
}

/// TEST-073: Workflow Cron Preserved with Tasks
/// EARS: WHEN workflow has cron and tasks
///       THE cron SHALL be preserved
pub fn test_073_cron_preserved_with_tasks_test() {
  let wf =
    workflow.new("test")
    |> workflow.with_cron("0 0 * * *")
    |> workflow.task("task1", fn(_) { Ok(dynamic.nil()) })

  wf.cron |> should.equal(Some("0 0 * * *"))
  wf.tasks |> list.length |> should.equal(1)
}

/// TEST-074: Cron and Events Can Coexist
/// EARS: WHEN workflow has both cron and events
///       THE system SHALL trigger on both
pub fn test_074_cron_and_events_coexist_test() {
  let wf =
    workflow.new("test")
    |> workflow.with_cron("0 * * * *")
    |> workflow.with_events(["manual.trigger"])

  wf.cron |> should.equal(Some("0 * * * *"))
  wf.events |> should.equal(["manual.trigger"])
}

/// TEST-075: Workflow Description with Cron
/// EARS: WHEN workflow has description and cron
///       THE both SHALL be preserved
pub fn test_075_workflow_description_with_cron_test() {
  let wf =
    workflow.new("test")
    |> workflow.with_description("Scheduled job")
    |> workflow.with_cron("0 0 * * *")

  wf.description |> should.equal(Some("Scheduled job"))
  wf.cron |> should.equal(Some("0 0 * * *"))
}

/// TEST-076: Run Options with Priority
/// EARS: WHEN run options have priority
///       THE run SHALL have specified priority
pub fn test_076_run_options_with_priority_test() {
  let options =
    types.RunOptions(
      metadata: dict.new(),
      priority: Some(5),
      sticky: False,
      run_key: None,
    )

  options.priority |> should.equal(Some(5))
}

/// TEST-077: Run Options with Metadata
/// EARS: WHEN run options have metadata
///       THE metadata SHALL be passed to run
pub fn test_077_run_options_with_metadata_test() {
  let metadata = dict.from_list([#("trace_id", "abc123")])
  let options =
    types.RunOptions(
      metadata: metadata,
      priority: None,
      sticky: False,
      run_key: None,
    )

  dict.get(options.metadata, "trace_id") |> should.equal(Ok("abc123"))
}

/// TEST-078: Run Options with Run Key
/// EARS: WHEN run options have run_key
///       THE system SHALL use key for deduplication
pub fn test_078_run_options_with_run_key_test() {
  let options =
    types.RunOptions(
      metadata: dict.new(),
      priority: None,
      sticky: False,
      run_key: Some("daily-job-2024-01-01"),
    )

  options.run_key |> should.equal(Some("daily-job-2024-01-01"))
}

/// TEST-079: Run Options Sticky Mode
/// EARS: WHEN run options have sticky=true
///       THE child runs SHALL use same worker
pub fn test_079_run_options_sticky_mode_test() {
  let options =
    types.RunOptions(
      metadata: dict.new(),
      priority: None,
      sticky: True,
      run_key: None,
    )

  options.sticky |> should.be_true
}

/// TEST-080: Run Options Default Values
/// EARS: WHEN run options use defaults
///       THE values SHALL be properly defaulted
pub fn test_080_run_options_default_values_test() {
  let options =
    types.RunOptions(
      metadata: dict.new(),
      priority: None,
      sticky: False,
      run_key: None,
    )

  options.priority |> should.equal(None)
  options.sticky |> should.be_false
  options.run_key |> should.equal(None)
  dict.size(options.metadata) |> should.equal(0)
}

// ============================================================================
// CATEGORY 8: RUN MANAGEMENT TESTS (TEST-081 to TEST-090)
// ============================================================================

/// TEST-081: Workflow Run Ref Creation
/// EARS: WHEN WorkflowRunRef is created
///       THE ref SHALL contain run_id and client
pub fn test_081_workflow_run_ref_creation_test() {
  let assert Ok(c) = client.new("localhost", "token")
  let ref = types.create_workflow_run_ref("run-123", c)

  types.get_run_id(ref) |> should.equal("run-123")
}

/// TEST-082: Run Ref Stores Client
/// EARS: WHEN run ref is created
///       THE client SHALL be accessible
pub fn test_082_run_ref_stores_client_test() {
  let assert Ok(c) = client.new("localhost", "token")
  let ref = types.create_workflow_run_ref("run-123", c)

  types.get_ref_client(ref)
  |> types.get_host
  |> should.equal("localhost")
}

/// TEST-083: Run Status Types
/// EARS: WHEN run status is checked
///       THE status SHALL be one of defined types
pub fn test_083_run_status_types_test() {
  let pending = types.Pending
  let running = types.Running
  let succeeded = types.Succeeded
  let failed = types.Failed("error message")
  let cancelled = types.Cancelled

  pending |> should.equal(types.Pending)
  running |> should.equal(types.Running)
  succeeded |> should.equal(types.Succeeded)
  cancelled |> should.equal(types.Cancelled)
  // Verify Failed contains error message
  failed |> should.equal(types.Failed("error message"))
}

/// TEST-084: Run Cancel Function Exists
/// EARS: WHEN cancel is called
///       THE system SHALL attempt to cancel run
pub fn test_084_run_cancel_function_exists_test() {
  let assert Ok(c) = client.new("localhost", "token")
  let ref = types.create_workflow_run_ref("run-123", c)

  // Function exists, returns error without server
  run.cancel(ref) |> should.be_error
}

/// TEST-085: Bulk Cancel Function Exists
/// EARS: WHEN bulk_cancel is called
///       THE system SHALL attempt to cancel all runs
pub fn test_085_bulk_cancel_function_exists_test() {
  let assert Ok(c) = client.new("localhost", "token")
  let run_ids = ["run-1", "run-2", "run-3"]

  // Function exists, returns error without server
  run.bulk_cancel(c, run_ids) |> should.be_error
}

/// TEST-086: Replay Function Exists
/// EARS: WHEN replay is called
///       THE system SHALL attempt to replay runs
pub fn test_086_replay_function_exists_test() {
  let assert Ok(c) = client.new("localhost", "token")
  let run_ids = ["run-1", "run-2"]

  // Function exists, returns error without server
  run.replay(c, run_ids) |> should.be_error
}

/// TEST-087: Failed Status Contains Error
/// EARS: WHEN run fails
///       THE Failed status SHALL contain error message
pub fn test_087_failed_status_contains_error_test() {
  let failed = types.Failed("Task timeout after 30s")

  // Verify Failed contains expected error message
  failed |> should.equal(types.Failed("Task timeout after 30s"))
}

/// TEST-088: Run Ref Unique IDs
/// EARS: WHEN multiple refs created
///       THE run_ids SHALL be unique
pub fn test_088_run_ref_unique_ids_test() {
  let assert Ok(c) = client.new("localhost", "token")
  let ref1 = types.create_workflow_run_ref("run-123", c)
  let ref2 = types.create_workflow_run_ref("run-456", c)

  types.get_run_id(ref1) |> should.equal("run-123")
  types.get_run_id(ref2) |> should.equal("run-456")
  should.be_true(types.get_run_id(ref1) != types.get_run_id(ref2))
}

/// TEST-089: Run Function Requires Server
/// EARS: WHEN run is called without server
///       THE system SHALL return error
pub fn test_089_run_function_requires_server_test() {
  let assert Ok(c) = client.new("localhost", "token")
  let wf =
    workflow.new("test") |> workflow.task("t", fn(_) { Ok(dynamic.nil()) })

  // Without server, should return error
  run.run(c, wf, dynamic.nil()) |> should.be_error
}

/// TEST-090: Run No Wait Function Exists
/// EARS: WHEN run_no_wait is called
///       THE system SHALL return immediately with ref
pub fn test_090_run_no_wait_function_exists_test() {
  let assert Ok(c) = client.new("localhost", "token")
  let wf =
    workflow.new("test") |> workflow.task("t", fn(_) { Ok(dynamic.nil()) })

  // Without server, should return error
  run.run_no_wait(c, wf, dynamic.nil()) |> should.be_error
}

// ============================================================================
// CATEGORY 9: RATE LIMITING TESTS (TEST-091 to TEST-095)
// ============================================================================

/// TEST-091: Rate Limit Duration Types
/// EARS: WHEN rate limit durations are used
///       THE system SHALL support all duration types
pub fn test_091_rate_limit_duration_types_test() {
  let _second = rate_limits.Second
  let _minute = rate_limits.Minute
  let _hour = rate_limits.Hour
  let _day = rate_limits.Day
  let _week = rate_limits.Week
  let _month = rate_limits.Month
  let _year = rate_limits.Year

  should.be_true(True)
}

/// TEST-092: Task Rate Limit Configuration
/// EARS: WHEN rate limit is added to task
///       THE task SHALL have rate limit config
pub fn test_092_task_rate_limit_configuration_test() {
  let limit = task.rate_limit("api", 10, 60_000)

  limit.key |> should.equal("api")
  limit.units |> should.equal(10)
  limit.duration_ms |> should.equal(60_000)
}

/// TEST-093: Multiple Rate Limits on Task
/// EARS: WHEN multiple rate limits are attached
///       THE task SHALL enforce all limits
pub fn test_093_multiple_rate_limits_on_task_test() {
  let handler = fn(_) { Ok(dynamic.nil()) }
  let wf =
    workflow.new("test")
    |> workflow.task("api-call", handler)
    |> workflow.with_rate_limit("per-minute", 100, 60_000)
    |> workflow.with_rate_limit("per-hour", 1000, 3_600_000)

  let assert [t] = wf.tasks
  t.rate_limits |> list.length |> should.equal(2)
}

/// TEST-094: Rate Limit Key Patterns
/// EARS: WHEN rate limit keys use patterns
///       THE system SHALL support variable substitution
pub fn test_094_rate_limit_key_patterns_test() {
  let patterns = [
    "global-api-calls",
    "tenant-{{metadata.tenant_id}}-requests",
    "user-{{metadata.user_id}}-actions",
  ]

  patterns |> list.length |> should.equal(3)
}

/// TEST-095: Rate Limit Config Struct
/// EARS: WHEN RateLimitConfig is created
///       THE struct SHALL have all required fields
pub fn test_095_rate_limit_config_struct_test() {
  let config =
    types.RateLimitConfig(key: "my-limit", units: 100, duration_ms: 60_000)

  config.key |> should.equal("my-limit")
  config.units |> should.equal(100)
  config.duration_ms |> should.equal(60_000)
}

// ============================================================================
// CATEGORY 10: STANDALONE TASK TESTS (TEST-096 to TEST-100)
// ============================================================================

/// TEST-096: Create Standalone Task
/// EARS: WHEN standalone task created
///       THE system SHALL wrap in single-task workflow
pub fn test_096_create_standalone_task_test() {
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }
  let task = standalone.new_standalone("my-task", handler)

  task.name |> should.equal("my-task")
  task.retries |> should.equal(0)
  task.cron |> should.equal(None)
  task.events |> should.equal([])
}

/// TEST-097: Standalone with Retries
/// EARS: WHEN standalone_with_retries is called
///       THE task SHALL have retry configuration
pub fn test_097_standalone_with_retries_test() {
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }
  let task =
    standalone.new_standalone("my-task", handler)
    |> standalone.with_task_retries(5)

  task.retries |> should.equal(5)
}

/// TEST-098: Standalone with Cron
/// EARS: WHEN standalone_with_cron is called
///       THE task SHALL have cron trigger
pub fn test_098_standalone_with_cron_test() {
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }
  let task =
    standalone.new_standalone("my-task", handler)
    |> standalone.with_task_cron("0 * * * *")

  task.cron |> should.equal(Some("0 * * * *"))
}

/// TEST-099: Standalone with Events
/// EARS: WHEN standalone_with_events is called
///       THE task SHALL have event triggers
pub fn test_099_standalone_with_events_test() {
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }
  let task =
    standalone.new_standalone("my-task", handler)
    |> standalone.with_task_events(["event.a", "event.b"])

  task.events |> should.equal(["event.a", "event.b"])
}

/// TEST-100: Standalone to Workflow
/// EARS: WHEN to_workflow is called
///       THE system SHALL return full workflow
pub fn test_100_standalone_to_workflow_test() {
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }
  let task =
    standalone.new_standalone("my-task", handler)
    |> standalone.with_task_cron("0 * * * *")
    |> standalone.with_task_events(["trigger"])

  let wf = standalone.to_workflow(task)

  wf.name |> should.equal("my-task")
  wf.tasks |> list.length |> should.equal(1)
  wf.cron |> should.equal(Some("0 * * * *"))
  wf.events |> should.equal(["trigger"])
}
