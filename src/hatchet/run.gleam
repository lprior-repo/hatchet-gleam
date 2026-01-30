import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/list
import gleam/option
import hatchet/errors
import hatchet/internal/ffi/timer
import hatchet/internal/http as h
import hatchet/internal/http_client.{type HttpClient, real_http_client, send}
import hatchet/internal/json as j
import hatchet/internal/protocol as p
import hatchet/types.{
  type Client, type RunOptions, type RunStatus, type Workflow,
  type WorkflowRunRef, Cancelled, Failed, Pending, RunOptions, Running,
  Succeeded,
}

pub fn run(
  client: Client,
  workflow: Workflow,
  input: Dynamic,
) -> Result(Dynamic, String) {
  let options = default_run_options()
  run_with_options(client, workflow, input, options)
}

pub fn run_with_options(
  client: Client,
  workflow: Workflow,
  input: Dynamic,
  options: RunOptions,
) -> Result(Dynamic, String) {
  run_with_options_and_http(
    client,
    workflow,
    input,
    options,
    real_http_client(),
  )
}

pub fn run_with_options_and_http(
  client: Client,
  workflow: Workflow,
  input: Dynamic,
  options: RunOptions,
  http: HttpClient,
) -> Result(Dynamic, String) {
  let run_req =
    p.WorkflowRunRequest(
      workflow_name: workflow.name,
      input: input,
      metadata: options.metadata,
      priority: options.priority,
      sticky: options.sticky,
      run_key: options.run_key,
    )

  let req_body = j.encode_workflow_run(run_req)
  let base_url = h.build_base_url(client)
  let url = base_url <> "/api/v1/workflows/" <> workflow.name <> "/run"

  case h.make_authenticated_request(client, url, option.Some(req_body)) {
    Ok(req) -> {
      case send(http, req) {
        Ok(resp) if resp.status == 200 -> {
          case j.decode_workflow_run_response(resp.body) {
            Ok(run_resp) -> {
              let run_ref =
                types.create_workflow_run_ref(run_resp.run_id, client)
              await_result_with_http(run_ref, http)
            }
            Error(e) -> {
              Error(
                errors.to_simple_string(errors.decode_error(
                  "workflow run response",
                  e,
                )),
              )
            }
          }
        }
        Ok(resp) -> {
          Error(
            errors.to_simple_string(errors.api_http_error(
              resp.status,
              resp.body,
            )),
          )
        }
        Error(_) -> Error(errors.to_simple_string(errors.network_error("")))
      }
    }
    Error(e) -> Error(e)
  }
}

pub fn run_no_wait(
  client: Client,
  workflow: Workflow,
  input: Dynamic,
) -> Result(WorkflowRunRef, String) {
  let options = default_run_options()
  run_no_wait_with_options(client, workflow, input, options)
}

pub fn run_no_wait_with_options(
  client: Client,
  workflow: Workflow,
  input: Dynamic,
  options: RunOptions,
) -> Result(WorkflowRunRef, String) {
  run_no_wait_with_options_and_http(
    client,
    workflow,
    input,
    options,
    real_http_client(),
  )
}

pub fn run_no_wait_with_options_and_http(
  client: Client,
  workflow: Workflow,
  input: Dynamic,
  options: RunOptions,
  http: HttpClient,
) -> Result(WorkflowRunRef, String) {
  let run_req =
    p.WorkflowRunRequest(
      workflow_name: workflow.name,
      input: input,
      metadata: options.metadata,
      priority: options.priority,
      sticky: options.sticky,
      run_key: options.run_key,
    )

  let req_body = j.encode_workflow_run(run_req)
  let base_url = h.build_base_url(client)
  let url = base_url <> "/api/v1/workflows/" <> workflow.name <> "/run"

  case h.make_authenticated_request(client, url, option.Some(req_body)) {
    Ok(req) -> {
      case send(http, req) {
        Ok(resp) if resp.status == 200 -> {
          case j.decode_workflow_run_response(resp.body) {
            Ok(run_resp) -> {
              Ok(types.create_workflow_run_ref(run_resp.run_id, client))
            }
            Error(e) -> {
              Error(
                errors.to_simple_string(errors.decode_error(
                  "workflow run response",
                  e,
                )),
              )
            }
          }
        }
        Ok(resp) -> {
          Error(
            errors.to_simple_string(errors.api_http_error(
              resp.status,
              resp.body,
            )),
          )
        }
        Error(_) -> Error(errors.to_simple_string(errors.network_error("")))
      }
    }
    Error(e) -> Error(e)
  }
}

pub fn run_many(
  client: Client,
  workflow: Workflow,
  inputs: List(Dynamic),
) -> Result(List(WorkflowRunRef), String) {
  let options = default_run_options()
  let results =
    list.map(inputs, fn(input) {
      run_no_wait_with_options(client, workflow, input, options)
    })
  let errors =
    list.filter(results, fn(r) {
      case r {
        Error(_) -> True
        Ok(_) -> False
      }
    })
  case errors {
    [] -> Ok(list.filter_map(results, fn(r) { r }))
    _ -> Error("Some workflow runs failed")
  }
}

pub fn await_result(ref: WorkflowRunRef) -> Result(Dynamic, String) {
  await_result_with_http(ref, real_http_client())
}

fn await_result_with_http(
  ref: WorkflowRunRef,
  http: HttpClient,
) -> Result(Dynamic, String) {
  poll_result(ref, 10, http)
}

fn poll_result(
  ref: WorkflowRunRef,
  attempts: Int,
  http: HttpClient,
) -> Result(Dynamic, String) {
  case get_status_with_http(ref, http) {
    Ok(Succeeded) -> {
      let url =
        h.build_base_url(types.get_ref_client(ref))
        <> "/api/v1/runs/"
        <> types.get_run_id(ref)
      case
        h.make_authenticated_request(
          types.get_ref_client(ref),
          url,
          option.None,
        )
      {
        Ok(req) -> {
          case send(http, req) {
            Ok(resp) if resp.status == 200 -> {
              case j.decode_workflow_status_response(resp.body) {
                Ok(status_resp) -> {
                  case status_resp.output {
                    option.Some(output) -> Ok(output)
                    option.None -> Error("No output available")
                  }
                }
                Error(e) -> {
                  Error(
                    errors.to_simple_string(errors.decode_error(
                      "workflow status response",
                      e,
                    )),
                  )
                }
              }
            }
            Ok(resp) ->
              Error(
                errors.to_simple_string(errors.api_http_error(resp.status, "")),
              )
            Error(_) -> Error(errors.to_simple_string(errors.network_error("")))
          }
        }
        Error(e) -> Error(e)
      }
    }
    Ok(Failed(err)) -> Error("Workflow failed: " <> err)
    Ok(Cancelled) -> Error("Workflow was cancelled")
    Ok(Pending) if attempts > 0 -> {
      sleep_ms(500)
      poll_result(ref, attempts - 1, http)
    }
    Ok(Running) if attempts > 0 -> {
      sleep_ms(500)
      poll_result(ref, attempts - 1, http)
    }
    _ -> Error("Workflow timed out")
  }
}

pub fn get_status(ref: WorkflowRunRef) -> Result(RunStatus, String) {
  get_status_with_http(ref, real_http_client())
}

pub fn get_status_with_http(
  ref: WorkflowRunRef,
  http: HttpClient,
) -> Result(RunStatus, String) {
  let url =
    h.build_base_url(types.get_ref_client(ref))
    <> "/api/v1/runs/"
    <> types.get_run_id(ref)
    <> "/status"
  case
    h.make_authenticated_request(types.get_ref_client(ref), url, option.None)
  {
    Ok(req) -> {
      case send(http, req) {
        Ok(resp) if resp.status == 200 -> {
          case j.decode_workflow_status_response(resp.body) {
            Ok(status_resp) -> Ok(parse_status(status_resp))
            Error(e) -> {
              Error(
                errors.to_simple_string(errors.decode_error(
                  "workflow status response",
                  e,
                )),
              )
            }
          }
        }
        Ok(resp) ->
          Error(errors.to_simple_string(errors.api_http_error(resp.status, "")))
        Error(_) -> Error(errors.to_simple_string(errors.network_error("")))
      }
    }
    Error(e) -> Error(e)
  }
}

pub fn cancel(ref: WorkflowRunRef) -> Result(Nil, String) {
  cancel_with_http(ref, http_client.real_http_client())
}

pub fn cancel_with_http(
  ref: WorkflowRunRef,
  http: HttpClient,
) -> Result(Nil, String) {
  let url =
    h.build_base_url(types.get_ref_client(ref))
    <> "/api/v1/runs/"
    <> types.get_run_id(ref)
    <> "/cancel"
  case
    h.make_authenticated_request(types.get_ref_client(ref), url, option.None)
  {
    Ok(req) -> {
      case send(http, req) {
        Ok(resp) if resp.status == 200 -> Ok(Nil)
        Ok(resp) ->
          Error(
            errors.to_simple_string(errors.api_http_error(
              resp.status,
              resp.body,
            )),
          )
        Error(_) -> Error(errors.to_simple_string(errors.network_error("")))
      }
    }
    Error(e) -> Error(e)
  }
}

fn default_run_options() -> RunOptions {
  RunOptions(
    metadata: dict.new(),
    priority: option.None,
    sticky: False,
    run_key: option.None,
  )
}

fn parse_status(resp: p.WorkflowStatusResponse) -> RunStatus {
  case resp.status {
    "pending" -> Pending
    "running" -> Running
    "succeeded" -> Succeeded
    "failed" -> {
      case resp.error {
        option.Some(err) -> Failed(err)
        option.None -> Failed("Unknown error")
      }
    }
    "cancelled" -> Cancelled
    _ -> Failed("Unknown status")
  }
}

fn sleep_ms(ms: Int) -> Nil {
  timer.sleep_ms(ms)
}

// ============================================================================
// Bulk Operations
// ============================================================================

/// Cancel multiple workflow runs at once.
pub fn bulk_cancel(client: Client, run_ids: List(String)) -> Result(Nil, String) {
  bulk_cancel_with_http(client, run_ids, http_client.real_http_client())
}

pub fn bulk_cancel_with_http(
  client: Client,
  run_ids: List(String),
  http: HttpClient,
) -> Result(Nil, String) {
  let body = j.encode_bulk_cancel(run_ids)
  let url = h.build_base_url(client) <> "/api/v1/runs/bulk/cancel"

  case h.make_authenticated_request(client, url, option.Some(body)) {
    Ok(req) -> {
      case send(http, req) {
        Ok(resp) if resp.status == 200 -> Ok(Nil)
        Ok(resp) ->
          Error(
            errors.to_simple_string(errors.api_http_error(
              resp.status,
              resp.body,
            )),
          )
        Error(_) -> Error(errors.to_simple_string(errors.network_error("")))
      }
    }
    Error(e) -> Error(e)
  }
}

/// Replay (re-run) failed workflow runs.
pub fn replay(client: Client, run_ids: List(String)) -> Result(Nil, String) {
  replay_with_http(client, run_ids, http_client.real_http_client())
}

pub fn replay_with_http(
  client: Client,
  run_ids: List(String),
  http: HttpClient,
) -> Result(Nil, String) {
  let body = j.encode_bulk_replay(run_ids)
  let url = h.build_base_url(client) <> "/api/v1/runs/bulk/replay"

  case h.make_authenticated_request(client, url, option.Some(body)) {
    Ok(req) -> {
      case send(http, req) {
        Ok(resp) if resp.status == 200 -> Ok(Nil)
        Ok(resp) ->
          Error(
            errors.to_simple_string(errors.api_http_error(
              resp.status,
              resp.body,
            )),
          )
        Error(_) -> Error(errors.to_simple_string(errors.network_error("")))
      }
    }
    Error(e) -> Error(e)
  }
}

/// Convert Workflow type to protocol WorkflowCreateRequest for API calls
fn convert_workflow_to_protocol(wf: types.Workflow) -> p.WorkflowCreateRequest {
  let tasks_converted =
    list.map(wf.tasks, fn(task) { convert_task_to_protocol(task) })

  let concurrency_converted = case wf.concurrency {
    option.Some(config) ->
      option.Some(p.ConcurrencyCreate(
        max_concurrent: config.max_concurrent,
        limit_strategy: convert_limit_strategy(config.limit_strategy),
      ))
    option.None -> option.None
  }

  p.WorkflowCreateRequest(
    name: wf.name,
    description: wf.description,
    version: wf.version,
    tasks: tasks_converted,
    cron: wf.cron,
    events: wf.events,
    concurrency: concurrency_converted,
  )
}

fn convert_task_to_protocol(task: types.TaskDef) -> p.TaskCreate {
  let backoff_converted = case task.retry_backoff {
    option.Some(config) -> option.Some(convert_backoff_config(config))
    option.None -> option.None
  }

  let concurrency_converted = case task.concurrency {
    option.Some(config) ->
      option.Some(p.ConcurrencyCreate(
        max_concurrent: config.max_concurrent,
        limit_strategy: convert_limit_strategy(config.limit_strategy),
      ))
    option.None -> option.None
  }

  let wait_converted = case task.wait_for {
    option.Some(config) -> option.Some(convert_wait_config(config))
    option.None -> option.None
  }

  p.TaskCreate(
    name: task.name,
    parents: task.parents,
    retries: task.retries,
    retry_backoff: backoff_converted,
    execution_timeout_ms: task.execution_timeout_ms,
    schedule_timeout_ms: task.schedule_timeout_ms,
    rate_limits: list.map(task.rate_limits, fn(limit) {
      p.RateLimitCreate(
        key: limit.key,
        units: limit.units,
        duration_ms: limit.duration_ms,
      )
    }),
    concurrency: concurrency_converted,
    wait_for: wait_converted,
  )
}

fn convert_backoff_config(config: types.BackoffConfig) -> p.BackoffCreate {
  case config {
    types.Exponential(base_ms, max_ms) ->
      p.ExponentialCreate(base_ms: base_ms, max_ms: max_ms)
    types.Linear(step_ms, max_ms) ->
      p.LinearCreate(step_ms: step_ms, max_ms: max_ms)
    types.Constant(delay_ms) -> p.ConstantCreate(delay_ms: delay_ms)
  }
}

fn convert_limit_strategy(strategy: types.LimitStrategy) -> String {
  case strategy {
    types.CancelInProgress -> "CANCEL_IN_PROGRESS"
    types.QueueNew -> "QUEUE_NEW"
    types.DropNew -> "DROP_NEW"
  }
}

fn convert_wait_config(config: types.WaitCondition) -> p.WaitCreate {
  case config {
    types.WaitForEvent(event, timeout_ms) ->
      p.WaitForEventCreate(event: event, timeout_ms: timeout_ms)
    types.WaitForTime(duration_ms) ->
      p.WaitForTimeCreate(duration_ms: duration_ms)
    types.WaitForExpression(cel) -> p.WaitForExpressionCreate(cel: cel)
  }
}

/// Export workflow conversion for testing
pub fn convert_workflow_to_protocol_for_test(
  wf: types.Workflow,
) -> p.WorkflowCreateRequest {
  convert_workflow_to_protocol(wf)
}
