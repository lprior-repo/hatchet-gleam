import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/http.{type Method}
import gleam/option.{type Option}

pub type HttpRequest {
  HttpRequest(
    method: Method,
    path: String,
    headers: Dict(String, String),
    body: String,
  )
}

pub type HttpResponse {
  HttpResponse(status: Int, headers: Dict(String, String), body: String)
}

pub type WorkflowCreateRequest {
  WorkflowCreateRequest(
    name: String,
    description: Option(String),
    version: Option(String),
    tasks: List(TaskCreate),
    cron: Option(String),
    events: List(String),
    concurrency: Option(ConcurrencyCreate),
  )
}

pub type TaskCreate {
  TaskCreate(
    name: String,
    parents: List(String),
    retries: Int,
    retry_backoff: Option(BackoffCreate),
    execution_timeout_ms: Option(Int),
    schedule_timeout_ms: Option(Int),
    rate_limits: List(RateLimitCreate),
    concurrency: Option(ConcurrencyCreate),
    wait_for: Option(WaitCreate),
  )
}

pub type BackoffCreate {
  ExponentialCreate(base_ms: Int, max_ms: Int)
  LinearCreate(step_ms: Int, max_ms: Int)
  ConstantCreate(delay_ms: Int)
}

pub type RateLimitCreate {
  RateLimitCreate(key: String, units: Int, duration_ms: Int)
}

pub type WaitCreate {
  WaitForEventCreate(event: String, timeout_ms: Int)
  WaitForTimeCreate(duration_ms: Int)
  WaitForExpressionCreate(cel: String)
}

pub type ConcurrencyCreate {
  ConcurrencyCreate(max_concurrent: Int, limit_strategy: String)
}

pub type WorkflowRunRequest {
  WorkflowRunRequest(
    workflow_name: String,
    input: Dynamic,
    metadata: Dict(String, String),
    priority: Option(Int),
    sticky: Bool,
    run_key: Option(String),
  )
}

pub type WorkflowRunResponse {
  WorkflowRunResponse(run_id: String, status: String)
}

pub type WorkflowStatusResponse {
  WorkflowStatusResponse(
    run_id: String,
    status: String,
    output: Option(Dynamic),
    error: Option(String),
  )
}

pub type EventPublishRequest {
  EventPublishRequest(
    event_key: String,
    data: Dynamic,
    metadata: Dict(String, String),
  )
}

pub type WorkerRegisterRequest {
  WorkerRegisterRequest(
    name: Option(String),
    slots: Int,
    durable_slots: Int,
    labels: Dict(String, String),
    workflows: List(String),
  )
}

pub type WorkerRegisterResponse {
  WorkerRegisterResponse(worker_id: String)
}

pub type TaskHeartbeatRequest {
  TaskHeartbeatRequest(
    run_id: String,
    task_run_id: String,
    output: Option(Dynamic),
  )
}

pub type TaskCompleteRequest {
  TaskCompleteRequest(run_id: String, task_run_id: String, output: Dynamic)
}

pub type TaskFailedRequest {
  TaskFailedRequest(run_id: String, task_run_id: String, error: String)
}

pub type WorkflowCancelRequest {
  WorkflowCancelRequest(run_id: String)
}

pub type WorkflowCancelResponse {
  WorkflowCancelResponse(success: Bool)
}

pub type Error {
  ApiError(status: Int, message: String)
  NetworkError(reason: String)
  DecodeError(reason: String)
  ValidationError(reason: String)
}
