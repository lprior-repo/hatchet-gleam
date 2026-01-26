# Hatchet Gleam SDK Verification Report

**Date:** 2026-01-26
**Compared Against:** Python SDK, Go SDK (official)
**Unit Test Results:** 68/68 passing

---

## Executive Summary

The Gleam Hatchet SDK is a **partial implementation** that provides type definitions and API surface but **cannot execute workflows** in its current state. Critical infrastructure components are missing or stubbed.

### Verdict: NOT PRODUCTION READY

| Category | Status | Severity |
|----------|--------|----------|
| Type System | Excellent | - |
| API Design | Good | - |
| Unit Tests | Good (68 tests) | - |
| Worker Implementation | **NOT IMPLEMENTED** | CRITICAL |
| gRPC Communication | **NOT IMPLEMENTED** | CRITICAL |
| Task Execution | **NOT IMPLEMENTED** | CRITICAL |
| Polling/Sleep | **BROKEN** | CRITICAL |

---

## Critical Issues (Must Fix)

### 1. Worker Implementation is Stubbed

**Location:** `src/hatchet/client.gleam:26-40`

```gleam
pub fn new_worker(...) -> Result(Worker, String) {
  Ok(types.create_worker("worker_" <> types.get_token(client)))  // Just returns a dummy ID
}

pub fn start_worker_blocking(_worker: Worker) -> Result(Nil, String) {
  Ok(Nil)  // Does nothing
}

pub fn start_worker(_worker: Worker) -> Result(fn() -> Nil, String) {
  Ok(fn() { Nil })  // Does nothing
}
```

**Impact:** Workers cannot register with Hatchet, cannot receive tasks, cannot execute anything.

**Python/Go Implementation:**
- Registers worker with dispatcher via gRPC
- Opens persistent gRPC streaming channel for task polling
- Maintains heartbeat (every 4 seconds)
- Spawns goroutines/threads to execute tasks
- Sends completion events back to dispatcher

---

### 2. No gRPC Implementation

**Current:** Gleam SDK uses HTTP REST API only
**Required:** gRPC is mandatory for worker operations

**Python SDK gRPC usage:**
- `GetActionListener()` - Register worker
- `ListenV2()` - Stream tasks from dispatcher
- `SendStepActionEvent()` - Report task completion
- `PutWorkflow()` - Register workflows
- `Push()` - Event publishing

**Go SDK gRPC usage:**
- Same operations via gRPC streaming
- Keepalive: 10s time, 60s timeout
- Gzip compression
- Automatic retry middleware

**Impact:** The Gleam SDK cannot perform core Hatchet operations that require gRPC.

---

### 3. Sleep Function is Non-Functional

**Location:** `src/hatchet/run.gleam:302-304`

```gleam
fn sleep_ms(_ms: Int) -> Nil {
  Nil  // Does NOT actually sleep
}
```

**Impact:**
- `await_result()` polling loops infinitely without backoff
- CPU spins at 100% when waiting for results
- Timeouts don't work correctly

**Fix Required:** Use `gleam_erlang` or `gleam_otp` for actual sleep:
```gleam
import gleam/erlang/process
fn sleep_ms(ms: Int) -> Nil {
  process.sleep(ms)
}
```

---

### 4. Task Handlers Are Never Invoked

Tasks are defined with handlers but there's no code path that actually calls them:

```gleam
pub type TaskDef {
  TaskDef(
    name: String,
    handler: fn(TaskContext) -> Result(Dynamic, String),  // Stored but never called
    ...
  )
}
```

**Required Architecture:**
1. Worker receives `ACTION_START_STEP_RUN` from dispatcher
2. Look up handler by action ID
3. Create `TaskContext` with input data
4. Execute handler function
5. Send completion/failure event back

---

### 5. Durable Tasks Not Implemented

**Location:** `src/hatchet/types.gleam:63-65`

```gleam
pub type DurableTaskDef {
  DurableTaskDef(task: TaskDef, checkpoint_key: String)  // Type only
}
```

**Python/Go Implementation:**
- `DurableContext` with `SleepFor()` method
- Persistence across process restarts
- Checkpoint mechanism for long-running tasks

---

## Feature Parity Matrix

### Core Client Features

| Feature | Python | Go | Gleam | Notes |
|---------|--------|----|----|-------|
| Client initialization | Yes | Yes | Yes | Works |
| Token authentication | Yes | Yes | Yes | Works |
| Namespace support | Yes | Yes | Yes | Works |
| TLS/mTLS | Yes | Yes | No | Missing |
| Config from env/file | Yes | Yes | No | Missing |
| Connection pooling | Yes | Yes | No | Missing |

### Workflow Definition

| Feature | Python | Go | Gleam | Notes |
|---------|--------|----|----|-------|
| Basic workflow | Yes | Yes | Yes | Types only |
| DAG dependencies | Yes | Yes | Yes | Types only |
| Cron scheduling | Yes | Yes | Yes | Types only |
| Event triggers | Yes | Yes | Yes | Types only |
| Concurrency limits | Yes | Yes | Yes | Types only |
| On-failure handler | Yes | Yes | Yes | Types only |
| Version control | Yes | Yes | Yes | Types only |
| Description | Yes | Yes | Yes | Types only |

### Task Configuration

| Feature | Python | Go | Gleam | Notes |
|---------|--------|----|----|-------|
| Retries | Yes | Yes | Yes | Types only |
| Exponential backoff | Yes | Yes | Yes | Types only |
| Linear backoff | Yes | Yes | Yes | Types only |
| Constant backoff | Yes | Yes | Yes | Types only |
| Execution timeout | Yes | Yes | Yes | Types only |
| Schedule timeout | Yes | Yes | Yes | Types only |
| Rate limits | Yes | Yes | Yes | Types only |
| Skip conditions (CEL) | Yes | Yes | Yes | Types only |
| Wait conditions | Yes | Yes | Yes | Types only |
| Worker labels/affinity | Yes | Yes | No | Missing |

### Worker Features

| Feature | Python | Go | Gleam | Notes |
|---------|--------|----|----|-------|
| Worker registration | Yes | Yes | **No** | STUBBED |
| Task polling | Yes | Yes | **No** | NOT IMPLEMENTED |
| Task execution | Yes | Yes | **No** | NOT IMPLEMENTED |
| Heartbeat | Yes | Yes | **No** | NOT IMPLEMENTED |
| Graceful shutdown | Yes | Yes | **No** | NOT IMPLEMENTED |
| Max concurrent runs | Yes | Yes | Types only | NOT ENFORCED |
| Durable task slots | Yes | Yes | Types only | NOT ENFORCED |
| Health checks | Yes | Yes | **No** | NOT IMPLEMENTED |
| Panic recovery | Yes | Yes | **No** | NOT IMPLEMENTED |
| Worker labels | Yes | Yes | Types only | NOT USED |

### Task Context

| Feature | Python | Go | Gleam | Notes |
|---------|--------|----|----|-------|
| Get input | Yes | Yes | Yes | Type exists |
| Get parent output | Yes | Yes | Yes | Type exists |
| Get metadata | Yes | Yes | Yes | Type exists |
| Log messages | Yes | Yes | Yes | Type exists |
| Spawn child workflow | Yes | Yes | **No** | Missing |
| Stream events | Yes | Yes | **No** | Missing |
| Refresh timeout | Yes | Yes | **No** | Missing |
| Release slot early | Yes | Yes | **No** | Missing |
| Get retry count | Yes | Yes | **No** | Missing |
| Get step errors | Yes | Yes | **No** | Missing |

### Workflow Execution

| Feature | Python | Go | Gleam | Notes |
|---------|--------|----|----|-------|
| Run (blocking) | Yes | Yes | Partial | Uses REST, polling broken |
| Run (async) | Yes | Yes | Partial | Uses REST |
| Run many (batch) | Yes | Yes | Yes | Sequential, not parallel |
| Get status | Yes | Yes | Yes | REST API |
| Cancel run | Yes | Yes | Yes | REST API |
| Await result | Yes | Yes | **Broken** | Sleep doesn't work |

### Event Publishing

| Feature | Python | Go | Gleam | Notes |
|---------|--------|----|----|-------|
| Push single event | Yes | Yes | Yes | REST API |
| Push with metadata | Yes | Yes | Yes | REST API |
| Bulk push | Yes | Yes | Yes | Sequential |
| Event-triggered workflows | Yes | Yes | Types only | - |

### Advanced Features

| Feature | Python | Go | Gleam | Notes |
|---------|--------|----|----|-------|
| CEL expressions | Yes | Yes | Types only | Server-side |
| Dynamic rate limits | Yes | Yes | **No** | Missing |
| Input validation | Yes | Yes | **No** | Missing |
| Sticky workers | Yes | Yes | Types only | - |
| Priority queues | Yes | Yes | Types only | - |
| Deduplication | Yes | Yes | **No** | Missing |
| Scheduled runs | Yes | Yes | **No** | Missing |
| Cron management API | Yes | Yes | **No** | Missing |
| Webhook support | Yes | Yes | **No** | Missing |
| Metrics API | Yes | Yes | **No** | Missing |
| Logs API | Yes | Yes | **No** | Missing |

---

## API Endpoint Analysis

### What Gleam SDK Uses (REST)

```
POST /api/v1/workflows/{name}/run     - Trigger workflow
GET  /api/v1/runs/{id}/status         - Check status
GET  /api/v1/runs/{id}                - Get output
POST /api/v1/runs/{id}/cancel         - Cancel run
POST /api/v1/events                   - Publish event
```

### What's Missing (gRPC Required)

```
Dispatcher.GetActionListener          - Register worker
Dispatcher.ListenV2                   - Stream tasks
Dispatcher.SendStepActionEvent        - Report completion
AdminService.PutWorkflow              - Register workflow
EventsService.Push                    - High-throughput events
WorkflowService.SubscribeToWorkflowRuns - Real-time updates
```

---

## Test Coverage Analysis

**Total Tests:** 68 passing

| Module | Tests | Coverage |
|--------|-------|----------|
| client_test | 6 | Client creation, configuration |
| workflow_test | 16 | Workflow builder, properties |
| task_test | 28 | Task config, backoff, rate limits |
| standalone_test | 7 | Standalone task wrapper |
| json_test | 14 | JSON encoding/decoding |
| integration_test | 19 | Multi-module integration |

**What's NOT Tested:**
- Actual API calls (no integration tests against server)
- Worker registration and task execution
- gRPC communication
- Error recovery and retries
- Concurrent execution

---

## Code Quality Issues

### 1. Unused Dependencies

```toml
gleam_otp = ">= 0.15.0"      # Available but not used
gleam_erlang = ">= 0.30.0"   # Available but not used
```

These should be used for:
- Process supervision (OTP)
- Sleep/timer functions (erlang)
- gRPC client implementation

### 2. Unused Imports (Compiler Warnings)

```
src/hatchet/workflow.gleam:6 - type TaskDef
src/hatchet/standalone.gleam:5 - type TaskDef
src/hatchet/task.gleam:3 - type DecodeError
src/hatchet/task.gleam:6 - gleam/result module
... (15 more warnings)
```

### 3. Dynamic Type Handling

**Location:** `src/hatchet/internal/json.gleam`

The `encode_dynamic()` function silently converts unrecognized types to `null`:
```gleam
// May silently lose data on unrecognized Dynamic values
```

---

## Implementation Roadmap

### Phase 1: Critical Fixes (Required for any functionality)

1. **Implement sleep function**
   - Use `gleam_erlang/process.sleep()`
   - Fix polling in `await_result()`

2. **Add gRPC support**
   - Research Gleam gRPC libraries (may need FFI to Erlang)
   - Implement dispatcher connection
   - Implement action streaming

3. **Implement worker registration**
   - `GetActionListener` gRPC call
   - Heartbeat mechanism
   - Action listener process

### Phase 2: Task Execution

4. **Implement task execution loop**
   - Receive actions from stream
   - Look up handlers
   - Execute with proper context
   - Report completion

5. **Implement context methods**
   - Spawn child workflows
   - Stream events
   - Logging

### Phase 3: Production Features

6. **Add TLS support**
7. **Add config file/env loading**
8. **Implement health checks**
9. **Add graceful shutdown**
10. **Implement durable tasks**

### Phase 4: API Completeness

11. **Cron management API**
12. **Scheduled runs API**
13. **Metrics API**
14. **Logs API**
15. **Webhook support**

---

## Recommended Gleam Libraries

| Need | Library | Notes |
|------|---------|-------|
| gRPC | `gleam_grpc` or Erlang FFI | May need custom implementation |
| Sleep/Process | `gleam_erlang` | Already in deps |
| Supervision | `gleam_otp` | Already in deps |
| TLS | `gleam_ssl` or Erlang FFI | For secure connections |
| Protobuf | `gleam_proto` or Erlang FFI | For gRPC messages |

---

## Comparison with Official SDK Quality

### Python SDK Strengths
- Complete gRPC implementation
- Multi-process architecture for workers
- Comprehensive error handling with tenacity
- Health check endpoints
- Full REST API for queries
- Input validation with Pydantic
- Both sync and async APIs

### Go SDK Strengths
- Clean interface design
- Efficient goroutine-based workers
- Strong middleware support
- Panic recovery
- Comprehensive context API
- Feature clients for management

### Gleam SDK Status
- Good type definitions
- Clean builder pattern API
- Solid unit test foundation
- **Missing all runtime components**

---

## Conclusion

The Gleam Hatchet SDK has a well-designed API surface and type system, but it's essentially a **type library without runtime implementation**. To be production-ready, it needs:

1. gRPC implementation (fundamental requirement)
2. Working worker process with task execution
3. Proper async/sleep primitives
4. Integration testing against real Hatchet server

**Current State:** Can define workflows, cannot execute them.
**Effort Estimate:** Significant development work required for core functionality.

---

## Files Reference

| File | Lines | Status |
|------|-------|--------|
| `src/hatchet.gleam` | 450 | Facade - OK |
| `src/hatchet/types.gleam` | 199 | Types - OK |
| `src/hatchet/client.gleam` | 41 | **STUBBED** |
| `src/hatchet/workflow.gleam` | 258 | Builder - OK |
| `src/hatchet/task.gleam` | 183 | Helpers - OK |
| `src/hatchet/run.gleam` | 305 | REST client - **BROKEN** (sleep) |
| `src/hatchet/events.gleam` | 95 | REST client - OK |
| `src/hatchet/standalone.gleam` | 52 | Wrapper - OK |
| `src/hatchet/internal/protocol.gleam` | 141 | Message types - OK |
| `src/hatchet/internal/json.gleam` | 280 | JSON codec - OK |
