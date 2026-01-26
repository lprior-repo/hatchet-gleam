import gleam/dynamic.{type Dynamic}
import gleam/list
import gleam/option
import hatchet/types.{
  type BackoffConfig, type FailureContext, type LimitStrategy, type TaskContext,
  type TaskDef, type WaitCondition, type Workflow, ConcurrencyConfig,
  RateLimitConfig, TaskDef, Workflow,
}

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

pub fn with_description(wf: Workflow, desc: String) -> Workflow {
  Workflow(..wf, description: option.Some(desc))
}

pub fn with_version(wf: Workflow, version: String) -> Workflow {
  Workflow(..wf, version: option.Some(version))
}

pub fn with_cron(wf: Workflow, cron: String) -> Workflow {
  Workflow(..wf, cron: option.Some(cron))
}

pub fn with_events(wf: Workflow, events: List(String)) -> Workflow {
  Workflow(..wf, events: list.append(wf.events, events))
}

pub fn with_concurrency(
  wf: Workflow,
  max: Int,
  strategy: LimitStrategy,
) -> Workflow {
  let config = ConcurrencyConfig(max_concurrent: max, limit_strategy: strategy)
  Workflow(..wf, concurrency: option.Some(config))
}

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

pub fn with_retries(wf: Workflow, retries: Int) -> Workflow {
  case wf.tasks {
    [] -> wf
    tasks -> {
      let reversed = list.reverse(tasks)
      case reversed {
        [last_task, ..rest] -> {
          let updated_task = TaskDef(..last_task, retries: retries)
          let updated_rest = list.reverse(rest)
          Workflow(..wf, tasks: list.append(updated_rest, [updated_task]))
        }
        _ -> wf
      }
    }
  }
}

pub fn with_timeout(wf: Workflow, timeout_ms: Int) -> Workflow {
  case wf.tasks {
    [] -> wf
    tasks -> {
      let reversed = list.reverse(tasks)
      case reversed {
        [last_task, ..rest] -> {
          let updated_task =
            TaskDef(..last_task, execution_timeout_ms: option.Some(timeout_ms))
          let updated_rest = list.reverse(rest)
          Workflow(..wf, tasks: list.append(updated_rest, [updated_task]))
        }
        _ -> wf
      }
    }
  }
}

pub fn on_failure(
  wf: Workflow,
  handler: fn(FailureContext) -> Result(Nil, String),
) {
  Workflow(..wf, on_failure: option.Some(handler))
}

pub fn with_retry_backoff(wf: Workflow, backoff: BackoffConfig) -> Workflow {
  case wf.tasks {
    [] -> wf
    tasks -> {
      let reversed = list.reverse(tasks)
      case reversed {
        [last_task, ..rest] -> {
          let updated_task =
            TaskDef(..last_task, retry_backoff: option.Some(backoff))
          let updated_rest = list.reverse(rest)
          Workflow(..wf, tasks: list.append(updated_rest, [updated_task]))
        }
        _ -> wf
      }
    }
  }
}

pub fn with_schedule_timeout(wf: Workflow, timeout_ms: Int) -> Workflow {
  case wf.tasks {
    [] -> wf
    tasks -> {
      let reversed = list.reverse(tasks)
      case reversed {
        [last_task, ..rest] -> {
          let updated_task =
            TaskDef(..last_task, schedule_timeout_ms: option.Some(timeout_ms))
          let updated_rest = list.reverse(rest)
          Workflow(..wf, tasks: list.append(updated_rest, [updated_task]))
        }
        _ -> wf
      }
    }
  }
}

pub fn with_rate_limit(
  wf: Workflow,
  key: String,
  units: Int,
  duration_ms: Int,
) -> Workflow {
  case wf.tasks {
    [] -> wf
    tasks -> {
      let reversed = list.reverse(tasks)
      case reversed {
        [last_task, ..rest] -> {
          let limit =
            RateLimitConfig(key: key, units: units, duration_ms: duration_ms)
          let updated_task =
            TaskDef(..last_task, rate_limits: [limit, ..last_task.rate_limits])
          let updated_rest = list.reverse(rest)
          Workflow(..wf, tasks: list.append(updated_rest, [updated_task]))
        }
        _ -> wf
      }
    }
  }
}

pub fn with_task_concurrency(
  wf: Workflow,
  max: Int,
  strategy: LimitStrategy,
) -> Workflow {
  case wf.tasks {
    [] -> wf
    tasks -> {
      let reversed = list.reverse(tasks)
      case reversed {
        [last_task, ..rest] -> {
          let config =
            ConcurrencyConfig(max_concurrent: max, limit_strategy: strategy)
          let updated_task =
            TaskDef(..last_task, concurrency: option.Some(config))
          let updated_rest = list.reverse(rest)
          Workflow(..wf, tasks: list.append(updated_rest, [updated_task]))
        }
        _ -> wf
      }
    }
  }
}

pub fn with_skip_if(
  wf: Workflow,
  predicate: fn(TaskContext) -> Bool,
) -> Workflow {
  case wf.tasks {
    [] -> wf
    tasks -> {
      let reversed = list.reverse(tasks)
      case reversed {
        [last_task, ..rest] -> {
          let updated_task =
            TaskDef(..last_task, skip_if: option.Some(predicate))
          let updated_rest = list.reverse(rest)
          Workflow(..wf, tasks: list.append(updated_rest, [updated_task]))
        }
        _ -> wf
      }
    }
  }
}

pub fn with_wait_for(wf: Workflow, condition: WaitCondition) -> Workflow {
  case wf.tasks {
    [] -> wf
    tasks -> {
      let reversed = list.reverse(tasks)
      case reversed {
        [last_task, ..rest] -> {
          let updated_task =
            TaskDef(..last_task, wait_for: option.Some(condition))
          let updated_rest = list.reverse(rest)
          Workflow(..wf, tasks: list.append(updated_rest, [updated_task]))
        }
        _ -> wf
      }
    }
  }
}
