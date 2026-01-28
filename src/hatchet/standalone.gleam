import gleam/dynamic.{type Dynamic}
import gleam/list
import gleam/option
import hatchet/types.{
  type StandaloneTask, type TaskContext, type Workflow, StandaloneTask,
}
import hatchet/workflow

/// Create a new standalone task with minimal configuration.
///
/// Standalone tasks are single-task workflows that can be used without
/// creating a full workflow object. They can be converted to workflows
/// with `to_workflow()` when needed.
///
/// **Parameters:**
///   - `name`: Task name
///   - `handler`: Function to execute for this task
///
/// **Returns:** A `StandaloneTask` with default configuration
///
/// **Examples:**
/// ```gleam
/// let task = standalone.new_standalone("my-task", fn(ctx) {
///   task.succeed(dynamic.from("done"))
/// })
/// ```
pub fn new_standalone(
  name: String,
  handler: fn(TaskContext) -> Result(Dynamic, String),
) -> StandaloneTask {
  StandaloneTask(
    name: name,
    handler: handler,
    retries: 0,
    cron: option.None,
    events: [],
  )
}

/// Set the number of retry attempts for a standalone task.
///
/// **Parameters:**
///   - `task`: The standalone task to configure
///   - `retries`: Number of times to retry on failure
///
/// **Returns:** The updated standalone task
///
/// **Examples:**
/// ```gleam
/// let task = standalone.new_standalone("retry-task", handler)
///   |> standalone.with_task_retries(3)
/// ```
pub fn with_task_retries(task: StandaloneTask, retries: Int) -> StandaloneTask {
  StandaloneTask(..task, retries: retries)
}

/// Set a cron schedule for a standalone task.
///
/// **Parameters:**
///   - `task`: The standalone task to configure
///   - `cron`: Cron expression for scheduling
///
/// **Returns:** The updated standalone task
///
/// **Examples:**
/// ```gleam
/// // Run every hour
/// let task = standalone.new_standalone("hourly-task", handler)
///   |> standalone.with_task_cron("0 * * * *")
/// ```
pub fn with_task_cron(task: StandaloneTask, cron: String) -> StandaloneTask {
  StandaloneTask(..task, cron: option.Some(cron))
}

/// Add event triggers to a standalone task.
///
/// The task will be triggered when any of the specified events are published.
///
/// **Parameters:**
///   - `task`: The standalone task to configure
///   - `events`: List of event keys that trigger this task
///
/// **Returns:** The updated standalone task with events appended
///
/// **Examples:**
/// ```gleam
/// let task = standalone.new_standalone("event-task", handler)
///   |> standalone.with_task_events(["user.created", "order.placed"])
/// ```
pub fn with_task_events(
  task: StandaloneTask,
  events: List(String),
) -> StandaloneTask {
  StandaloneTask(..task, events: list.append(task.events, events))
}

/// Convert a standalone task to a full workflow.
///
/// This creates a workflow with a single task and applies any
/// configured cron schedule or event triggers.
///
/// **Parameters:**
///   - `task`: The standalone task to convert
///
/// **Returns:** A `Workflow` ready for registration
///
/// **Examples:**
/// ```gleam
/// let task = standalone.new_standalone("simple-task", handler)
/// let wf = standalone.to_workflow(task)
///
/// let scheduled = standalone.new_standalone("scheduled-task", handler)
///   |> standalone.with_task_cron("0 * * * *")
/// let wf_with_schedule = standalone.to_workflow(scheduled)
/// ```
pub fn to_workflow(task: StandaloneTask) -> Workflow {
  let wf = workflow.new(task.name)
  let wf_with_task = workflow.task(wf, task.name, task.handler)

  let wf_with_cron = case task.cron {
    option.Some(cron) -> workflow.with_cron(wf_with_task, cron)
    option.None -> wf_with_task
  }

  case list.is_empty(task.events) {
    True -> wf_with_cron
    False -> workflow.with_events(wf_with_cron, task.events)
  }
}
