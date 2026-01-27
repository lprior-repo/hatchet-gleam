import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option
import hatchet/internal/protocol as p

pub fn encode_workflow_create(req: p.WorkflowCreateRequest) -> String {
  json.object([
    #("name", json.string(req.name)),
    #("description", optionable(json.string, req.description)),
    #("version", optionable(json.string, req.version)),
    #("tasks", json.array(req.tasks, encode_task_create)),
    #("cron", optionable(json.string, req.cron)),
    #("events", json.array(req.events, json.string)),
    #("concurrency", optionable(encode_concurrency, req.concurrency)),
  ])
  |> json.to_string()
}

pub fn encode_task_create(task: p.TaskCreate) -> json.Json {
  json.object([
    #("name", json.string(task.name)),
    #("parents", json.array(task.parents, json.string)),
    #("retries", json.int(task.retries)),
    #("retry_backoff", optionable(encode_backoff, task.retry_backoff)),
    #("execution_timeout_ms", optionable(json.int, task.execution_timeout_ms)),
    #("schedule_timeout_ms", optionable(json.int, task.schedule_timeout_ms)),
    #("rate_limits", json.array(task.rate_limits, encode_rate_limit)),
    #("concurrency", optionable(encode_concurrency, task.concurrency)),
    #("wait_for", optionable(encode_wait, task.wait_for)),
  ])
}

pub fn encode_backoff(backoff: p.BackoffCreate) -> json.Json {
  case backoff {
    p.ExponentialCreate(base_ms, max_ms) -> {
      json.object([
        #("type", json.string("exponential")),
        #("base_ms", json.int(base_ms)),
        #("max_ms", json.int(max_ms)),
      ])
    }
    p.LinearCreate(step_ms, max_ms) -> {
      json.object([
        #("type", json.string("linear")),
        #("step_ms", json.int(step_ms)),
        #("max_ms", json.int(max_ms)),
      ])
    }
    p.ConstantCreate(delay_ms) -> {
      json.object([
        #("type", json.string("constant")),
        #("delay_ms", json.int(delay_ms)),
      ])
    }
  }
}

pub fn encode_rate_limit(limit: p.RateLimitCreate) -> json.Json {
  json.object([
    #("key", json.string(limit.key)),
    #("units", json.int(limit.units)),
    #("duration_ms", json.int(limit.duration_ms)),
  ])
}

pub fn encode_concurrency(concurrency: p.ConcurrencyCreate) -> json.Json {
  json.object([
    #("max_concurrent", json.int(concurrency.max_concurrent)),
    #("limit_strategy", json.string(concurrency.limit_strategy)),
  ])
}

pub fn encode_wait(wait: p.WaitCreate) -> json.Json {
  case wait {
    p.WaitForEventCreate(event, timeout_ms) -> {
      json.object([
        #("type", json.string("event")),
        #("event", json.string(event)),
        #("timeout_ms", json.int(timeout_ms)),
      ])
    }
    p.WaitForTimeCreate(duration_ms) -> {
      json.object([
        #("type", json.string("time")),
        #("duration_ms", json.int(duration_ms)),
      ])
    }
    p.WaitForExpressionCreate(cel) -> {
      json.object([
        #("type", json.string("expression")),
        #("cel", json.string(cel)),
      ])
    }
  }
}

pub fn encode_workflow_run(req: p.WorkflowRunRequest) -> String {
  json.object([
    #("workflow_name", json.string(req.workflow_name)),
    #("input", encode_dynamic(req.input)),
    #(
      "metadata",
      json.object(
        list.map(dict.to_list(req.metadata), fn(pair) {
          #(pair.0, json.string(pair.1))
        }),
      ),
    ),
    #("priority", optionable(json.int, req.priority)),
    #("sticky", json.bool(req.sticky)),
    #("run_key", optionable(json.string, req.run_key)),
  ])
  |> json.to_string()
}

pub fn encode_event_publish(req: p.EventPublishRequest) -> String {
  json.object([
    #("event_key", json.string(req.event_key)),
    #("data", encode_dynamic(req.data)),
    #(
      "metadata",
      json.object(
        list.map(dict.to_list(req.metadata), fn(pair) {
          #(pair.0, json.string(pair.1))
        }),
      ),
    ),
  ])
  |> json.to_string()
}

pub fn encode_worker_register(req: p.WorkerRegisterRequest) -> String {
  json.object([
    #("name", optionable(json.string, req.name)),
    #("slots", json.int(req.slots)),
    #("durable_slots", json.int(req.durable_slots)),
    #(
      "labels",
      json.object(
        list.map(dict.to_list(req.labels), fn(pair) {
          #(pair.0, json.string(pair.1))
        }),
      ),
    ),
    #("workflows", json.array(req.workflows, json.string)),
  ])
  |> json.to_string()
}

pub fn encode_task_complete(req: p.TaskCompleteRequest) -> String {
  json.object([
    #("run_id", json.string(req.run_id)),
    #("task_run_id", json.string(req.task_run_id)),
    #("output", encode_dynamic(req.output)),
  ])
  |> json.to_string()
}

pub fn encode_task_failed(req: p.TaskFailedRequest) -> String {
  json.object([
    #("run_id", json.string(req.run_id)),
    #("task_run_id", json.string(req.task_run_id)),
    #("error", json.string(req.error)),
  ])
  |> json.to_string()
}

pub fn decode_workflow_run_response(
  body: String,
) -> Result(p.WorkflowRunResponse, String) {
  let decoder = {
    use run_id <- decode.field("run_id", decode.string)
    use status <- decode.field("status", decode.string)
    decode.success(p.WorkflowRunResponse(run_id: run_id, status: status))
  }

  case json.parse(from: body, using: decoder) {
    Ok(response) -> Ok(response)
    Error(err) -> Error(decode_error_to_string(err))
  }
}

pub fn decode_workflow_status_response(
  body: String,
) -> Result(p.WorkflowStatusResponse, String) {
  let decoder = {
    use run_id <- decode.field("run_id", decode.string)
    use status <- decode.field("status", decode.string)
    use output <- decode.optional_field(
      "output",
      option.None,
      decode.optional(decode.dynamic),
    )
    use error <- decode.optional_field(
      "error",
      option.None,
      decode.optional(decode.string),
    )
    decode.success(p.WorkflowStatusResponse(
      run_id: run_id,
      status: status,
      output: output,
      error: error,
    ))
  }

  case json.parse(from: body, using: decoder) {
    Ok(response) -> Ok(response)
    Error(err) -> Error(decode_error_to_string(err))
  }
}

pub fn decode_worker_register_response(
  body: String,
) -> Result(p.WorkerRegisterResponse, String) {
  let decoder = {
    use worker_id <- decode.field("worker_id", decode.string)
    decode.success(p.WorkerRegisterResponse(worker_id: worker_id))
  }

  case json.parse(from: body, using: decoder) {
    Ok(response) -> Ok(response)
    Error(err) -> Error(decode_error_to_string(err))
  }
}

pub fn decode_cancel_response(
  body: String,
) -> Result(p.WorkflowCancelResponse, String) {
  let decoder = {
    use success <- decode.field("success", decode.bool)
    decode.success(p.WorkflowCancelResponse(success: success))
  }

  case json.parse(from: body, using: decoder) {
    Ok(response) -> Ok(response)
    Error(err) -> Error(decode_error_to_string(err))
  }
}

// ============================================================================
// Bulk Operation Encoders
// ============================================================================

pub fn encode_bulk_cancel(run_ids: List(String)) -> String {
  json.object([#("run_ids", json.array(run_ids, json.string))])
  |> json.to_string()
}

pub fn encode_bulk_replay(run_ids: List(String)) -> String {
  json.object([#("run_ids", json.array(run_ids, json.string))])
  |> json.to_string()
}

// ============================================================================
// Cron Management Encoders/Decoders
// ============================================================================

pub fn encode_cron_create(req: p.CronCreateRequest) -> String {
  json.object([
    #("name", json.string(req.name)),
    #("expression", json.string(req.expression)),
    #("input", encode_dynamic(req.input)),
  ])
  |> json.to_string()
}

pub fn decode_cron_response(
  body: String,
) -> Result(p.CronResponse, String) {
  let decoder = {
    use cron_id <- decode.field("cron_id", decode.string)
    use name <- decode.field("name", decode.string)
    use expression <- decode.field("expression", decode.string)
    decode.success(p.CronResponse(
      cron_id: cron_id,
      name: name,
      expression: expression,
    ))
  }

  case json.parse(from: body, using: decoder) {
    Ok(response) -> Ok(response)
    Error(err) -> Error(decode_error_to_string(err))
  }
}

// ============================================================================
// Schedule Management Encoders/Decoders
// ============================================================================

pub fn encode_schedule_create(req: p.ScheduleCreateRequest) -> String {
  json.object([
    #("trigger_at", json.string(req.trigger_at)),
    #("input", encode_dynamic(req.input)),
  ])
  |> json.to_string()
}

pub fn decode_schedule_response(
  body: String,
) -> Result(p.ScheduleResponse, String) {
  let decoder = {
    use schedule_id <- decode.field("schedule_id", decode.string)
    use trigger_at <- decode.field("trigger_at", decode.string)
    decode.success(p.ScheduleResponse(
      schedule_id: schedule_id,
      trigger_at: trigger_at,
    ))
  }

  case json.parse(from: body, using: decoder) {
    Ok(response) -> Ok(response)
    Error(err) -> Error(decode_error_to_string(err))
  }
}

// ============================================================================
// Rate Limit Management Encoders
// ============================================================================

pub fn encode_rate_limit_upsert(req: p.RateLimitUpsertRequest) -> String {
  json.object([
    #("key", json.string(req.key)),
    #("limit", json.int(req.limit)),
    #("duration", json.string(req.duration)),
  ])
  |> json.to_string()
}

// ============================================================================
// Decode Helpers
// ============================================================================

fn decode_error_to_string(err: json.DecodeError) -> String {
  case err {
    json.UnexpectedEndOfInput -> "Unexpected end of input"
    json.UnexpectedByte(msg) -> "Unexpected byte: " <> msg
    json.UnexpectedSequence(msg) -> "Unexpected sequence: " <> msg
    json.UnableToDecode(errors) ->
      "Decode error: "
      <> list.fold(errors, "", fn(acc, e) {
        acc <> e.expected <> " != " <> e.found <> "; "
      })
  }
}

fn optionable(encoder: fn(a) -> json.Json, value: option.Option(a)) -> json.Json {
  case value {
    option.Some(v) -> encoder(v)
    option.None -> json.null()
  }
}

fn encode_dynamic(value: dynamic.Dynamic) -> json.Json {
  let decoder =
    decode.one_of(decode.string |> decode.map(json.string), [
      decode.int |> decode.map(json.int),
      decode.bool |> decode.map(json.bool),
      decode.list(decode.dynamic)
        |> decode.map(fn(l) { json.array(l, encode_dynamic) }),
      decode.dict(decode.string, decode.dynamic)
        |> decode.map(fn(d) { json.dict(d, fn(k) { k }, encode_dynamic) }),
    ])

  case decode.run(value, decoder) {
    Ok(json_val) -> json_val
    Error(_) -> json.null()
  }
}
