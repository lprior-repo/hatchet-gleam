import gleam/dynamic.{type Dynamic}
import gleam/list
import gleam/option
import hatchet/types.{
  type StandaloneTask, type TaskContext, type TaskDef, type Workflow,
  StandaloneTask,
}
import hatchet/workflow

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

pub fn with_task_retries(task: StandaloneTask, retries: Int) -> StandaloneTask {
  StandaloneTask(..task, retries: retries)
}

pub fn with_task_cron(task: StandaloneTask, cron: String) -> StandaloneTask {
  StandaloneTask(..task, cron: option.Some(cron))
}

pub fn with_task_events(
  task: StandaloneTask,
  events: List(String),
) -> StandaloneTask {
  StandaloneTask(..task, events: list.append(task.events, events))
}

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
