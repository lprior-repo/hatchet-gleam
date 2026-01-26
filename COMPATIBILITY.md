# Compatibility Issues with Gleam 1.14.0

The current codebase was written for Gleam 0.x but the environment has Gleam 1.14.0 installed. There are significant API incompatibilities:

## Major API Changes

### gleam/json
- `json.from_dynamic()` function removed - no longer exists
- JSON parsing API completely changed
- Decoding now uses `gleam/dynamic/decode` module instead of inline decoders

### gleam/dynamic
- `dynamic.decode2`, `dynamic.decode4`, etc. removed - now use `decode.run(decoder, dynamic)`
- `dynamic.field()` removed - now use `decode.field()`
- `dynamic.optional()` removed - now use `decode.optional()`
- `dynamic.from()` removed

### gleam/http
- `request.Method` moved to `http.Method`

### gleam_erlang, gleam_http, gleam_otp
- These packages need to be updated to compatible versions for Gleam 1.14.0
- Older versions use deprecated APIs

## Current Status

Test files have been written for all modules:
- test/hatchet/client_test.gleam
- test/hatchet/workflow_test.gleam  
- test/hatchet/task_test.gleam
- test/hatchet/standalone_test.gleam
- test/hatchet/internal/json_test.gleam

To run these tests, the code needs to be migrated to Gleam 1.x APIs, which requires:
1. Updating all encode/decode functions in internal/json.gleam
2. Updating all imports and type references
3. Rewriting the dynamic-to-json conversion logic

## Recommended Actions

1. **Option A**: Use Gleam 0.x (recommended for this codebase)
   - The code is designed for Gleam 0.x APIs
   - Install an older version of Gleam that matches the dependencies

2. **Option B**: Full migration to Gleam 1.x
   - Rewrite internal/json.gleam to use new decode API
   - Implement custom Dynamic->Json conversion helper
   - Update all imports and type references
   - Test thoroughly with Gleam 1.14.0

## Test Coverage

The test files cover:
- Client creation and configuration
- Workflow builder DSL (tasks, dependencies, retries, timeouts, etc.)
- Task helpers and context utilities
- Standalone tasks
- JSON encoding/decoding
- All type constructors and accessors

Once the compatibility issues are resolved, these tests can be run with:
```bash
gleam test
```
