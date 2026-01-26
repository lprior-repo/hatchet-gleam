import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/json as gleam_json
import gleam/option
import gleam/string
import gleeunit/should
import hatchet/internal/json as hatchet_json
import hatchet/internal/protocol as p

pub fn encode_workflow_create_test() {
  let req =
    p.WorkflowCreateRequest(
      name: "test-workflow",
      description: option.Some("Test workflow"),
      version: option.Some("1.0.0"),
      tasks: [],
      cron: option.Some("0 * * * *"),
      events: ["event1"],
      concurrency: option.None,
    )

  let encoded = hatchet_json.encode_workflow_create(req)

  string.contains(encoded, "test-workflow")
  |> should.equal(True)

  string.contains(encoded, "Test workflow")
  |> should.equal(True)

  string.contains(encoded, "event1")
  |> should.equal(True)
}

pub fn encode_task_create_test() {
  let task =
    p.TaskCreate(
      name: "task1",
      parents: ["parent1"],
      retries: 3,
      retry_backoff: option.None,
      execution_timeout_ms: option.Some(30_000),
      schedule_timeout_ms: option.None,
      rate_limits: [],
      concurrency: option.None,
      wait_for: option.None,
    )

  let encoded = hatchet_json.encode_task_create(task)

  let json_str = gleam_json.to_string(encoded)

  string.contains(json_str, "task1")
  |> should.equal(True)

  string.contains(json_str, "parent1")
  |> should.equal(True)

  string.contains(json_str, "3")
  |> should.equal(True)
}

pub fn encode_backoff_test() {
  let exponential = p.ExponentialCreate(1000, 60_000)
  let linear = p.LinearCreate(2000, 60_000)
  let constant = p.ConstantCreate(5000)

  let exp_encoded = hatchet_json.encode_backoff(exponential)
  let lin_encoded = hatchet_json.encode_backoff(linear)
  let const_encoded = hatchet_json.encode_backoff(constant)

  let exp_str = gleam_json.to_string(exp_encoded)
  let lin_str = gleam_json.to_string(lin_encoded)
  let const_str = gleam_json.to_string(const_encoded)

  string.contains(exp_str, "exponential")
  |> should.equal(True)

  string.contains(lin_str, "linear")
  |> should.equal(True)

  string.contains(const_str, "constant")
  |> should.equal(True)
}

pub fn encode_rate_limit_test() {
  let limit = p.RateLimitCreate(key: "api", units: 10, duration_ms: 60_000)

  let encoded = hatchet_json.encode_rate_limit(limit)

  let json_str = gleam_json.to_string(encoded)

  string.contains(json_str, "api")
  |> should.equal(True)

  string.contains(json_str, "10")
  |> should.equal(True)
}

pub fn encode_concurrency_test() {
  let concurrency =
    p.ConcurrencyCreate(max_concurrent: 10, limit_strategy: "CancelInProgress")

  let encoded = hatchet_json.encode_concurrency(concurrency)

  let json_str = gleam_json.to_string(encoded)

  string.contains(json_str, "10")
  |> should.equal(True)

  string.contains(json_str, "CancelInProgress")
  |> should.equal(True)
}

pub fn encode_wait_test() {
  let event_wait = p.WaitForEventCreate(event: "test-event", timeout_ms: 30_000)
  let time_wait = p.WaitForTimeCreate(duration_ms: 5000)
  let expr_wait = p.WaitForExpressionCreate(cel: "input.value > 10")

  let event_encoded = hatchet_json.encode_wait(event_wait)
  let time_encoded = hatchet_json.encode_wait(time_wait)
  let expr_encoded = hatchet_json.encode_wait(expr_wait)

  let event_str = gleam_json.to_string(event_encoded)
  let time_str = gleam_json.to_string(time_encoded)
  let expr_str = gleam_json.to_string(expr_encoded)

  string.contains(event_str, "event")
  |> should.equal(True)

  string.contains(time_str, "time")
  |> should.equal(True)

  string.contains(expr_str, "expression")
  |> should.equal(True)
}

pub fn encode_workflow_run_test() {
  let input_dynamic = dynamic.string("test-input")

  let req =
    p.WorkflowRunRequest(
      workflow_name: "test-workflow",
      input: input_dynamic,
      metadata: dict.from_list([#("key1", "value1")]),
      priority: option.Some(1),
      sticky: True,
      run_key: option.Some("run-123"),
    )

  let encoded = hatchet_json.encode_workflow_run(req)

  string.contains(encoded, "test-workflow")
  |> should.equal(True)

  string.contains(encoded, "true")
  |> should.equal(True)
}

pub fn encode_event_publish_test() {
  let data_dynamic = dynamic.string("test-data")

  let req =
    p.EventPublishRequest(
      event_key: "test-event",
      data: data_dynamic,
      metadata: dict.from_list([#("key1", "value1")]),
    )

  let encoded = hatchet_json.encode_event_publish(req)

  string.contains(encoded, "test-event")
  |> should.equal(True)
}

pub fn decode_workflow_run_response_test() {
  let json_string =
    gleam_json.object([
      #("run_id", gleam_json.string("run-123")),
      #("status", gleam_json.string("pending")),
    ])
    |> gleam_json.to_string()

  let assert Ok(resp) = hatchet_json.decode_workflow_run_response(json_string)

  resp.run_id
  |> should.equal("run-123")

  resp.status
  |> should.equal("pending")
}

pub fn decode_workflow_status_response_test() {
  let json_string =
    gleam_json.object([
      #("run_id", gleam_json.string("run-123")),
      #("status", gleam_json.string("succeeded")),
      #("output", gleam_json.string("result")),
      #("error", gleam_json.null()),
    ])
    |> gleam_json.to_string()

  let assert Ok(resp) =
    hatchet_json.decode_workflow_status_response(json_string)

  resp.run_id
  |> should.equal("run-123")

  resp.status
  |> should.equal("succeeded")
}

pub fn decode_worker_register_response_test() {
  let json_string =
    gleam_json.object([#("worker_id", gleam_json.string("worker-123"))])
    |> gleam_json.to_string()

  let assert Ok(resp) =
    hatchet_json.decode_worker_register_response(json_string)

  resp.worker_id
  |> should.equal("worker-123")
}

pub fn decode_cancel_response_test() {
  let json_string =
    gleam_json.object([#("success", gleam_json.bool(True))])
    |> gleam_json.to_string()

  let assert Ok(resp) = hatchet_json.decode_cancel_response(json_string)

  resp.success
  |> should.equal(True)
}
