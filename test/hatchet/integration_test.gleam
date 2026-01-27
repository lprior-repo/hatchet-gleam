import gleam/dict
import gleam/list
import gleam/option
import gleam/string
import gleeunit/should
import hatchet
import hatchet/internal/json as hatchet_json
import hatchet/internal/protocol as p
import hatchet/types

pub fn simple_workflow_definition_test() {
  let workflow =
    hatchet.workflow_new("test-workflow")
    |> hatchet.workflow_with_description("A simple test workflow")

  workflow.name
  |> should.equal("test-workflow")

  workflow.description
  |> should.equal(option.Some("A simple test workflow"))
}

pub fn task_count_test() {
  let workflow =
    hatchet.workflow_new("task-workflow")
    |> hatchet.workflow_task("simple-task", fn(ctx) { Ok(ctx.input) })

  list.length(workflow.tasks)
  |> should.equal(1)
}

pub fn client_creation_test() {
  let assert Ok(client) = hatchet.new("localhost", "test-token")

  types.get_host(client)
  |> should.equal("localhost")

  types.get_token(client)
  |> should.equal("test-token")
}

pub fn worker_config_test() {
  let config = hatchet.worker_config()

  config.slots
  |> should.equal(10)

  config.durable_slots
  |> should.equal(1)
}

pub fn with_slots_test() {
  let config =
    hatchet.worker_config()
    |> hatchet.worker_with_slots(10)

  config.slots
  |> should.equal(10)
}

pub fn with_labels_test() {
  let config =
    hatchet.worker_config()
    |> hatchet.worker_with_labels(
      dict.from_list([#("env", "test"), #("version", "1.0.0")]),
    )

  config.labels
  |> should.equal(dict.from_list([#("env", "test"), #("version", "1.0.0")]))
}

pub fn multi_task_workflow_with_dependencies_test() {
  let workflow =
    hatchet.workflow_new("order-processing")
    |> hatchet.workflow_with_description("Process customer orders")
    |> hatchet.workflow_with_version("1.0.0")
    |> hatchet.workflow_task("validate", fn(ctx) { Ok(ctx.input) })
    |> hatchet.workflow_task_after("charge", ["validate"], fn(ctx) {
      Ok(ctx.input)
    })
    |> hatchet.workflow_task_after("fulfill", ["charge"], fn(ctx) {
      Ok(ctx.input)
    })

  workflow.name
  |> should.equal("order-processing")

  workflow.version
  |> should.equal(option.Some("1.0.0"))

  list.length(workflow.tasks)
  |> should.equal(3)

  let validate_task = list.find(workflow.tasks, fn(t) { t.name == "validate" })
  let charge_task = list.find(workflow.tasks, fn(t) { t.name == "charge" })
  let fulfill_task = list.find(workflow.tasks, fn(t) { t.name == "fulfill" })

  validate_task
  |> should.be_ok()

  charge_task
  |> should.be_ok()

  fulfill_task
  |> should.be_ok()
}

pub fn workflow_with_triggers_test() {
  let workflow =
    hatchet.workflow_new("scheduled-task")
    |> hatchet.workflow_with_cron("0 0 * * *")
    |> hatchet.workflow_with_events(["user.created", "order.placed"])
    |> hatchet.workflow_task("process", fn(ctx) { Ok(ctx.input) })

  workflow.cron
  |> should.equal(option.Some("0 0 * * *"))

  workflow.events
  |> should.equal(["user.created", "order.placed"])
}

pub fn workflow_with_concurrency_test() {
  let workflow =
    hatchet.workflow_new("concurrent-workflow")
    |> hatchet.workflow_with_concurrency(10, types.CancelInProgress)
    |> hatchet.workflow_task("task1", fn(ctx) { Ok(ctx.input) })

  workflow.concurrency
  |> should.equal(
    option.Some(types.ConcurrencyConfig(10, types.CancelInProgress)),
  )
}

pub fn task_configuration_test() {
  let workflow =
    hatchet.workflow_new("task-config-test")
    |> hatchet.workflow_task("task1", fn(ctx) { Ok(ctx.input) })
    |> hatchet.workflow_with_retries(5)
    |> hatchet.workflow_with_timeout(30_000)

  let task = list.find(workflow.tasks, fn(t) { t.name == "task1" })
  let assert Ok(task_def) = task

  task_def.retries
  |> should.equal(5)

  task_def.execution_timeout_ms
  |> should.equal(option.Some(30_000))
}

pub fn workflow_json_encoding_test() {
  let req =
    p.WorkflowCreateRequest(
      name: "test-workflow",
      description: option.Some("A test workflow"),
      version: option.Some("1.0.0"),
      tasks: [],
      cron: option.Some("0 0 * * *"),
      events: ["user.created"],
      concurrency: option.None,
    )

  let json_string = hatchet_json.encode_workflow_create(req)

  string.contains(json_string, "test-workflow")
  |> should.equal(True)

  string.contains(json_string, "1.0.0")
  |> should.equal(True)

  string.contains(json_string, "user.created")
  |> should.equal(True)
}

pub fn backoff_encoding_test() {
  let exponential = p.ExponentialCreate(1000, 60_000)
  let linear = p.LinearCreate(5000, 120_000)
  let constant = p.ConstantCreate(2000)

  let _exp_json = hatchet_json.encode_backoff(exponential)
  let _lin_json = hatchet_json.encode_backoff(linear)
  let _const_json = hatchet_json.encode_backoff(constant)

  Ok(Nil)
  |> should.be_ok()
}

pub fn client_configuration_test() {
  let assert Ok(client) = hatchet.new("hatchet.example.com", "secret-token")
  let client_with_port = hatchet.with_port(client, 7070)
  let client_with_namespace =
    hatchet.with_namespace(client_with_port, "production")

  types.get_host(client_with_namespace)
  |> should.equal("hatchet.example.com")

  types.get_port(client_with_namespace)
  |> should.equal(7070)

  types.get_namespace(client_with_namespace)
  |> should.equal(option.Some("production"))
}
