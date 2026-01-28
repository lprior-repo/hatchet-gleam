import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/option
import gleeunit/should
import hatchet/task
import hatchet/types.{
  Constant, DropNew, Exponential, Linear, TaskContext, TaskDef, WaitForEvent,
  WaitForExpression, WaitForTime,
}

pub fn backoff_configs_test() {
  let exponential = task.exponential_backoff(1000, 60_000)

  case exponential {
    Exponential(base_ms, max_ms) -> {
      base_ms
      |> should.equal(1000)

      max_ms
      |> should.equal(60_000)
    }
    _ -> panic as "Test failed"
  }

  let linear = task.linear_backoff(2000, 60_000)

  case linear {
    Linear(step_ms, max_ms) -> {
      step_ms
      |> should.equal(2000)

      max_ms
      |> should.equal(60_000)
    }
    _ -> panic as "Test failed"
  }

  let constant = task.constant_backoff(5000)

  case constant {
    Constant(delay_ms) -> {
      delay_ms
      |> should.equal(5000)
    }
    _ -> panic as "Test failed"
  }
}

pub fn default_backoff_test() {
  let exponential = task.exponential_backoff_default()

  case exponential {
    Exponential(base_ms, max_ms) -> {
      base_ms
      |> should.equal(1000)

      max_ms
      |> should.equal(60_000)
    }
    _ -> panic as "Test failed"
  }

  let linear = task.linear_backoff_default()

  case linear {
    Linear(step_ms, max_ms) -> {
      step_ms
      |> should.equal(2000)

      max_ms
      |> should.equal(60_000)
    }
    _ -> panic as "Test failed"
  }

  let constant = task.constant_backoff_default()

  case constant {
    Constant(delay_ms) -> {
      delay_ms
      |> should.equal(5000)
    }
    _ -> panic as "Test failed"
  }
}

pub fn rate_limit_test() {
  let limit = task.rate_limit("api", 10, 60_000)

  limit.key
  |> should.equal("api")

  limit.units
  |> should.equal(10)

  limit.duration_ms
  |> should.equal(60_000)
}

pub fn wait_conditions_test() {
  let event_wait = task.wait_for_event("order.created", 30_000)

  case event_wait {
    WaitForEvent(event, timeout_ms) -> {
      event
      |> should.equal("order.created")

      timeout_ms
      |> should.equal(30_000)
    }
    _ -> panic as "Test failed"
  }

  let time_wait = task.wait_for_time(5000)

  case time_wait {
    WaitForTime(duration_ms) -> {
      duration_ms
      |> should.equal(5000)
    }
    _ -> panic as "Test failed"
  }

  let expr_wait = task.wait_for_expression("input.value > 10")

  case expr_wait {
    WaitForExpression(cel) -> {
      cel
      |> should.equal("input.value > 10")
    }
    _ -> panic as "Test failed"
  }
}

pub fn task_context_accessors_test() {
  let ctx =
    TaskContext(
      workflow_run_id: "wf-123",
      task_run_id: "task-456",
      input: dynamic.string("test-input"),
      parent_outputs: dict.from_list([#("task1", dynamic.string("output1"))]),
      metadata: dict.from_list([#("key1", "value1")]),
      step_run_errors: dict.from_list([#("failed-task", "error message")]),
      logger: fn(_) { Nil },
      stream_fn: fn(_) { Ok(Nil) },
      release_slot_fn: fn() { Ok(Nil) },
      refresh_timeout_fn: fn(_) { Ok(Nil) },
      cancel_fn: fn() { Ok(Nil) },
      spawn_workflow_fn: fn(workflow_name, input, metadata) {
        Ok("workflow-run-id")
      },
    )

  task.get_workflow_run_id(ctx)
  |> should.equal("wf-123")

  task.get_task_run_id(ctx)
  |> should.equal("task-456")

  task.get_input(ctx)
  |> decode.run(decode.string)
  |> should.equal(Ok("test-input"))

  task.get_metadata(ctx, "key1")
  |> should.equal(option.Some("value1"))

  task.get_metadata(ctx, "missing")
  |> should.equal(option.None)

  task.get_all_metadata(ctx)
  |> should.equal(dict.from_list([#("key1", "value1")]))
}

pub fn get_parent_output_test() {
  let ctx =
    TaskContext(
      workflow_run_id: "wf-123",
      task_run_id: "task-456",
      input: dynamic.string("test-input"),
      parent_outputs: dict.from_list([#("task1", dynamic.string("output1"))]),
      metadata: dict.new(),
      step_run_errors: dict.new(),
      logger: fn(_) { Nil },
      stream_fn: fn(_) { Ok(Nil) },
      release_slot_fn: fn() { Ok(Nil) },
      refresh_timeout_fn: fn(_) { Ok(Nil) },
      cancel_fn: fn() { Ok(Nil) },
      spawn_workflow_fn: fn(workflow_name, input, metadata) {
        Ok("workflow-run-id")
      },
    )

  task.get_parent_output(ctx, "task1")
  |> should.equal(option.Some(dynamic.string("output1")))

  task.get_parent_output(ctx, "missing")
  |> should.equal(option.None)
}

pub fn task_result_helpers_test() {
  let success = task.succeed(dynamic.string("result"))

  success
  |> should.equal(Ok(dynamic.string("result")))

  let success_from = task.succeed(dynamic.int(42))

  success_from
  |> should.equal(Ok(dynamic.int(42)))

  let failure = task.fail("error message")

  failure
  |> should.equal(Error("error message"))
}

pub fn map_result_test() {
  let result = Ok(dynamic.int(42))

  let assert Ok(mapped) =
    task.map_result(result, fn(d) { decode.run(d, decode.int) })
  mapped
  |> should.equal(42)

  let error_result = Error("test error")

  let assert Error(err) =
    task.map_result(error_result, fn(d) { decode.run(d, decode.int) })
  err
  |> should.equal("test error")
}

pub fn standalone_task_test() {
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }
  let task = task.standalone("my-task", handler)

  task.name
  |> should.equal("my-task")

  task.retries
  |> should.equal(0)

  task.cron
  |> should.equal(option.None)

  task.events
  |> should.equal([])
}

pub fn standalone_with_retries_test() {
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }
  let task = task.standalone_with_retries("my-task", handler, 5)

  task.retries
  |> should.equal(5)
}

pub fn standalone_with_cron_test() {
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }
  let task = task.standalone_with_cron("my-task", handler, "0 * * * *")

  task.cron
  |> should.equal(option.Some("0 * * * *"))
}

pub fn standalone_with_events_test() {
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }
  let task =
    task.standalone_with_events("my-task", handler, ["event1", "event2"])

  task.events
  |> should.equal(["event1", "event2"])
}

pub fn task_with_retry_backoff_test() {
  let backoff = task.exponential_backoff(1000, 60_000)
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }

  let base_task =
    TaskDef(
      name: "test",
      handler: handler,
      parents: [],
      retries: 0,
      retry_backoff: option.None,
      execution_timeout_ms: option.None,
      schedule_timeout_ms: option.None,
      rate_limits: [],
      concurrency: option.None,
      skip_if: option.None,
      wait_for: option.None,
      is_durable: False,
      checkpoint_key: option.None,
    )

  let updated = task.with_retry_backoff(base_task, backoff)

  updated.retry_backoff
  |> should.equal(option.Some(backoff))
}

pub fn task_with_schedule_timeout_test() {
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }

  let base_task =
    TaskDef(
      name: "test",
      handler: handler,
      parents: [],
      retries: 0,
      retry_backoff: option.None,
      execution_timeout_ms: option.None,
      schedule_timeout_ms: option.None,
      rate_limits: [],
      concurrency: option.None,
      skip_if: option.None,
      wait_for: option.None,
      is_durable: False,
      checkpoint_key: option.None,
    )

  let updated = task.with_schedule_timeout(base_task, 10_000)

  updated.schedule_timeout_ms
  |> should.equal(option.Some(10_000))
}

pub fn task_with_rate_limit_test() {
  let limit = task.rate_limit("api", 10, 60_000)
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }

  let base_task =
    TaskDef(
      name: "test",
      handler: handler,
      parents: [],
      retries: 0,
      retry_backoff: option.None,
      execution_timeout_ms: option.None,
      schedule_timeout_ms: option.None,
      rate_limits: [],
      concurrency: option.None,
      skip_if: option.None,
      wait_for: option.None,
      is_durable: False,
      checkpoint_key: option.None,
    )

  let updated = task.with_rate_limit(base_task, limit)

  updated.rate_limits
  |> should.equal([limit])
}

pub fn task_with_concurrency_test() {
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }

  let base_task =
    TaskDef(
      name: "test",
      handler: handler,
      parents: [],
      retries: 0,
      retry_backoff: option.None,
      execution_timeout_ms: option.None,
      schedule_timeout_ms: option.None,
      rate_limits: [],
      concurrency: option.None,
      skip_if: option.None,
      wait_for: option.None,
      is_durable: False,
      checkpoint_key: option.None,
    )

  let updated = task.with_task_concurrency(base_task, 5, DropNew)

  case updated.concurrency {
    option.Some(config) -> {
      config.max_concurrent
      |> should.equal(5)

      config.limit_strategy
      |> should.equal(DropNew)
    }
    option.None -> panic as "Expected concurrency config"
  }
}

pub fn durable_task_test() {
  let handler = fn(_ctx) { Ok(dynamic.string("result")) }
  let task_def =
    TaskDef(
      name: "test",
      handler: handler,
      parents: [],
      retries: 0,
      retry_backoff: option.None,
      execution_timeout_ms: option.None,
      schedule_timeout_ms: option.None,
      rate_limits: [],
      concurrency: option.None,
      skip_if: option.None,
      wait_for: option.None,
      is_durable: False,
      checkpoint_key: option.None,
    )

  let durable = task.durable(task_def, "checkpoint-key")

  durable.checkpoint_key
  |> should.equal("checkpoint-key")

  durable.task.name
  |> should.equal("test")
}
