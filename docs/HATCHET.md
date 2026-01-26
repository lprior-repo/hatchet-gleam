# Hatchet: Durable DAG-Based Workflow Orchestrator

Hatchet is an MIT-licensed distributed workflow engine that powers beads-runner's task orchestration.

## Why Hatchet?

| Need | Solution |
|------|----------|
| **Durable execution** | Jobs survive crashes, restarts, network failures |
| **DAG orchestration** | Tasks run in dependency order with parallelization |
| **Automatic retries** | Exponential backoff with configurable limits |
| **Distributed workers** | Scale horizontally across machines |
| **Event streaming** | Real-time progress via WebSocket/SSE |
| **MIT licensed** | Use anywhere, modify freely |

## Core concepts

### Workflows

A workflow is a DAG (Directed Acyclic Graph) of steps:

```go
workflow.DefineWorkflow("task-execution").
    AddStep("check-deps", checkDependencies).
    AddStep("process", processTask).AddParents("check-deps").
    AddStep("verify", verifyChanges).AddParents("process").
    AddStep("commit", commitChanges).AddParents("verify")
```

### Steps

Each step is an atomic unit of work:

```go
func processTask(ctx context.Context, input *TaskInput) (*TaskOutput, error) {
    // Execute task logic
    return &TaskOutput{Success: true}, nil
}
```

### Workers

Workers pull jobs from the queue and execute steps:

```go
worker := client.Worker("beads-worker")
worker.RegisterWorkflow(taskExecutionWorkflow)
worker.Start()
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Hatchet Engine                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │  Scheduler  │  │  Job Queue  │  │   Events    │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
└─────────────────────────────────────────────────────────────────┘
         │                  │                  │
         ▼                  ▼                  ▼
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│  Worker 1   │    │  Worker 2   │    │  Worker N   │
└─────────────┘    └─────────────┘    └─────────────┘
```

**Components:**
- **Engine** — Orchestration brain (Go binary)
- **PostgreSQL** — Job state persistence
- **RabbitMQ** — Job queue messaging
- **Workers** — Job executors (your code)
- **Dashboard** — Web UI for monitoring

## Setup

### Docker Compose (recommended)

```yaml
# docker-compose.yml
services:
  postgres:
    image: postgres:15
    environment:
      POSTGRES_DB: hatchet
      POSTGRES_USER: hatchet
      POSTGRES_PASSWORD: hatchet
    ports:
      - "5435:5432"

  rabbitmq:
    image: rabbitmq:3-management
    ports:
      - "5672:5672"
      - "15672:15672"

  hatchet-engine:
    image: ghcr.io/hatchet-dev/hatchet/hatchet-engine:latest
    environment:
      DATABASE_URL: postgres://hatchet:hatchet@postgres:5432/hatchet
      RABBITMQ_URL: amqp://guest:guest@rabbitmq:5672
    ports:
      - "7077:7077"  # gRPC
    depends_on:
      - postgres
      - rabbitmq

  hatchet-dashboard:
    image: ghcr.io/hatchet-dev/hatchet/hatchet-dashboard:latest
    ports:
      - "8080:8080"
    depends_on:
      - hatchet-engine
```

```bash
docker compose up -d
```

### Get API token

```bash
# From dashboard or CLI
docker exec hatchet-engine hatchet token create --name beads-runner
```

### Configure client

```bash
export HATCHET_CLIENT_TOKEN="your-token"
export HATCHET_CLIENT_TLS_STRATEGY="none"  # For local dev
```

## Integration with beads-runner

### Workflow registration

```go
// hatchet_integration.go
func (h *HatchetIntegration) Initialize() error {
    // Health check with retries
    if err := h.waitForHatchet(); err != nil {
        return err
    }

    // Create rate limits
    h.client.RateLimits().Upsert("opencode-sessions", 3)

    // Register workflow
    workflow := h.client.DefineWorkflow("beads-task-execution")
    workflow.AddStep("process-task", h.processTask).
        WithRateLimits("opencode-sessions")

    return h.worker.Start()
}
```

### Task execution flow

```
1. Beads provides ready tasks
2. beads-runner submits to Hatchet
3. Hatchet schedules based on DAG
4. Worker executes via OpenCode
5. Quality gates verify results
6. Hatchet handles retries on failure
7. Success: commit and close task
```

## Reliability features

### Automatic retries

```go
workflow.AddStep("risky-operation", handler).
    WithRetries(3).
    WithBackoff(time.Second, 30*time.Second, 2.0)
```

### Rate limiting

```go
// Limit concurrent OpenCode sessions
workflow.AddStep("ai-task", handler).
    WithRateLimits("opencode-sessions")
```

### Timeouts

```go
workflow.AddStep("long-task", handler).
    WithTimeout(10 * time.Minute)
```

### Event streaming

```go
// Real-time progress updates
client.Events().Subscribe(workflowRunID, func(event Event) {
    log.Printf("Step %s: %s", event.StepName, event.Status)
})
```

## Dashboard

Access at `http://localhost:8080`:

- **Workflow runs** — See all executions
- **Step status** — Track progress through DAG
- **Logs** — View step outputs
- **Metrics** — Success rates, durations

## Comparison with alternatives

| Feature | Hatchet | Temporal | Airflow |
|---------|---------|----------|---------|
| License | MIT | MIT | Apache 2.0 |
| Language | Go | Go | Python |
| DAG support | Native | Workflows | Native |
| Retries | Built-in | Built-in | Built-in |
| Self-hosted | Easy | Medium | Easy |
| Learning curve | Low | High | Medium |
| Resource usage | Low | Medium | High |

## Troubleshooting

### Connection refused

```bash
# Check engine is running
docker ps | grep hatchet-engine

# Check gRPC port
nc -zv localhost 7077
```

### Rate limit errors

```bash
# Verify rate limit exists
psql -h localhost -p 5435 -U hatchet -d hatchet \
  -c "SELECT * FROM rate_limits WHERE key = 'opencode-sessions';"
```

### TLS mismatch

```bash
# For local dev, disable TLS
export HATCHET_CLIENT_TLS_STRATEGY="none"
```

## Resources

- [Hatchet Documentation](https://docs.hatchet.run)
- [Hatchet GitHub](https://github.com/hatchet-dev/hatchet)
- [Go SDK Reference](https://pkg.go.dev/github.com/hatchet-dev/hatchet/pkg/client)
- [beads-runner Integration](../hatchet_integration.go)
