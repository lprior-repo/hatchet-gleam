import gleam/dynamic
import gleam/list
import gleam/option
import gleeunit/should
import hatchet/standalone

pub fn new_standalone_test() {
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }
  let task = standalone.new_standalone("my-task", handler)

  task.name
  |> should.equal("my-task")

  task.retries
  |> should.equal(0)

  task.cron
  |> should.equal(option.None)

  task.events
  |> should.equal([])
}

pub fn with_task_retries_test() {
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }
  let task =
    standalone.new_standalone("my-task", handler)
    |> standalone.with_task_retries(5)

  task.retries
  |> should.equal(5)
}

pub fn with_task_cron_test() {
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }
  let task =
    standalone.new_standalone("my-task", handler)
    |> standalone.with_task_cron("0 * * * *")

  task.cron
  |> should.equal(option.Some("0 * * * *"))
}

pub fn with_task_events_test() {
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }
  let task =
    standalone.new_standalone("my-task", handler)
    |> standalone.with_task_events(["event1", "event2"])

  task.events
  |> should.equal(["event1", "event2"])
}

pub fn to_workflow_test() {
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }
  let task = standalone.new_standalone("my-task", handler)
  let wf = standalone.to_workflow(task)

  wf.name
  |> should.equal("my-task")

  wf.tasks
  |> list.length
  |> should.equal(1)
}

pub fn to_workflow_with_cron_test() {
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }
  let task =
    standalone.new_standalone("my-task", handler)
    |> standalone.with_task_cron("0 * * * *")

  let wf = standalone.to_workflow(task)

  wf.cron
  |> should.equal(option.Some("0 * * * *"))
}

pub fn to_workflow_with_events_test() {
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }
  let task =
    standalone.new_standalone("my-task", handler)
    |> standalone.with_task_events(["event1", "event2"])

  let wf = standalone.to_workflow(task)

  wf.events
  |> should.equal(["event1", "event2"])
}
