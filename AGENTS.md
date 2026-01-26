# Agent Instructions

This project uses **bd** (beads) for issue tracking. The codebase is a Gleam SDK for Hatchet distributed task orchestration.

## Project Overview

**Status:** NOT PRODUCTION READY - See `SDK_VERIFICATION_REPORT.md`

**Critical Issues:**
- Worker implementation is stubbed
- No gRPC implementation (uses REST only)
- sleep_ms() doesn't actually sleep

**Reference Documentation:**
- `docs/HATCHET.md` - Hatchet concepts and architecture
- `docs/HATCHET_DESIGN_REVIEW.md` - Hexagonal architecture patterns
- `docs/GLEAM_CONVENTIONS.md` - Coding conventions

---

## Working with Beads

### Finding Work

```bash
bd ready              # Show issues ready to work on (no blockers)
bd blocked            # Show issues waiting on dependencies
bd list               # Show all issues
bd show <id>          # View full issue details with acceptance criteria
```

### Grabbing a Bead

```bash
# 1. Find available work
bd ready

# 2. View the bead's acceptance criteria
bd show hatchet-port-xyz

# 3. Claim it
bd update hatchet-port-xyz --status in_progress --claim

# 4. The bead now shows you as owner
```

### Working a Bead

**Before writing code, understand the acceptance criteria:**

```bash
bd show hatchet-port-xyz
```

Each bead has:
- **Invariants** - What MUST always be true
- **Variants** - Edge cases and scenarios to handle
- **Happy Path** - The expected flow
- **Validation** - How to prove it works
- **Definition of Done** - Checklist of requirements

### Validating Your Work

**You MUST verify ALL acceptance criteria before closing:**

1. **Run tests:** `gleam test`
2. **Check formatting:** `gleam format --check src test`
3. **Verify no warnings:** `gleam build 2>&1 | grep -i warning`
4. **Complete the Definition of Done checklist**

### Completing a Bead

```bash
# 1. Commit your changes
git add -A
git commit -m "feat: Implement X (hatchet-port-xyz)

- Implemented Y
- Added tests for Z
- Verified against acceptance criteria

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"

# 2. Close the bead with summary
bd close hatchet-port-xyz --reason "Implemented X. All acceptance criteria met. Tests pass."

# 3. Sync and push
bd sync
git push
```

---

## The 7 Commandments of Gleam

These are **NON-NEGOTIABLE**. All code MUST follow these principles.

### 1. Immutability
All data is immutable. Never mutate - always transform.

```gleam
// WRONG - trying to mutate
let list = [1, 2, 3]
list.push(4)  // This doesn't exist in Gleam

// RIGHT - create new value
let list = [1, 2, 3]
let new_list = list.append([4])
```

### 2. No Nulls
Use `Option(a)` with `Some(value)` and `None`. Never null.

```gleam
// WRONG - no null in Gleam
let value = null

// RIGHT - use Option
let value: Option(String) = None
let value: Option(String) = Some("hello")
```

### 3. Pipelines
Use `|>` for data transformation chains. Data flows left to right.

```gleam
// WRONG - nested calls
let result = transform(validate(parse(input)))

// RIGHT - pipeline
let result = input
  |> parse()
  |> validate()
  |> transform()
```

### 4. Exhaustive Matching
All pattern matches MUST handle every case. The compiler enforces this.

```gleam
// This won't compile - missing cases
case status {
  Pending -> "waiting"
  Running -> "active"
  // Missing: Succeeded, Failed, Cancelled
}

// RIGHT - handle all cases
case status {
  Pending -> "waiting"
  Running -> "active"
  Succeeded -> "done"
  Failed(err) -> "error: " <> err
  Cancelled -> "cancelled"
}
```

### 5. Labeled Arguments
Use labeled arguments for clarity, especially with multiple parameters of the same type.

```gleam
// WRONG - unclear what arguments mean
fn create(String, String, Int) -> User

// RIGHT - labeled and clear
fn create(name name: String, email email: String, age age: Int) -> User

// Called as:
create(name: "Alice", email: "alice@example.com", age: 30)
```

### 6. Type Safety
Leverage the type system. Use opaque types for encapsulation, Result for errors.

```gleam
// Opaque type - internals hidden
pub opaque type Client {
  Client(host: String, port: Int, token: String)
}

// Only way to create is through factory
pub fn new(host: String, token: String) -> Result(Client, String) {
  case validate_token(token) {
    True -> Ok(Client(host: host, port: 7070, token: token))
    False -> Error("Invalid token")
  }
}
```

### 7. Formatting
Run `gleam format` before every commit. No exceptions.

```bash
gleam format src test
```

---

## Gleam Patterns for This Project

### Result Composition with `use`

```gleam
pub fn process(input: String) -> Result(Output, Error) {
  use parsed <- result.try(parse(input))
  use validated <- result.try(validate(parsed))
  use transformed <- result.try(transform(validated))
  Ok(transformed)
}
```

### Builder Pattern

```gleam
pub fn new(name: String) -> Workflow {
  Workflow(name: name, tasks: [], cron: None, events: [])
}

pub fn with_cron(workflow: Workflow, cron: String) -> Workflow {
  Workflow(..workflow, cron: Some(cron))
}

pub fn task(workflow: Workflow, name: String, handler: Handler) -> Workflow {
  let task = TaskDef(name: name, handler: handler, parents: [])
  Workflow(..workflow, tasks: list.append(workflow.tasks, [task]))
}

// Usage
let wf = new("my-workflow")
  |> with_cron("0 * * * *")
  |> task("step-1", handler1)
  |> task("step-2", handler2)
```

### Error Handling with Context

```gleam
pub fn load_config(path: String) -> Result(Config, AppError) {
  simplifile.read(path)
  |> result.map_error(fn(e) {
    ConfigError(path: path, reason: "Failed to read: " <> string.inspect(e))
  })
  |> result.try(fn(content) {
    parse_config(content)
    |> result.map_error(fn(e) {
      ConfigError(path: path, reason: "Failed to parse: " <> e)
    })
  })
}
```

### Dependency Injection for Testing

```gleam
// Define function types for dependencies
pub type FileReader = fn(String) -> Result(String, String)
pub type HttpClient = fn(Request) -> Result(Response, String)

// Pure function accepts dependencies
pub fn process(
  path: String,
  read_file: FileReader,
  http: HttpClient,
) -> Result(Output, String) {
  use content <- result.try(read_file(path))
  use response <- result.try(http(build_request(content)))
  Ok(parse_response(response))
}

// Production: use real implementations
let result = process(path, simplifile.read, httpc.send)

// Test: use mocks
let result = process(path, mock_reader, mock_http)
```

### JSON Encoding

```gleam
import gleam/json

pub fn encode_task(task: TaskDef) -> String {
  json.object([
    #("name", json.string(task.name)),
    #("retries", json.int(task.retries)),
    #("parents", json.array(task.parents, json.string)),
    #("timeout", case task.timeout {
      Some(t) -> json.int(t)
      None -> json.null()
    }),
  ])
  |> json.to_string()
}
```

### Test Patterns

```gleam
/// Contract: Workflow creation
/// - GIVEN a workflow name
/// - WHEN creating a new workflow
/// - THEN it should have empty task list
pub fn workflow_new_has_empty_tasks_test() {
  let wf = workflow.new("test")
  wf.tasks |> should.equal([])
}

/// Contract: Task addition
/// - GIVEN an existing workflow
/// - WHEN adding a task
/// - THEN the task should be in the workflow's task list
pub fn workflow_task_adds_to_list_test() {
  let wf = workflow.new("test")
    |> workflow.task("step-1", sample_handler())

  wf.tasks |> list.length() |> should.equal(1)
}
```

---

## Current Beads

Run `bd ready` to see available work. Priority order:

1. **P1: hatchet-port-csv** - Fix sleep_ms (quick win)
2. **P1: hatchet-port-8uf** - Implement gRPC client
3. **P1: hatchet-port-4dg** - Implement worker (blocked by gRPC)

---

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed):
   ```bash
   gleam format src test
   gleam test
   gleam build
   ```
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds

---

## Reference Locations

| Resource | Path |
|----------|------|
| Python SDK | `/tmp/hatchet-python/hatchet_sdk/` |
| Go SDK | `/tmp/hatchet/pkg/` |
| Intent CLI patterns | `~/src/intent-cli/src/intent/` |
| Hatchet docs | `docs/HATCHET.md` |
| Gleam conventions | `docs/GLEAM_CONVENTIONS.md` |
| Verification report | `SDK_VERIFICATION_REPORT.md` |
