import gleam/dynamic
import gleam/list
import gleam/option
import gleeunit/should
import hatchet/types.{CancelInProgress, Exponential, QueueNew}
import hatchet/workflow

pub fn workflow_new_test() {
  let wf = workflow.new("test-workflow")

  wf.name
  |> should.equal("test-workflow")

  wf.description
  |> should.equal(option.None)

  wf.version
  |> should.equal(option.None)

  wf.tasks
  |> should.equal([])

  wf.cron
  |> should.equal(option.None)

  wf.events
  |> should.equal([])
}

pub fn workflow_with_description_test() {
  let wf =
    workflow.new("test-workflow")
    |> workflow.with_description("A test workflow")

  wf.description
  |> should.equal(option.Some("A test workflow"))
}

pub fn workflow_with_version_test() {
  let wf =
    workflow.new("test-workflow")
    |> workflow.with_version("1.0.0")

  wf.version
  |> should.equal(option.Some("1.0.0"))
}

pub fn workflow_with_cron_test() {
  let wf =
    workflow.new("test-workflow")
    |> workflow.with_cron("0 * * * *")

  wf.cron
  |> should.equal(option.Some("0 * * * *"))
}

pub fn workflow_with_events_test() {
  let wf =
    workflow.new("test-workflow")
    |> workflow.with_events(["order.created"])
    |> workflow.with_events(["payment.completed"])

  wf.events
  |> should.equal(["order.created", "payment.completed"])
}

pub fn workflow_with_concurrency_test() {
  let wf =
    workflow.new("test-workflow")
    |> workflow.with_concurrency(10, CancelInProgress)

  let assert option.Some(config) = wf.concurrency
  config.max_concurrent
  |> should.equal(10)
}

pub fn workflow_add_task_test() {
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }
  let wf =
    workflow.new("test-workflow")
    |> workflow.task("task1", handler)

  wf.tasks
  |> list.length
  |> should.equal(1)
}

pub fn workflow_add_task_after_test() {
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }
  let wf =
    workflow.new("test-workflow")
    |> workflow.task("task1", handler)
    |> workflow.task_after("task2", ["task1"], handler)

  wf.tasks
  |> list.length
  |> should.equal(2)
}

pub fn workflow_with_retries_test() {
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }
  let wf =
    workflow.new("test-workflow")
    |> workflow.task("task1", handler)
    |> workflow.with_retries(5)

  wf.tasks
  |> list.length
  |> should.equal(1)
}

pub fn workflow_with_timeout_test() {
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }
  let wf =
    workflow.new("test-workflow")
    |> workflow.task("task1", handler)
    |> workflow.with_timeout(30_000)

  wf.tasks
  |> list.length
  |> should.equal(1)
}

pub fn workflow_with_retry_backoff_test() {
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }
  let backoff = Exponential(base_ms: 1000, max_ms: 60_000)
  let wf =
    workflow.new("test-workflow")
    |> workflow.task("task1", handler)
    |> workflow.with_retry_backoff(backoff)

  wf.tasks
  |> list.length
  |> should.equal(1)
}

pub fn workflow_with_rate_limit_test() {
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }
  let wf =
    workflow.new("test-workflow")
    |> workflow.task("task1", handler)
    |> workflow.with_rate_limit("api", 10, 60_000)

  wf.tasks
  |> list.length
  |> should.equal(1)
}

pub fn workflow_with_task_concurrency_test() {
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }
  let wf =
    workflow.new("test-workflow")
    |> workflow.task("task1", handler)
    |> workflow.with_task_concurrency(5, QueueNew)

  wf.tasks
  |> list.length
  |> should.equal(1)
}

pub fn workflow_on_failure_test() {
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }
  let failure_handler = fn(_ctx) { Ok(Nil) }
  let wf =
    workflow.new("test-workflow")
    |> workflow.task("task1", handler)
    |> workflow.on_failure(failure_handler)

  wf.on_failure
  |> should.not_equal(option.None)
}
