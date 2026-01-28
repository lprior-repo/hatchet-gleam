import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/list
import gleam/option
import hatchet/types.{
  type BackoffConfig, type DurableContext, type DurableTaskDef,
  type FailureContext, type LimitStrategy, type TaskContext, type TaskDef,
  type WaitCondition, type Workflow, ConcurrencyConfig, DurableContext,
  DurableEventConditions, DurableTaskDef, RateLimitConfig, TaskDef, Workflow,
}

/// Create a new workflow with the given name.
///
/// This creates an empty workflow configuration that can be extended
/// with tasks, schedules, and other configuration options.
///
/// **Parameters:**
///   - `name`: A unique identifier for the workflow
///
/// **Returns:** A new `Workflow` with minimal configuration
///
/// **Examples:**
/// ```gleam
/// let wf = workflow.new("my-workflow")
/// ```
pub fn new(name: String) -> Workflow {
  Workflow(
    name: name,
    description: option.None,
    version: option.None,
    tasks: [],
    on_failure: option.None,
    cron: option.None,
    events: [],
    concurrency: option.None,
  )
}

/// Set a human-readable description for the workflow.
///
/// This description is used in the Hatchet dashboard and API responses.
///
/// **Parameters:**
///   - `wf`: The workflow to configure
///   - `desc`: The workflow description
///
/// **Returns:** The updated workflow
///
/// **Examples:**
/// ```gleam
/// workflow.new("my-workflow")
///   |> workflow.with_description("Processes user data")
/// ```
pub fn with_description(wf: Workflow, desc: String) -> Workflow {
  Workflow(..wf, description: option.Some(desc))
}

/// Set a version string for the workflow.
///
/// Versioning helps track changes to workflow definitions over time.
///
/// **Parameters:**
///   - `wf`: The workflow to configure
///   - `version`: The version string (e.g., "1.0.0")
///
/// **Returns:** The updated workflow
///
/// **Examples:**
/// ```gleam
/// workflow.new("my-workflow")
///   |> workflow.with_version("1.0.0")
/// ```
pub fn with_version(wf: Workflow, version: String) -> Workflow {
  Workflow(..wf, version: option.Some(version))
}

/// Set a cron schedule for the workflow.
///
/// The workflow will be triggered automatically according to the cron schedule.
///
/// **Parameters:**
///   - `wf`: The workflow to configure
///   - `cron`: A cron expression (e.g., "0 * * * *" for hourly)
///
/// **Returns:** The updated workflow
///
/// **Examples:**
/// ```gleam
/// // Run every hour
/// workflow.new("hourly-task")
///   |> workflow.with_cron("0 * * * *")
///
/// // Run every Monday at 9 AM
/// workflow.new("weekly-report")
///   |> workflow.with_cron("0 9 * * 1")
/// ```
pub fn with_cron(wf: Workflow, cron: String) -> Workflow {
  Workflow(..wf, cron: option.Some(cron))
}

/// Add event triggers for the workflow.
///
/// The workflow will be triggered when any of the specified events are published.
/// Events are deduplicated - adding the same event multiple times has no effect.
///
/// **Parameters:**
///   - `wf`: The workflow to configure
///   - `events`: List of event keys that trigger this workflow
///
/// **Returns:** The updated workflow with new events appended
///
/// **Examples:**
/// ```gleam
/// workflow.new("user-handler")
///   |> workflow.with_events(["user.created", "user.updated"])
///
/// // Events can be added multiple times
/// workflow.new("multi-trigger")
///   |> workflow.with_events(["event.a"])
///   |> workflow.with_events(["event.b", "event.c"])
/// ```
pub fn with_events(wf: Workflow, events: List(String)) -> Workflow {
  let existing_set =
    list.fold(wf.events, dict.new(), fn(acc, event) {
      dict.insert(acc, event, True)
    })
  let new_unique_events =
    list.filter(events, fn(event) {
      case dict.get(existing_set, event) {
        Ok(_) -> False
        Error(_) -> True
      }
    })
  Workflow(..wf, events: list.append(wf.events, new_unique_events))
}

/// Configure workflow-level concurrency limits.
///
/// Limits the number of concurrent workflow runs across all workers.
///
/// **Parameters:**
///   - `wf`: The workflow to configure
///   - `max`: Maximum number of concurrent runs
///   - `strategy`: How to handle exceeding the limit
///
/// **Returns:** The updated workflow
///
/// **Examples:**
/// ```gleam
/// import hatchet/types.{GroupConcurrency, CancelInFlight}
///
/// workflow.new("concurrent-workflow")
///   |> workflow.with_concurrency(10, GroupConcurrency)
///
/// // Cancel in-flight runs if limit exceeded
/// workflow.new("exclusive-workflow")
///   |> workflow.with_concurrency(1, CancelInFlight)
/// ```
pub fn with_concurrency(
  wf: Workflow,
  max: Int,
  strategy: LimitStrategy,
) -> Workflow {
  let config = ConcurrencyConfig(max_concurrent: max, limit_strategy: strategy)
  Workflow(..wf, concurrency: option.Some(config))
}

/// Add a task to the workflow that runs at the start.
///
/// The task will execute immediately when the workflow starts.
///
/// **Parameters:**
///   - `wf`: The workflow to add the task to
///   - `name`: A unique name for the task within this workflow
///   - `handler`: Function that processes the task
///
/// **Returns:** The updated workflow with the task added
///
/// **Examples:**
/// ```gleam
/// let wf = workflow.new("simple-workflow")
///   |> workflow.task("process", fn(ctx) {
///     let input = task.get_input(ctx)
///     task.succeed(dynamic.string("done"))
///   })
/// ```
pub fn task(
  wf: Workflow,
  name: String,
  handler: fn(TaskContext) -> Result(Dynamic, String),
) -> Workflow {
  let task_def =
    TaskDef(
      name: name,
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
    )
  Workflow(..wf, tasks: list.append(wf.tasks, [task_def]))
}

/// Add a task that runs after the specified parent tasks complete.
///
/// The task will execute only after all parent tasks have completed successfully.
///
/// **Parameters:**
///   - `wf`: The workflow to add the task to
///   - `name`: A unique name for the task within this workflow
///   - `parents`: List of task names that must complete first
///   - `handler`: Function that processes the task
///
/// **Returns:** The updated workflow with the task added
///
/// **Examples:**
/// ```gleam
/// let wf = workflow.new("pipeline")
///   |> workflow.task("fetch", fn(ctx) {
///     task.succeed(dynamic.string("data"))
///   })
///   |> workflow.task_after("process", ["fetch"], fn(ctx) {
///     let data = task.get_parent_output(ctx, "fetch")
///     task.succeed(dynamic.string("processed"))
///   })
///   |> workflow.task_after("save", ["process"], fn(ctx) {
///     task.succeed(dynamic.string("saved"))
///   })
/// ```
pub fn task_after(
  wf: Workflow,
  name: String,
  parents: List(String),
  handler: fn(TaskContext) -> Result(Dynamic, String),
) -> Workflow {
  let task_def =
    TaskDef(
      name: name,
      handler: handler,
      parents: parents,
      retries: 0,
      retry_backoff: option.None,
      execution_timeout_ms: option.None,
      schedule_timeout_ms: option.None,
      rate_limits: [],
      concurrency: option.None,
      skip_if: option.None,
      wait_for: option.None,
    )
  Workflow(..wf, tasks: list.append(wf.tasks, [task_def]))
}

/// Add a durable task to the workflow.
///
/// Durable tasks can survive process restarts through checkpointing.
///
/// **Parameters:**
///   - `wf`: The workflow to add the task to
///   - `name`: Task name
///   - `handler`: Function taking DurableContext and returning Result
///   - `checkpoint_key`: Unique key for checkpointing state
///
/// **Returns:** Updated workflow with the durable task
///
/// **Example:**
/// ```gleam
/// workflow.new("my-workflow")
///   |> workflow.durable_task("durable-step", fn(ctx) {
///     durable.sleep_for(ctx, 5000)
///     Ok(dynamic.string("done"))
///   }, "my-checkpoint")
/// ```
pub fn durable_task(
  wf: Workflow,
  name: String,
  handler: fn(DurableContext) -> Result(Dynamic, String),
  checkpoint_key: String,
) -> Workflow {
  // Create a wrapper handler that converts TaskContext to DurableContext
  let wrapped_handler = fn(task_ctx: TaskContext) -> Result(Dynamic, String) {
    // For now, create a basic durable context
    // In a full implementation, this would come from the worker with proper callbacks
    let durable_ctx =
      DurableContext(
        task_context: task_ctx,
        checkpoint_key: checkpoint_key,
        wait_key_counter: 0,
        register_durable_event_fn: fn(_, _, _) {
          Error("Durable events not available in current context")
        },
        await_durable_event_fn: fn(_, _) {
          Error("Durable events not available in current context")
        },
      )
    handler(durable_ctx)
  }

  let task_def =
    TaskDef(
      name: name,
      handler: wrapped_handler,
      parents: [],
      retries: 0,
      retry_backoff: option.None,
      execution_timeout_ms: option.None,
      schedule_timeout_ms: option.None,
      rate_limits: [],
      concurrency: option.None,
      skip_if: option.None,
      wait_for: option.None,
    )
  Workflow(..wf, tasks: list.append(wf.tasks, [task_def]))
}

/// Helper function to modify the last task in a workflow.
/// This is used internally by with_retries, with_timeout, with_retry_backoff, etc.
fn modify_last_task(wf: Workflow, modifier: fn(TaskDef) -> TaskDef) -> Workflow {
  case wf.tasks {
    [] -> wf
    tasks -> {
      let reversed = list.reverse(tasks)
      case reversed {
        [last_task, ..rest] -> {
          let updated_task = modifier(last_task)
          let updated_rest = list.reverse(rest)
          Workflow(..wf, tasks: list.append(updated_rest, [updated_task]))
        }
        _ -> wf
      }
    }
  }
}

/// Set the number of retry attempts for the most recently added task.
///
/// **Parameters:**
///   - `wf`: The workflow to configure
///   - `retries`: Number of times to retry on failure
///
/// **Returns:** The updated workflow
///
/// **Examples:**
/// ```gleam
/// workflow.new("retry-workflow")
///   |> workflow.task("flaky-task", fn(ctx) {
///     task.succeed(dynamic.string("done"))
///   })
///   |> workflow.with_retries(3) // Retry 3 times
/// ```
pub fn with_retries(wf: Workflow, retries: Int) -> Workflow {
  modify_last_task(wf, fn(task) { TaskDef(..task, retries: retries) })
}

/// Set the execution timeout for the most recently added task.
///
/// The task will be cancelled if it exceeds this timeout.
///
/// **Parameters:**
///   - `wf`: The workflow to configure
///   - `timeout_ms`: Timeout in milliseconds
///
/// **Returns:** The updated workflow
///
/// **Examples:**
/// ```gleam
/// workflow.new("timed-workflow")
///   |> workflow.task("slow-task", fn(ctx) {
///     task.succeed(dynamic.string("done"))
///   })
///   |> workflow.with_timeout(30_000) // 30 second timeout
/// ```
pub fn with_timeout(wf: Workflow, timeout_ms: Int) -> Workflow {
  modify_last_task(wf, fn(task) {
    TaskDef(..task, execution_timeout_ms: option.Some(timeout_ms))
  })
}

/// Set a failure handler for the workflow.
///
/// The handler will be called if any task in the workflow fails.
///
/// **Parameters:**
///   - `wf`: The workflow to configure
///   - `handler`: Function to handle workflow failures
///
/// **Returns:** The updated workflow
///
/// **Examples:**
/// ```gleam
/// workflow.new("handled-workflow")
///   |> workflow.on_failure(fn(ctx) {
///     // Log or notify about the failure
///     Ok(Nil)
///   })
/// ```
pub fn on_failure(
  wf: Workflow,
  handler: fn(FailureContext) -> Result(Nil, String),
) {
  Workflow(..wf, on_failure: option.Some(handler))
}

/// Set the retry backoff strategy for the most recently added task.
///
/// **Parameters:**
///   - `wf`: The workflow to configure
///   - `backoff`: The backoff strategy (constant, linear, or exponential)
///
/// **Returns:** The updated workflow
///
/// **Examples:**
/// ```gleam
/// import hatchet/task
///
/// workflow.new("backoff-workflow")
///   |> workflow.task("task", fn(ctx) {
///     task.succeed(dynamic.string("done"))
///   })
///   |> workflow.with_retry_backoff(task.exponential_backoff(1000, 60_000))
/// ```
pub fn with_retry_backoff(wf: Workflow, backoff: BackoffConfig) -> Workflow {
  modify_last_task(wf, fn(task) {
    TaskDef(..task, retry_backoff: option.Some(backoff))
  })
}

/// Set the schedule timeout for the most recently added task.
///
/// This is different from execution timeout - it limits how long the task
/// can wait in the queue before being scheduled.
///
/// **Parameters:**
///   - `wf`: The workflow to configure
///   - `timeout_ms`: Schedule timeout in milliseconds
///
/// **Returns:** The updated workflow
///
/// **Examples:**
/// ```gleam
/// workflow.new("scheduled-workflow")
///   |> workflow.task("task", fn(ctx) {
///     task.succeed(dynamic.string("done"))
///   })
///   |> workflow.with_schedule_timeout(5_000) // 5 second schedule timeout
/// ```
pub fn with_schedule_timeout(wf: Workflow, timeout_ms: Int) -> Workflow {
  modify_last_task(wf, fn(task) {
    TaskDef(..task, schedule_timeout_ms: option.Some(timeout_ms))
  })
}

/// Add a rate limit to the most recently added task.
///
/// Limits how often the task can execute.
///
/// **Parameters:**
///   - `wf`: The workflow to configure
///   - `key`: A unique key for the rate limit
///   - `units`: Number of allowed executions
///   - `duration_ms`: Time window in milliseconds
///
/// **Returns:** The updated workflow
///
/// **Examples:**
/// ```gleam
/// workflow.new("rate-limited")
///   |> workflow.task("api-call", fn(ctx) {
///     task.succeed(dynamic.string("done"))
///   })
///   |> workflow.with_rate_limit("api", 10, 60_000) // 10 requests per minute
/// ```
pub fn with_rate_limit(
  wf: Workflow,
  key: String,
  units: Int,
  duration_ms: Int,
) -> Workflow {
  modify_last_task(wf, fn(task) {
    let limit =
      RateLimitConfig(key: key, units: units, duration_ms: duration_ms)
    TaskDef(..task, rate_limits: [limit, ..task.rate_limits])
  })
}

/// Set task-level concurrency limits for the most recently added task.
///
/// Limits the number of concurrent executions of this specific task.
///
/// **Parameters:**
///   - `wf`: The workflow to configure
///   - `max`: Maximum number of concurrent executions
///   - `strategy`: How to handle exceeding the limit
///
/// **Returns:** The updated workflow
///
/// **Examples:**
/// ```gleam
/// import hatchet/types.{CancelInFlight}
///
/// workflow.new("concurrent-task")
///   |> workflow.task("exclusive", fn(ctx) {
///     task.succeed(dynamic.string("done"))
///   })
///   |> workflow.with_task_concurrency(1, CancelInFlight)
/// ```
pub fn with_task_concurrency(
  wf: Workflow,
  max: Int,
  strategy: LimitStrategy,
) -> Workflow {
  modify_last_task(wf, fn(task) {
    let config =
      ConcurrencyConfig(max_concurrent: max, limit_strategy: strategy)
    TaskDef(..task, concurrency: option.Some(config))
  })
}

/// Set a condition to skip the most recently added task.
///
/// The task will be skipped if the predicate returns True.
///
/// **Parameters:**
///   - `wf`: The workflow to configure
///   - `predicate`: Function that determines whether to skip the task
///
/// **Returns:** The updated workflow
///
/// **Examples:**
/// ```gleam
/// workflow.new("conditional-workflow")
///   |> workflow.task("skip-me", fn(ctx) {
///     task.succeed(dynamic.string("done"))
///   })
///   |> workflow.with_skip_if(fn(ctx) {
///     let should_skip = task.get_metadata(ctx, "skip")
///       |> option.unwrap("false")
///       |> bool.parse
///     should_skip
///   })
/// ```
pub fn with_skip_if(
  wf: Workflow,
  predicate: fn(TaskContext) -> Bool,
) -> Workflow {
  modify_last_task(wf, fn(task) {
    TaskDef(..task, skip_if: option.Some(predicate))
  })
}

/// Set a wait condition for the most recently added task.
///
/// The task will wait for the condition to be met before executing.
///
/// **Parameters:**
///   - `wf`: The workflow to configure
///   - `condition`: The condition to wait for (event, time, or expression)
///
/// **Returns:** The updated workflow
///
/// **Examples:**
/// ```gleam
/// import hatchet/task
///
/// workflow.new("waiting-workflow")
///   |> workflow.task("wait-event", fn(ctx) {
///     task.succeed(dynamic.string("done"))
///   })
///   |> workflow.with_wait_for(task.wait_for_event("trigger", 60_000))
/// ```
pub fn with_wait_for(wf: Workflow, condition: WaitCondition) -> Workflow {
  modify_last_task(wf, fn(task) {
    TaskDef(..task, wait_for: option.Some(condition))
  })
}
