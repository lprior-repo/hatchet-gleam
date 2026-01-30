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

pub fn decode_cron_response(body: String) -> Result(p.CronResponse, String) {
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
// Workflow Management Decoders
// ============================================================================

pub fn decode_workflow_list(
  body: String,
) -> Result(p.WorkflowListResponse, String) {
  let decoder = {
    use workflows <- decode.field(
      "workflows",
      decode.list(decode_workflow_metadata_internal()),
    )
    decode.success(p.WorkflowListResponse(workflows: workflows))
  }

  case json.parse(from: body, using: decoder) {
    Ok(response) -> Ok(response)
    Error(err) -> Error(decode_error_to_string(err))
  }
}

fn decode_workflow_metadata_internal() -> decode.Decoder(p.WorkflowMetadata) {
  let decoder = {
    use name <- decode.field("name", decode.string)
    use description <- decode.optional_field(
      "description",
      option.None,
      decode.optional(decode.string),
    )
    use version <- decode.optional_field(
      "version",
      option.None,
      decode.optional(decode.string),
    )
    use created_at <- decode.field("created_at", decode.string)
    use cron_triggers <- decode.field(
      "cron_triggers",
      decode.list(decode.string),
    )
    use event_triggers <- decode.field(
      "event_triggers",
      decode.list(decode.string),
    )
    use concurrency <- decode.optional_field(
      "concurrency",
      option.None,
      decode.optional(decode.int),
    )
    use status <- decode.field("status", decode.string)
    decode.success(p.WorkflowMetadata(
      name: name,
      description: description,
      version: version,
      created_at: created_at,
      cron_triggers: cron_triggers,
      event_triggers: event_triggers,
      concurrency: concurrency,
      status: status,
    ))
  }
  decoder
}

pub fn decode_workflow_metadata(
  body: String,
) -> Result(p.WorkflowMetadata, String) {
  case json.parse(from: body, using: decode_workflow_metadata_internal()) {
    Ok(metadata) -> Ok(metadata)
    Error(err) -> Error(decode_error_to_string(err))
  }
}

// ============================================================================
// Worker Management Decoders
// ============================================================================

pub fn decode_worker_list(body: String) -> Result(p.WorkerListResponse, String) {
  let decoder = {
    use workers <- decode.field(
      "workers",
      decode.list(decode_worker_metadata()),
    )
    decode.success(p.WorkerListResponse(workers: workers))
  }

  case json.parse(from: body, using: decoder) {
    Ok(response) -> Ok(response)
    Error(err) -> Error(decode_error_to_string(err))
  }
}

fn decode_worker_metadata() -> decode.Decoder(p.WorkerMetadata) {
  let decoder = {
    use id <- decode.field("id", decode.string)
    use name <- decode.field("name", decode.string)
    use status <- decode.field("status", decode.string)
    use slots <- decode.field("slots", decode.int)
    use active_slots <- decode.field("active_slots", decode.int)
    use labels <- decode.field(
      "labels",
      decode.dict(decode.string, decode.string),
    )
    use last_heartbeat <- decode.optional_field(
      "last_heartbeat",
      option.None,
      decode.optional(decode.string),
    )
    decode.success(p.WorkerMetadata(
      id: id,
      name: name,
      status: status,
      slots: slots,
      active_slots: active_slots,
      labels: labels,
      last_heartbeat: last_heartbeat,
    ))
  }
  decoder
}

pub fn decode_worker_pause_response(
  body: String,
) -> Result(p.WorkerPauseResponse, String) {
  let decoder = {
    use success <- decode.field("success", decode.bool)
    decode.success(p.WorkerPauseResponse(success: success))
  }

  case json.parse(from: body, using: decoder) {
    Ok(response) -> Ok(response)
    Error(err) -> Error(decode_error_to_string(err))
  }
}

pub fn decode_worker_resume_response(
  body: String,
) -> Result(p.WorkerResumeResponse, String) {
  let decoder = {
    use success <- decode.field("success", decode.bool)
    decode.success(p.WorkerResumeResponse(success: success))
  }

  case json.parse(from: body, using: decoder) {
    Ok(response) -> Ok(response)
    Error(err) -> Error(decode_error_to_string(err))
  }
}

// ============================================================================
// Metrics Management Decoders
// ============================================================================

pub fn decode_workflow_metrics(
  body: String,
) -> Result(p.WorkflowMetrics, String) {
  let decoder = {
    use workflow_name <- decode.field("workflow_name", decode.string)
    use total_runs <- decode.field("total_runs", decode.int)
    use successful_runs <- decode.field("successful_runs", decode.int)
    use failed_runs <- decode.field("failed_runs", decode.int)
    use success_rate <- decode.field("success_rate", decode.float)
    use avg_duration_ms <- decode.optional_field(
      "avg_duration_ms",
      option.None,
      decode.optional(decode.int),
    )
    use p50_duration_ms <- decode.optional_field(
      "p50_duration_ms",
      option.None,
      decode.optional(decode.int),
    )
    use p95_duration_ms <- decode.optional_field(
      "p95_duration_ms",
      option.None,
      decode.optional(decode.int),
    )
    use p99_duration_ms <- decode.optional_field(
      "p99_duration_ms",
      option.None,
      decode.optional(decode.int),
    )
    decode.success(p.WorkflowMetrics(
      workflow_name: workflow_name,
      total_runs: total_runs,
      successful_runs: successful_runs,
      failed_runs: failed_runs,
      success_rate: success_rate,
      avg_duration_ms: avg_duration_ms,
      p50_duration_ms: p50_duration_ms,
      p95_duration_ms: p95_duration_ms,
      p99_duration_ms: p99_duration_ms,
    ))
  }

  case json.parse(from: body, using: decoder) {
    Ok(response) -> Ok(response)
    Error(err) -> Error(decode_error_to_string(err))
  }
}

pub fn decode_worker_metrics(body: String) -> Result(p.WorkerMetrics, String) {
  let decoder = {
    use worker_id <- decode.field("worker_id", decode.string)
    use total_tasks <- decode.field("total_tasks", decode.int)
    use successful_tasks <- decode.field("successful_tasks", decode.int)
    use failed_tasks <- decode.field("failed_tasks", decode.int)
    use active_tasks <- decode.field("active_tasks", decode.int)
    use uptime_ms <- decode.optional_field(
      "uptime_ms",
      option.None,
      decode.optional(decode.int),
    )
    decode.success(p.WorkerMetrics(
      worker_id: worker_id,
      total_tasks: total_tasks,
      successful_tasks: successful_tasks,
      failed_tasks: failed_tasks,
      active_tasks: active_tasks,
      uptime_ms: uptime_ms,
    ))
  }

  case json.parse(from: body, using: decoder) {
    Ok(response) -> Ok(response)
    Error(err) -> Error(decode_error_to_string(err))
  }
}

// ============================================================================
// Logs Management Decoders
// ============================================================================

pub fn decode_log_list(body: String) -> Result(p.LogListResponse, String) {
  let decoder = {
    use logs <- decode.field("logs", decode.list(decode_log_entry()))
    use has_more <- decode.field("has_more", decode.bool)
    decode.success(p.LogListResponse(logs: logs, has_more: has_more))
  }

  case json.parse(from: body, using: decoder) {
    Ok(response) -> Ok(response)
    Error(err) -> Error(decode_error_to_string(err))
  }
}

fn decode_log_entry() -> decode.Decoder(p.LogEntry) {
  let decoder = {
    use run_id <- decode.field("run_id", decode.string)
    use task_run_id <- decode.optional_field(
      "task_run_id",
      option.None,
      decode.optional(decode.string),
    )
    use timestamp <- decode.field("timestamp", decode.string)
    use level <- decode.field("level", decode.string)
    use message <- decode.field("message", decode.string)
    use metadata <- decode.field(
      "metadata",
      decode.dict(decode.string, decode.string),
    )
    decode.success(p.LogEntry(
      run_id: run_id,
      task_run_id: task_run_id,
      timestamp: timestamp,
      level: level,
      message: message,
      metadata: metadata,
    ))
  }
  decoder
}

// ============================================================================
// Cron List Decoder
// ============================================================================

pub fn decode_cron_list(body: String) -> Result(p.CronListResponse, String) {
  let decoder = {
    use crons <- decode.field("crons", decode.list(decode_cron_metadata()))
    decode.success(p.CronListResponse(crons: crons))
  }

  case json.parse(from: body, using: decoder) {
    Ok(response) -> Ok(response)
    Error(err) -> Error(decode_error_to_string(err))
  }
}

fn decode_cron_metadata() -> decode.Decoder(p.CronMetadata) {
  let decoder = {
    use id <- decode.field("id", decode.string)
    use workflow_name <- decode.field("workflow_name", decode.string)
    use name <- decode.field("name", decode.string)
    use expression <- decode.field("expression", decode.string)
    use next_run <- decode.optional_field(
      "next_run",
      option.None,
      decode.optional(decode.string),
    )
    use created_at <- decode.field("created_at", decode.string)
    decode.success(p.CronMetadata(
      id: id,
      workflow_name: workflow_name,
      name: name,
      expression: expression,
      next_run: next_run,
      created_at: created_at,
    ))
  }
  decoder
}

// ============================================================================
// Schedule List Decoder
// ============================================================================

// ============================================================================
// Worker Management Encoders
// ============================================================================

pub fn encode_worker_pause(req: p.WorkerPauseRequest) -> String {
  json.object([#("worker_id", json.string(req.worker_id))])
  |> json.to_string()
}

pub fn encode_worker_resume(req: p.WorkerResumeRequest) -> String {
  json.object([#("worker_id", json.string(req.worker_id))])
  |> json.to_string()
}

pub fn decode_schedule_list(
  body: String,
) -> Result(p.ScheduleListResponse, String) {
  let decoder = {
    use schedules <- decode.field(
      "schedules",
      decode.list(decode_schedule_metadata()),
    )
    decode.success(p.ScheduleListResponse(schedules: schedules))
  }

  case json.parse(from: body, using: decoder) {
    Ok(response) -> Ok(response)
    Error(err) -> Error(decode_error_to_string(err))
  }
}

fn decode_schedule_metadata() -> decode.Decoder(p.ScheduleMetadata) {
  let decoder = {
    use id <- decode.field("id", decode.string)
    use workflow_name <- decode.field("workflow_name", decode.string)
    use trigger_at <- decode.field("trigger_at", decode.string)
    use created_at <- decode.field("created_at", decode.string)
    use status <- decode.field("status", decode.string)
    decode.success(p.ScheduleMetadata(
      id: id,
      workflow_name: workflow_name,
      trigger_at: trigger_at,
      created_at: created_at,
      status: status,
    ))
  }
  decoder
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
