# Hatchet Integration Design Review

**Date**: 2026-01-01
**Purpose**: Review Hatchet integrations for maximum cohesion, minimal coupling, and AI-friendliness
**Principles**: Dave Farley (Continuous Delivery, Accelerate), Hexagonal Architecture, Domain-Driven Design

---

## Executive Summary

The current Hatchet integration is **functionally correct but architecturally immature**. The 9-step workflow system provides robust task orchestration with self-healing and comprehensive observability. However, the implementation suffers from:

1. **Monolithic workflow factory** (1,755 lines)
2. **Closure capture anti-pattern** in step implementations
3. **Tight coupling** between orchestration and domain logic
4. **Missing abstraction boundaries** (Ports and Adapters)
5. **Incomplete refactoring** (helper functions exist but aren't connected)

**Recommended priority**: Refactor to **Ports and Adapters (Hexagonal Architecture)** with extracted step implementations to achieve testability, AI-discoverability, and continuous delivery capabilities.

---

## Current Architecture Analysis

### File Structure (2,185 lines across 7 files)

| File | Lines | Responsibility | Coupling Score |
|------|-------|----------------|----------------|
| `workflow_factory.go` | 1,755 | 9-step workflow + all step logic | **HIGH** ❌ |
| `hatchet_integration.go` | 410 | HatchetRunner orchestration | MEDIUM |
| `hatchet_beads_bridge.go` | 125 | Beads↔Hatchet adapter | LOW ✓ |
| `hatchet.go` | 153 | HatchetOrchestrator | LOW ✓ |
| `workflow_helpers.go` | 98 | StepLogger utility | LOW ✓ |
| `workflow_step_helpers.go` | 232 | Extracted step stubs | **DISCONNECTED** ❌ |
| `workflow_validation.go` | 248 | Output validation | LOW ✓ |
| `types.go` | 573 | StepContext, Config, State | MEDIUM |

### Dependency Graph

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          BeadsRunner (God Object)                        │
│  - client, cmdExecutor, gitClient, verifierRegistry, serverLifecycle    │
│  - hatchetRunner, retryCounters, impasseResolver, sessionMonitor        │
└─────────────────────────────────────────────────────────────────────────┘
           │                           │                          │
           ▼                           ▼                          ▼
  ┌─────────────────┐        ┌─────────────────┐        ┌─────────────────┐
  │  HatchetRunner  │◄──────►│ HatchetWorkflow │        │  HatchetBeads   │
  │                 │        │    Factory      │        │     Bridge      │
  │  - orchestrator │        │                 │        │                 │
  │  - workflowMgr  │        │  - 9 inline     │        │  - orchestrator │
  │  - bridge       │        │    step closures│        │  - workflowMgr  │
  │  - worker       │        │  - runner ref   │        │  - runner       │
  │  - runner ◄─────┼────────┼──────────►      │        │                 │
  └─────────────────┘        └─────────────────┘        └─────────────────┘
           │                           │
           ▼                           ▼
  ┌─────────────────┐        ┌─────────────────┐
  │  Hatchet Client │        │  StepContext    │
  │  (v0.74.0)      │        │  (incomplete)   │
  └─────────────────┘        └─────────────────┘
```

---

## Design Issues (Dave Farley Principles)

### 1. **Violation: Low Cohesion in workflow_factory.go**

**Principle**: *"Each module should do one thing well"* (Single Responsibility)

**Problem**: `CreateBeadsTaskWorkflow()` is 1,100+ lines containing:
- Workflow orchestration (DAG setup)
- All 9 step implementations inline as closures
- Error handling for each step
- Metrics recording
- Logging

**Evidence** (workflow_factory.go:611-1647):
```go
func (hwf *HatchetWorkflowFactory) CreateBeadsTaskWorkflow() (*hatchet.Workflow, error) {
    // ... 1000+ lines of step closures
    ensureServerStep := workflow.NewTask("ensure-server", func(ctx hatchet.Context, input TaskInput) (EnsureServerOutput, error) {
        // 60 lines of logic
    })
    validateStep := workflow.NewTask("validate", func(...) { /* 70 lines */ })
    // ... 7 more steps
}
```

**Impact**:
- Cannot test steps independently
- Code review is painful (context loss)
- AI agents struggle to find specific logic
- Changes risk breaking unrelated steps

### 2. **Violation: Closure Capture Anti-Pattern**

**Principle**: *"Make dependencies explicit"* (Dependency Injection)

**Problem**: Step closures capture `runner` and `hwf` implicitly:

```go
// workflow_factory.go:623
runner := hwf.runner  // Captured in closure scope

ensureServerStep := workflow.NewTask("ensure-server",
    func(ctx hatchet.Context, input TaskInput) (EnsureServerOutput, error) {
        lifecycle := runner.ServerLifecycle()  // Hidden dependency!
        // ...
    })
```

**Impact**:
- Cannot mock dependencies for testing
- Hidden coupling makes reasoning difficult
- No compile-time guarantees about dependencies

### 3. **Violation: Incomplete Abstraction (StepContext)**

**Principle**: *"Design for testability"*

**Problem**: `StepContext` exists (workflow_factory.go:255-272) but isn't used by actual steps:

```go
// StepContext exists in types...
type StepContext struct {
    ServerLifecycle       *ServerLifecycleManager
    Client                OpenCodeClient
    ProcessTaskFunc       func(context.Context, *BeadTask) (string, error)
    // ...
}

// But steps still use runner directly:
runner.ProcessTaskSync(logCtx, task)  // Not stepContext.ProcessTaskFunc()
```

**Impact**:
- Tests must mock entire `BeadsRunner`
- StepContext is dead code
- Refactoring promise unfulfilled

### 4. **Violation: Missing Ports and Adapters**

**Principle**: *"Isolate domain logic from infrastructure"* (Hexagonal Architecture)

**Problem**: Domain logic (task execution) is entangled with infrastructure (Hatchet SDK):

```go
// Domain logic (BeadTask processing) inside infrastructure (Hatchet step):
executeStep := workflow.NewTask("execute", func(ctx hatchet.Context, input TaskInput) {
    task := &BeadTask{...}  // Domain
    _, err := hwf.runner.ProcessTaskSync(logCtx, task)  // Domain
    // All inside Hatchet infrastructure
})
```

**Impact**:
- Cannot swap orchestrator (Hatchet → Temporal)
- Cannot run domain logic without Hatchet
- Testing requires Hatchet infrastructure

### 5. **Violation: Scattered Observability**

**Principle**: *"Cross-cutting concerns should be handled uniformly"*

**Problem**: Metrics/logging duplicated in every step (60+ occurrences):

```go
// Repeated in EVERY step:
stepCtx := enrichHatchetStepContext(input, "step-name", N, 1)
logger.Info(logCtx, "[Step N/8] ...", stepCtx)
recordHatchetStepMetric(logCtx, "step-name", time.Since(stepStart), success, 0)
```

**Impact**:
- Inconsistent observability when copy-paste errors occur
- Cannot add new cross-cutting concern without touching all steps
- Violates DRY

### 6. **Violation: Disconnected Helper Functions**

**Principle**: *"Working software over comprehensive documentation"*

**Problem**: `workflow_step_helpers.go` has stub implementations not connected to workflow:

```go
// workflow_step_helpers.go:84-112 - handleValidate exists but has dummy logic:
func handleValidate(input TaskInput) (ValidateOutput, error) {
    // Only validates TaskID, doesn't call ctx.ParentOutput()
    if input.TaskID == "" {
        return ValidateOutput{Valid: false, Error: "TaskID is empty"}, nil
    }
    return ValidateOutput{Valid: true, TaskID: input.TaskID}, nil
}

// Meanwhile, workflow_factory.go:703-775 has the REAL implementation:
validateStep := workflow.NewTask("validate", func(ctx hatchet.Context, input TaskInput) {
    var serverOutput EnsureServerOutput
    if err := ctx.ParentOutput(ensureServerStep, &serverOutput); err != nil {...}
    // ... actual validation logic
})
```

**Impact**:
- Confusing codebase (two versions of same logic)
- Tests may pass on wrong implementation
- AI agents find wrong code

---

## AI-Friendliness Issues

### 1. **Discoverability**

| Need | Current | Ideal |
|------|---------|-------|
| Find step logic | Grep 1,700-line file | Read `steps/ensure_server.go` |
| Understand dependencies | Trace closure captures | Look at function signature |
| Find related tests | Search for "Step 0" | Check `steps/ensure_server_test.go` |

### 2. **Predictability**

**Problem**: Steps have different patterns:
- Some use `handleXxx()` helpers (not connected)
- Some use inline logic
- Some use `StepLogger`, most don't
- Error handling varies

**Ideal**: Every step follows identical structure.

### 3. **Atomicity**

**Problem**: Changes to one step require understanding 1,700 lines of context.

**Ideal**: Each step in separate file, ~100 lines max.

---

## Recommended Architecture

### Target: Hexagonal Architecture with Extracted Steps

```
┌─────────────────────────────────────────────────────────────────────────┐
│                            DOMAIN LAYER                                  │
│  pkg/domain/                                                            │
│  ├── task.go          (BeadTask, TaskInput, TaskOutput)                 │
│  ├── workflow.go      (WorkflowStep interface, StepResult)              │
│  └── verifier.go      (Verifier interface, VerifierRegistry)            │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         APPLICATION LAYER                                │
│  pkg/workflow/steps/                                                    │
│  ├── step.go          (Step interface, StepContext)                     │
│  ├── ensure_server.go (EnsureServerStep)                                │
│  ├── validate.go      (ValidateStep)                                    │
│  ├── resolve_deps.go  (ResolveDepsStep)                                 │
│  ├── tdd_guard.go     (TDDGuardStep)                                    │
│  ├── execute.go       (ExecuteStep)                                     │
│  ├── self_healing.go  (SelfHealingStep)                                 │
│  ├── tcr.go           (TCRStep)                                         │
│  ├── capture.go       (CaptureStep)                                     │
│  └── sync_beads.go    (SyncBeadsStep)                                   │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          ADAPTER LAYER                                   │
│  pkg/adapter/hatchet/                                                   │
│  ├── workflow_builder.go   (Builds Hatchet workflow from steps)         │
│  ├── step_adapter.go       (Adapts Step → hatchet.Task)                 │
│  └── observability.go      (Metrics, logging middleware)                │
│                                                                         │
│  pkg/adapter/beads/                                                     │
│  ├── bridge.go             (BeadsBridge for task sync)                  │
│  └── client.go             (Beads CLI wrapper)                          │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         INFRASTRUCTURE LAYER                             │
│  pkg/infra/                                                             │
│  ├── hatchet/client.go     (Hatchet client wrapper)                     │
│  ├── opencode/client.go    (OpenCode client wrapper)                    │
│  └── observability/        (OTEL, structured logging)                   │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Refactoring Plan

### Phase 1: Extract Step Interface (Week 1)

**Goal**: Define clean step abstraction without changing behavior.

```go
// pkg/workflow/step.go
package workflow

// Step represents a single workflow step with explicit dependencies
type Step interface {
    Name() string
    Execute(ctx context.Context, deps StepDeps, input StepInput) (StepOutput, error)
}

// StepDeps contains all dependencies a step might need
type StepDeps struct {
    ServerLifecycle  ServerLifecyclePort
    TaskProcessor    TaskProcessorPort
    DependencyChecker DependencyCheckerPort
    TDDGuard         TDDGuardPort
    Verifier         VerifierPort
    TCRRunner        TCRRunnerPort
    BeadsSync        BeadsSyncPort
    Config           *Config
    Logger           Logger
    Metrics          MetricsRecorder
}

// StepInput is the generic input passed between steps
type StepInput struct {
    TaskInput
    ParentOutputs map[string]interface{}
}

// StepOutput is the generic output from a step
type StepOutput interface {
    StepName() string
    Success() bool
    Error() error
}
```

### Phase 2: Extract Individual Steps (Week 2)

**Goal**: Move each step to its own file with tests.

**Example**: `pkg/workflow/steps/ensure_server.go`

```go
package steps

import (
    "context"
    "time"
    "github.com/your-org/beads-runner/pkg/workflow"
)

// EnsureServerStep verifies the OpenCode server is running
type EnsureServerStep struct{}

func NewEnsureServerStep() *EnsureServerStep {
    return &EnsureServerStep{}
}

func (s *EnsureServerStep) Name() string {
    return "ensure-server"
}

func (s *EnsureServerStep) Execute(
    ctx context.Context,
    deps workflow.StepDeps,
    input workflow.StepInput,
) (workflow.StepOutput, error) {
    start := time.Now()
    defer deps.Metrics.RecordStepDuration(s.Name(), time.Since(start))

    deps.Logger.Info(ctx, "Ensuring OpenCode server is running", map[string]any{
        "task_id": input.TaskID,
    })

    // Use port instead of concrete implementation
    if err := deps.ServerLifecycle.EnsureReady(ctx); err != nil {
        deps.Metrics.RecordStepFailure(s.Name())
        return &EnsureServerOutput{
            Running: false,
            Error:   err.Error(),
        }, err
    }

    serverURL := deps.ServerLifecycle.ServerURL()
    deps.Metrics.RecordStepSuccess(s.Name())

    return &EnsureServerOutput{
        Running:   true,
        ServerURL: serverURL,
    }, nil
}

// EnsureServerOutput is the output of this step
type EnsureServerOutput struct {
    Running   bool
    ServerURL string
    Error     string
}

func (o *EnsureServerOutput) StepName() string { return "ensure-server" }
func (o *EnsureServerOutput) Success() bool    { return o.Running }
func (o *EnsureServerOutput) Error() error {
    if o.Error != "" {
        return fmt.Errorf("%s", o.Error)
    }
    return nil
}
```

### Phase 3: Create Hatchet Adapter (Week 3)

**Goal**: Thin adapter that wraps Steps into Hatchet tasks.

```go
// pkg/adapter/hatchet/step_adapter.go
package hatchet

import (
    "context"
    hatchetsdk "github.com/hatchet-dev/hatchet/sdks/go"
    "github.com/your-org/beads-runner/pkg/workflow"
    "github.com/your-org/beads-runner/pkg/workflow/steps"
)

// StepAdapter adapts workflow.Step to hatchet.Task
type StepAdapter struct {
    step workflow.Step
    deps workflow.StepDeps
}

func NewStepAdapter(step workflow.Step, deps workflow.StepDeps) *StepAdapter {
    return &StepAdapter{step: step, deps: deps}
}

// ToHatchetTask creates a Hatchet task function from the step
func (a *StepAdapter) ToHatchetTask() func(hatchetsdk.Context, TaskInput) (interface{}, error) {
    return func(ctx hatchetsdk.Context, input TaskInput) (interface{}, error) {
        // Convert Hatchet context to standard context
        stdCtx := context.Background()

        // Build step input with parent outputs
        stepInput := workflow.StepInput{
            TaskInput:     input,
            ParentOutputs: extractParentOutputs(ctx),
        }

        // Execute the step through clean interface
        return a.step.Execute(stdCtx, a.deps, stepInput)
    }
}

// WorkflowBuilder builds Hatchet workflows from Steps
type WorkflowBuilder struct {
    client *hatchetsdk.Client
    deps   workflow.StepDeps
}

func (b *WorkflowBuilder) Build() (*hatchetsdk.Workflow, error) {
    wf := b.client.NewWorkflow("beads-task-workflow")

    // Each step is clean, small, testable
    steps := []workflow.Step{
        steps.NewEnsureServerStep(),
        steps.NewValidateStep(),
        steps.NewResolveDepsStep(),
        steps.NewTDDGuardStep(),
        steps.NewExecuteStep(),
        steps.NewSelfHealingStep(),
        steps.NewTCRStep(),
        steps.NewCaptureStep(),
        steps.NewSyncBeadsStep(),
    }

    var prevTask *hatchetsdk.Task
    for i, step := range steps {
        adapter := NewStepAdapter(step, b.deps)
        opts := []hatchetsdk.TaskOption{
            hatchetsdk.WithRetries(defaultRetries(step.Name())),
            hatchetsdk.WithExecutionTimeout(defaultTimeout(step.Name())),
        }
        if prevTask != nil {
            opts = append(opts, hatchetsdk.WithParents(prevTask))
        }
        prevTask = wf.NewTask(step.Name(), adapter.ToHatchetTask(), opts...)
    }

    return wf, nil
}
```

### Phase 4: Add Observability Middleware (Week 4)

**Goal**: Cross-cutting observability without code duplication.

```go
// pkg/adapter/hatchet/observability.go
package hatchet

import (
    "context"
    "time"
    "github.com/your-org/beads-runner/pkg/workflow"
)

// ObservableStep wraps a step with logging and metrics
type ObservableStep struct {
    inner   workflow.Step
    logger  Logger
    metrics MetricsRecorder
}

func WithObservability(step workflow.Step, logger Logger, metrics MetricsRecorder) workflow.Step {
    return &ObservableStep{inner: step, logger: logger, metrics: metrics}
}

func (s *ObservableStep) Name() string {
    return s.inner.Name()
}

func (s *ObservableStep) Execute(
    ctx context.Context,
    deps workflow.StepDeps,
    input workflow.StepInput,
) (workflow.StepOutput, error) {
    start := time.Now()

    // Pre-execution logging
    s.logger.Info(ctx, fmt.Sprintf("[%s] Starting", s.Name()), map[string]any{
        "task_id":     input.TaskID,
        "workflow_id": input.WorkflowID,
        "step.name":   s.Name(),
    })

    // Execute
    output, err := s.inner.Execute(ctx, deps, input)

    // Post-execution metrics
    duration := time.Since(start)
    success := err == nil && output.Success()

    s.metrics.Record(ctx, s.Name(), duration, success)

    if success {
        s.logger.Info(ctx, fmt.Sprintf("[%s] Completed", s.Name()), map[string]any{
            "duration_ms": duration.Milliseconds(),
        })
    } else {
        s.logger.Error(ctx, fmt.Sprintf("[%s] Failed", s.Name()), err, map[string]any{
            "duration_ms": duration.Milliseconds(),
        })
    }

    return output, err
}
```

---

## Testing Strategy

### Current State

- Tests exist but test integration (require Hatchet running)
- Cannot unit test individual steps
- Mock setup is complex

### Target State

```go
// pkg/workflow/steps/ensure_server_test.go
package steps_test

import (
    "context"
    "testing"
    "github.com/your-org/beads-runner/pkg/workflow"
    "github.com/your-org/beads-runner/pkg/workflow/steps"
)

func TestEnsureServerStep_Success(t *testing.T) {
    // Arrange - simple mock setup
    mockLifecycle := &MockServerLifecycle{
        ReadyErr:  nil,
        URL:       "http://localhost:8080",
    }
    deps := workflow.StepDeps{
        ServerLifecycle: mockLifecycle,
        Logger:          &NoopLogger{},
        Metrics:         &NoopMetrics{},
    }
    input := workflow.StepInput{
        TaskInput: TaskInput{TaskID: "test-1"},
    }

    // Act
    step := steps.NewEnsureServerStep()
    output, err := step.Execute(context.Background(), deps, input)

    // Assert
    require.NoError(t, err)
    require.True(t, output.Success())
    serverOutput := output.(*steps.EnsureServerOutput)
    require.Equal(t, "http://localhost:8080", serverOutput.ServerURL)
}

func TestEnsureServerStep_LifecycleError(t *testing.T) {
    mockLifecycle := &MockServerLifecycle{
        ReadyErr: errors.New("server unhealthy"),
    }
    // ... test error path
}
```

---

## Migration Strategy

### Backwards Compatibility

1. **Keep existing functions working** during migration
2. **Feature flags** to switch between old/new implementations
3. **Parallel execution** in tests to verify identical behavior

### Incremental Delivery

| Week | Deliverable | Risk |
|------|-------------|------|
| 1 | Step interface + first step extracted | Low |
| 2 | All 9 steps extracted with tests | Medium |
| 3 | Hatchet adapter using new steps | Medium |
| 4 | Observability middleware + cleanup | Low |

### Rollback Plan

- Keep `workflow_factory.go` until migration complete
- Feature flag: `USE_EXTRACTED_STEPS=true/false`
- Revert flag if issues detected in production

---

## Metrics for Success

| Metric | Current | Target |
|--------|---------|--------|
| Largest file | 1,755 lines | < 300 lines |
| Step test coverage | ~0% (integration only) | > 80% unit |
| Time to understand step | 10+ minutes | < 2 minutes |
| Time to add new step | 2+ hours | 30 minutes |
| Dependencies per step | Implicit (runner) | Explicit (ports) |

---

## Summary

The current Hatchet integration works but violates key software design principles. The recommended refactoring to **Hexagonal Architecture with Extracted Steps** will:

1. **Increase cohesion** - Each step in its own file (~100 lines)
2. **Reduce coupling** - Ports/adapters isolate infrastructure
3. **Enable testing** - Unit tests without Hatchet running
4. **Improve AI-friendliness** - Predictable structure, easy discovery
5. **Support continuous delivery** - Small, independently deployable changes

**Estimated effort**: 4 weeks
**Risk**: Medium (behavioral changes possible during extraction)
**ROI**: High (enables faster development, better observability, easier onboarding)

---

## Appendix: File-by-File Analysis

### workflow_factory.go (CRITICAL - Needs Refactoring)

**Lines**: 1,755
**Responsibilities**: Too many
- Workflow input/output types (57-247)
- StepContext definition (255-272)
- HatchetWorkflowFactory struct (305-313)
- Child workflow (fix-attempt) (354-479)
- Task config mapping (480-512)
- Observability helpers (518-590)
- **9 step implementations inline** (611-1647)
- Workflow execution (1654-1754)

**Recommendation**: Split into 10+ files

### hatchet_integration.go (MEDIUM - Acceptable)

**Lines**: 410
**Responsibilities**: Acceptable mix
- HatchetRunner struct and lifecycle
- Health checks
- Worker management

**Recommendation**: Consider extracting health checks to separate file

### hatchet_beads_bridge.go (GOOD ✓)

**Lines**: 125
**Responsibilities**: Single (adapter pattern)
- Dispatch tasks to Hatchet
- Sync results back to Beads

**Recommendation**: Keep as-is, good example of clean design

### types.go (MEDIUM - Consider Splitting)

**Lines**: 573
**Responsibilities**: Type definitions
- State machine
- Domain types
- Config types
- Verification types

**Recommendation**: Split into domain types and config types

### workflow_step_helpers.go (DELETE - Dead Code)

**Lines**: 232
**Responsibilities**: Stub implementations
- Not connected to actual workflow
- Confusing for AI and humans

**Recommendation**: Delete after extracting real logic to new step files
