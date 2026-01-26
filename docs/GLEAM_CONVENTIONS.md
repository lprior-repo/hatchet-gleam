# Gleam Coding Conventions for Hatchet SDK

## The 7 Commandments of Gleam

1. **Immutability** - All data is immutable. Use transformation functions, not mutations.
2. **No Nulls** - Use `Option(a)` with `Some(value)` and `None` instead of null.
3. **Pipelines** - Use the `|>` pipe operator for data transformation chains.
4. **Exhaustive Matching** - All pattern matches must handle every case. Use `_` only when truly appropriate.
5. **Labeled Arguments** - Use labeled arguments for clarity: `fn create(name name: String, age age: Int)`.
6. **Type Safety** - Leverage the type system. Opaque types for encapsulation. Result types for errors.
7. **Formatting** - Run `gleam format` before committing. Code style is consistent across all Gleam projects.

## Error Handling Patterns

### Use Result Types
```gleam
pub fn parse(input: String) -> Result(Data, ParseError) {
  case validate(input) {
    True -> Ok(Data(input))
    False -> Error(InvalidInput)
  }
}
```

### Monadic Composition with `use`
```gleam
pub fn process(input: String) -> Result(Output, Error) {
  use data <- result.try(parse(input))
  use validated <- result.try(validate(data))
  use transformed <- result.try(transform(validated))
  Ok(transformed)
}
```

### Error Context with Mapping
```gleam
pub fn load_file(path: String) -> Result(String, AppError) {
  simplifile.read(path)
  |> result.map_error(fn(e) { FileError(path, e) })
}
```

## Builder Pattern

```gleam
pub fn new(name: String) -> Builder {
  Builder(name: name, options: default_options())
}

pub fn with_timeout(builder: Builder, timeout: Int) -> Builder {
  Builder(..builder, timeout: Some(timeout))
}

pub fn with_retries(builder: Builder, retries: Int) -> Builder {
  Builder(..builder, retries: retries)
}

// Usage with pipelines
let config = new("my-workflow")
  |> with_timeout(5000)
  |> with_retries(3)
```

## Type Definitions

### Opaque Types for Encapsulation
```gleam
pub opaque type Client {
  Client(host: String, port: Int, token: String)
}

// Factory function is the only way to create
pub fn new(host: String, token: String) -> Client {
  Client(host: host, port: 7070, token: token)
}

// Accessor functions control what's exposed
pub fn get_host(client: Client) -> String {
  client.host
}
```

### Discriminated Unions for Variants
```gleam
pub type Status {
  Pending
  Running
  Succeeded
  Failed(error: String)
  Cancelled
}

// Exhaustive matching required
pub fn is_terminal(status: Status) -> Bool {
  case status {
    Pending | Running -> False
    Succeeded | Failed(_) | Cancelled -> True
  }
}
```

## Dependency Injection Pattern

```gleam
// Define function types for dependencies
pub type FileReader = fn(String) -> Result(String, String)
pub type FileWriter = fn(String, String) -> Result(Nil, String)

// Pure function that accepts dependencies
pub fn process(
  path: String,
  read: FileReader,
  write: FileWriter,
) -> Result(Nil, String) {
  use content <- result.try(read(path))
  let transformed = transform(content)
  write(path, transformed)
}

// Production adapter
pub fn simplifile_reader() -> FileReader {
  fn(path) {
    simplifile.read(path)
    |> result.map_error(fn(_) { "Failed to read: " <> path })
  }
}

// Test mock
pub fn mock_reader(content: String) -> FileReader {
  fn(_path) { Ok(content) }
}
```

## JSON Encoding/Decoding

### Encoding
```gleam
import gleam/json

pub fn encode_task(task: Task) -> String {
  json.object([
    #("name", json.string(task.name)),
    #("retries", json.int(task.retries)),
    #("timeout", case task.timeout {
      Some(t) -> json.int(t)
      None -> json.null()
    }),
  ])
  |> json.to_string()
}
```

### Decoding with Dynamic
```gleam
import gleam/dynamic/decode

pub fn decode_task(data: Dynamic) -> Result(Task, DecodeError) {
  let decoder = {
    use name <- decode.field("name", decode.string)
    use retries <- decode.field("retries", decode.int)
    use timeout <- decode.optional_field("timeout", decode.int)
    decode.success(Task(name: name, retries: retries, timeout: timeout))
  }
  decode.run(data, decoder)
}
```

## Testing Patterns

### Contract Documentation
```gleam
/// Contract: Task creation
/// - GIVEN a valid task name
/// - WHEN creating a task
/// - THEN it should have default retries of 0
pub fn task_default_retries_test() {
  let task = task.new("my-task", handler)
  task.retries |> should.equal(0)
}
```

### Factory Functions for Test Data
```gleam
// test/test_helpers.gleam
pub fn sample_task() -> Task {
  Task(
    name: "test-task",
    handler: fn(_) { Ok(dynamic.from(Nil)) },
    retries: 0,
    timeout: None,
  )
}

pub fn sample_workflow() -> Workflow {
  workflow.new("test-workflow")
  |> workflow.task("step-1", sample_handler())
}
```

## File Organization

```
src/
├── hatchet.gleam           # Public API facade (re-exports)
├── hatchet/
│   ├── types.gleam         # Core type definitions
│   ├── client.gleam        # Client creation and config
│   ├── workflow.gleam      # Workflow builder
│   ├── task.gleam          # Task helpers
│   ├── run.gleam           # Execution functions
│   ├── events.gleam        # Event publishing
│   └── internal/
│       ├── protocol.gleam  # Protocol messages
│       └── json.gleam      # JSON codecs
test/
├── hatchet/
│   ├── client_test.gleam
│   ├── workflow_test.gleam
│   └── ...
└── test_helpers.gleam      # Shared test utilities
```

## Common Libraries

| Package | Purpose |
|---------|---------|
| `gleam_stdlib` | Core types (Dict, List, Option, Result) |
| `gleam_json` | JSON encoding/decoding |
| `gleam_http` | HTTP types |
| `gleam_httpc` | HTTP client |
| `gleam_otp` | OTP/actor model |
| `gleam_erlang` | Erlang FFI (process, timer) |
| `simplifile` | File I/O |
| `gleeunit` | Testing framework |

## FFI (Foreign Function Interface)

```gleam
// Centralized FFI module
// src/hatchet/internal/ffi.gleam

@external(erlang, "timer", "sleep")
pub fn sleep(milliseconds: Int) -> Nil

@external(erlang, "erlang", "system_time")
fn system_time_impl(unit: Atom) -> Int

pub fn current_time_ms() -> Int {
  system_time_impl(atom.create_from_string("millisecond"))
}
```

## Resources

- [Gleam Documentation](https://gleam.run/documentation/)
- [Gleam Standard Library](https://hexdocs.pm/gleam_stdlib/)
- [Gleam Tour](https://tour.gleam.run/)
- [Gleam Discord](https://discord.gg/gleam)
