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

// ============================================================================
// Cron Management
// ============================================================================

pub type CronCreateRequest {
  CronCreateRequest(name: String, expression: String, input: Dynamic)
}

pub type CronResponse {
  CronResponse(cron_id: String, name: String, expression: String)
}

// ============================================================================
// Schedule Management
// ============================================================================

pub type ScheduleCreateRequest {
  ScheduleCreateRequest(trigger_at: String, input: Dynamic)
}

pub type ScheduleResponse {
  ScheduleResponse(schedule_id: String, trigger_at: String)
}

// ============================================================================
// Rate Limit Management
// ============================================================================

pub type RateLimitUpsertRequest {
  RateLimitUpsertRequest(key: String, limit: Int, duration: String)
}

// ============================================================================
// Workflow Management
// ============================================================================

pub type WorkflowMetadata {
  WorkflowMetadata(
    name: String,
    description: Option(String),
    version: Option(String),
    created_at: String,
    cron_triggers: List(String),
    event_triggers: List(String),
    concurrency: Option(Int),
    status: String,
  )
}

pub type WorkflowListResponse {
  WorkflowListResponse(workflows: List(WorkflowMetadata))
}

// ============================================================================
// Worker Management
// ============================================================================

pub type WorkerMetadata {
  WorkerMetadata(
    id: String,
    name: String,
    status: String,
    slots: Int,
    active_slots: Int,
    labels: Dict(String, String),
    last_heartbeat: Option(String),
  )
}

pub type WorkerListResponse {
  WorkerListResponse(workers: List(WorkerMetadata))
}

pub type WorkerPauseRequest {
  WorkerPauseRequest(worker_id: String)
}

pub type WorkerPauseResponse {
  WorkerPauseResponse(success: Bool)
}

pub type WorkerResumeRequest {
  WorkerResumeRequest(worker_id: String)
}

pub type WorkerResumeResponse {
  WorkerResumeResponse(success: Bool)
}

// ============================================================================
// Metrics Management
// ============================================================================

pub type WorkflowMetrics {
  WorkflowMetrics(
    workflow_name: String,
    total_runs: Int,
    successful_runs: Int,
    failed_runs: Int,
    success_rate: Float,
    avg_duration_ms: Option(Int),
    p50_duration_ms: Option(Int),
    p95_duration_ms: Option(Int),
    p99_duration_ms: Option(Int),
  )
}

pub type WorkerMetrics {
  WorkerMetrics(
    worker_id: String,
    total_tasks: Int,
    successful_tasks: Int,
    failed_tasks: Int,
    active_tasks: Int,
    uptime_ms: Option(Int),
  )
}

// ============================================================================
// Logs Management
// ============================================================================

pub type LogEntry {
  LogEntry(
    run_id: String,
    task_run_id: Option(String),
    timestamp: String,
    level: String,
    message: String,
    metadata: Dict(String, String),
  )
}

pub type LogListResponse {
  LogListResponse(logs: List(LogEntry), has_more: Bool)
}

pub type CronListResponse {
  CronListResponse(crons: List(CronMetadata))
}

pub type CronMetadata {
  CronMetadata(
    id: String,
    workflow_name: String,
    name: String,
    expression: String,
    next_run: Option(String),
    created_at: String,
  )
}

pub type ScheduleListResponse {
  ScheduleListResponse(schedules: List(ScheduleMetadata))
}

pub type ScheduleMetadata {
  ScheduleMetadata(
    id: String,
    workflow_name: String,
    trigger_at: String,
    created_at: String,
    status: String,
  )
}
