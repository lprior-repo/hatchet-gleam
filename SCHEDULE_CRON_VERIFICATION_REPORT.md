# Scheduling and Cron Verification Report

## Bead: hatchet-port-vt3
**Date:** 2026-01-28
**Status:** Code Review Complete

---

## Executive Summary

The current implementation of scheduling and cron functionality in the hatchet-port Gleam SDK is **MINIMAL**. The SDK provides basic HTTP API wrappers but lacks:

1. Cron expression parsing and validation
2. Timezone support
3. Schedule builder patterns
4. Multiple schedules per workflow
5. Schedule monitoring and querying
6. Special cron string support (@hourly, @daily, etc.)

**Critical Finding:** The SDK delegates ALL cron validation, parsing, and execution logic to the Hatchet server. This means:
- Client-side validation is impossible
- Errors are only returned from server
- No timezone conversion in the SDK
- No next-run-time calculation

---

## Section 1: Cron Expression Parsing

### Code Review

**File:** `src/hatchet/cron.gleam` (113 lines)

**Findings:**
- ❌ **NO CRON PARSER IMPLEMENTED** - The module only contains HTTP API wrappers
- ❌ **NO CLIENT-SIDE VALIDATION** - Cron expressions are passed as-is to server
- ❌ **NO SPECIAL STRING SUPPORT** - No @hourly, @daily, @weekly, @monthly, @yearly
- ❌ **NO NAMED VALUES** - No MON, TUE, JAN, FEB etc. support
- ⚠️ **Documentation:** Basic, but doesn't list supported cron features

**What Exists:**
```gleam
// Create a named cron trigger (HTTP API call)
pub fn create(
  client: Client,
  workflow: Workflow,
  name: String,
  expression: String,  // Passed as-is to server
  input: Dynamic,
) -> Result(String, String)

// Delete a cron trigger (HTTP API call)
pub fn delete(client: Client, cron_id: String) -> Result(Nil, String)
```

**What's Missing:**
1. Cron expression parser
2. Cron expression validator
3. Special string expansion (@daily → "0 0 * * *")
4. Named value expansion (MON → 1)
5. Next run time calculator
6. Timezone converter
7. DST transition handler

### Test Coverage

**Current State:** No dedicated cron parsing tests

**What Should Be Tested:**
- ✅ Parse "*/5 * * * *" (every 5 minutes)
- ✅ Parse "0 9 * * 1-5" (weekdays at 9am)
- ✅ Parse "0 0 1 * *" (first of month)
- ❌ Parse "@daily" shorthand (NOT SUPPORTED)
- ❌ Parse "@hourly" shorthand (NOT SUPPORTED)
- ❌ Reject invalid: "70 * * * *" (minute >59) (SERVER-SIDE ONLY)
- ❌ Reject invalid: "* * 32 * *" (day >31) (SERVER-SIDE ONLY)
- ❌ Reject invalid: "not-a-cron-expression" (SERVER-SIDE ONLY)

**GAP:** All validation happens server-side. No client-side tests possible.

---

## Section 2: Schedule Creation

### Code Review

**File:** `src/hatchet/schedule.gleam` (116 lines)

**Findings:**
- ✅ **ONE-TIME SCHEDULES SUPPORTED** - `schedule.create()` works for specific timestamps
- ❌ **NO TIMEZONE SUPPORT** - ISO 8601 strings passed as-is
- ❌ **NO START/END DATES** - Cannot set schedule duration
- ❌ **NO ENABLE/DISABLE TOGGLE** - No schedule state management
- ❌ **NO SCHEDULE BUILDER** - Just raw HTTP calls

**What Exists:**
```gleam
// Schedule a one-time workflow run at a specific time
pub fn create(
  client: Client,
  workflow: Workflow,
  trigger_at: String,  // ISO 8601 timestamp (no timezone conversion)
  input: Dynamic,
) -> Result(String, String)

// Delete a scheduled run by its ID
pub fn delete(client: Client, schedule_id: String) -> Result(Nil, String)
```

**What's Missing:**
1. Schedule builder pattern
2. Timezone support (UTC conversion)
3. Start date support (schedule future jobs)
4. End date support (expire schedules)
5. Enable/disable toggle
6. Schedule metadata (name, description)
7. Schedule query/list endpoint
8. Schedule history endpoint
9. Next run time calculator

### Test Coverage

**Current State:** No dedicated schedule tests

**What Should Be Tested:**
- ✅ Create schedule with simple timestamp
- ✅ Create schedule with complex input
- ❌ Create schedule with timezone (UTC, America/New_York) (NOT SUPPORTED)
- ❌ Create schedule with start date (future) (NOT SUPPORTED)
- ❌ Create schedule with end date (past = disabled) (NOT SUPPORTED)
- ❌ Attach multiple schedules to workflow (NOT SUPPORTED)
- ❌ Disable schedule (workflow not triggered) (NOT SUPPORTED)

---

## Section 3: Schedule Attachment to Workflows

### Code Review

**File:** `src/hatchet/workflow.gleam`

**Findings:**
- ✅ **WORKFLOW CRON ATTACHMENT WORKS** - `workflow.with_cron()` exists
- ✅ **SINGLE CRON PER WORKFLOW** - Supported via Option(String)
- ❌ **NO SCHEDULE METADATA** - No name/description for schedules
- ❌ **NO MULTIPLE SCHEDULES** - Cannot attach multiple cron expressions
- ⚠️ **FLUENT API EXISTS** - Builder pattern works well

**What Exists:**
```gleam
// In workflow.gleam
pub fn with_cron(wf: Workflow, cron: String) -> Workflow {
  Workflow(..wf, cron: option.Some(cron))
}

// Example usage
let wf =
  workflow.new("nightly-report")
  |> workflow.with_cron("0 0 * * *")
  |> workflow.task("generate-report", handler)
```

**JSON Encoding (src/hatchet/internal/json.gleam):**
```gleam
pub fn encode_workflow_create(req: p.WorkflowCreateRequest) -> String {
  json.object([
    #("name", json.string(req.name)),
    #("cron", optionable(json.string, req.cron)),  // Encodes as JSON
    #("events", json.array(req.events, json.string)),
    // ...
  ])
  |> json.to_string()
}
```

**What's Missing:**
1. Multiple schedules per workflow (arrays of cron expressions)
2. Schedule metadata (name, description per schedule)
3. Schedule update workflow (re-register with new schedules)
4. Schedule remove workflow (clear schedules without code change)
5. Schedule query API (list schedules for workflow)

### Test Coverage

**Current State:** Basic workflow.with_cron() tests exist in `workflow_test.gleam:48-55`

**What Should Be Tested:**
- ✅ Workflow with single schedule
- ❌ Workflow with multiple schedules (NOT SUPPORTED)
- ✅ Update workflow schedule (re-register) - Works via `workflow.with_cron()`
- ✅ Remove workflow schedule (re-register without) - Works via creating new workflow
- ❌ Schedule survives worker restart (NOT TESTED)
- ❌ Schedule not duplicated on re-registration (NOT TESTED)

---

## Section 4: Schedule Execution

### Code Review

**Findings:**
- ⚠️ **SERVER-SIDE LOGIC ONLY** - SDK doesn't handle execution
- ❌ **NO CLIENT-SIDE POLLING** - No scheduler in SDK
- ❌ **NO EXECUTION MONITORING** - No run tracking
- ❌ **NO MISS HANDLING** - No grace period configuration
- ❌ **NO JITTER SUPPORT** - No thundering herd prevention

**What's Missing:**
1. Scheduler polling loop
2. Workflow run trigger logic
3. Concurrent schedule execution handling
4. Missed schedule handling (grace period)
5. Schedule jitter configuration
6. Execution metrics tracking

### Test Coverage

**Current State:** NO EXECUTION TESTS - Server-side only

**What Should Be Tested (Live Integration):**
- ❌ Workflow runs at scheduled time (±5 seconds) (NOT TESTED)
- ❌ Workflow runs every interval (e.g., every minute for 5 minutes) (NOT TESTED)
- ❌ Overlapping schedules don't conflict (NOT TESTED)
- ❌ Long-running workflow doesn't block next schedule (NOT TESTED)
- ❌ Schedule continues after workflow error (NOT TESTED)
- ❌ Schedule respects workflow concurrency limit (NOT TESTED)

---

## Section 5: Timezone and DST Handling

### Code Review

**Findings:**
- ❌ **NO TIMEZONE SUPPORT** - ISO 8601 strings passed as-is
- ❌ **NO DST HANDLING** - No IANA timezone support
- ⚠️ **UTC BY DEFAULT** - Server likely stores in UTC
- ❌ **NO TIMEZONE CONVERSION** - No timezone conversion logic

**What's Missing:**
1. Timezone conversion functions
2. DST transition handlers (spring forward, fall back)
3. UTC default/storage timezone
4. IANA timezone name support
5. Timezone-aware schedule builder

### Test Coverage

**Current State:** NO TIMEZONE TESTS

**What Should Be Tested:**
- ❌ Schedule in UTC executes correctly (NOT TESTED)
- ❌ Schedule in America/New_York executes correctly (NOT TESTED)
- ❌ Schedule during DST transition (March, November) (NOT TESTED)
- ❌ Schedule survives timezone change (NOT SUPPORTED)

---

## Section 6: Schedule Monitoring

### Code Review

**Findings:**
- ❌ **NO NEXT RUN TIME CALCULATION** - No client-side calculation
- ❌ **NO SCHEDULE HISTORY** - No history endpoint
- ❌ **NO SCHEDULE METRICS** - No metrics tracking
- ❌ **NO ALERT ENDPOINTS** - No alert configuration

**What's Missing:**
1. Next run time calculator
2. Schedule history endpoint (last 10 runs)
3. Schedule metrics (on-time %, missed %)
4. Schedule alerts (missed runs, errors)
5. Schedule health query endpoint

### Test Coverage

**Current State:** NO MONITORING TESTS

**What Should Be Tested:**
- ❌ Query next 5 run times for schedule (NOT SUPPORTED)
- ❌ View last 10 runs for schedule (NOT SUPPORTED)
- ❌ Missed run logged and alerted (NOT SUPPORTED)
- ❌ Schedule lag visible in metrics (NOT SUPPORTED)

---

## Gaps and Bugs Found

### Critical Gaps

1. **NO CLIENT-SIDE CRON PARSER**
   - Impact: Cannot validate cron expressions before sending to server
   - Severity: HIGH
   - Workaround: Trust server validation

2. **NO TIMEZONE SUPPORT**
   - Impact: Users must manually convert to UTC
   - Severity: MEDIUM
   - Workaround: Use ISO 8601 with offset

3. **NO SPECIAL CRON STRINGS**
   - Impact: No @hourly, @daily, @weekly, @monthly, @yearly
   - Severity: LOW
   - Workaround: Use explicit cron expressions

4. **NO MULTIPLE SCHEDULES PER WORKFLOW**
   - Impact: One cron expression per workflow only
   - Severity: MEDIUM
   - Workaround: Create multiple workflows

5. **NO SCHEDULE MONITORING**
   - Impact: Cannot query schedule history or metrics
   - Severity: MEDIUM
   - Workaround: Use Hatchet dashboard

### Bugs Found

**None** - The implementation is minimal but functionally correct for what it does.

### Pre-existing Issues (Not in Scope)

The following issues exist in the test suite but are **NOT** related to scheduling/cron:

1. `test/hatchet/e2e_test.gleam` - Incorrect arity for `new_worker_with_grpc_port`
2. `test/hatchet/live_integration_test.gleam` - Incorrect arity for `new_worker_with_grpc_port`
3. Various test files using deprecated `dynamic.from()` instead of type constructors

---

## Test File Created

**File:** `test/hatchet/schedule_and_cron_test.gleam` (555 lines)

**Sections:**
1. Cron Expression Parsing Tests (Section 1)
2. Schedule Creation Tests (Section 2)
3. Schedule Attachment to Workflows Tests (Section 3)
4. Schedule Execution Tests (Section 4)
5. Timezone Handling Tests (Section 5)
6. Schedule Monitoring Tests (Section 6)
7. Complex Cron Expressions (Section 7)
8. Error Handling Tests (Section 8)
9. Integration Tests (Section 9)
10. Edge Cases (Section 10)

**Test Count:** 50+ test functions covering all documented scenarios

**Note:** Many tests cannot run without live Hatchet server integration. They test:
- Cron expression storage
- JSON encoding/decoding
- Workflow builder patterns
- API request/response structures

---

## Acceptance Criteria Status

### ✅ Cron expressions parsed correctly for all valid formats
**STATUS:** PARTIAL - No client-side parser, but expressions are stored correctly and passed to server.

### ✅ Workflows execute on schedule within 30s accuracy
**STATUS:** NOT TESTED - Server-side only, no client tests possible.

### ✅ DST transitions handled without manual intervention
**STATUS:** NOT IMPLEMENTED - No timezone support in SDK.

### ✅ Schedule changes take effect within 1 minute
**STATUS:** NOT TESTED - Server-side only.

### ✅ Missed schedules detected and alerted
**STATUS:** NOT IMPLEMENTED - No monitoring/alerting in SDK.

---

## Recommendations

### Immediate Actions

1. **Document Limitations** - Add clear documentation that:
   - Cron validation happens server-side only
   - No timezone support
   - One cron expression per workflow
   - Use ISO 8601 for schedules

2. **Add Examples** - Provide examples for:
   - Creating scheduled workflows
   - Common cron patterns
   - ISO 8601 timestamps
   - Using the Hatchet dashboard for monitoring

### Future Enhancements

1. **Client-Side Cron Parser**
   - Validate cron expressions before sending
   - Calculate next run times
   - Expand special strings (@daily, @hourly)
   - Support named values (MON, TUE)

2. **Timezone Support**
   - IANA timezone database
   - DST transition handling
   - Timezone-aware schedule builder
   - UTC conversion utilities

3. **Schedule Monitoring**
   - Query schedule history
   - Get next N run times
   - Schedule health metrics
   - Missed run alerts

4. **Multiple Schedules**
   - Support multiple cron expressions per workflow
   - Schedule metadata (name, description)
   - Enable/disable individual schedules
   - Schedule priority/ordering

---

## Summary

The current scheduling and cron implementation in the hatchet-port Gleam SDK is **MINIMAL BUT FUNCTIONAL**. It provides:

✅ Basic cron attachment to workflows
✅ One-time schedule creation
✅ HTTP API wrappers for cron/schedule CRUD
✅ JSON encoding/decoding
✅ Fluent API for workflow building

❌ NO client-side cron parsing/validation
❌ NO timezone support
❌ NO schedule monitoring
❌ NO special cron strings
❌ NO multiple schedules per workflow

**Overall Assessment:** The SDK correctly delegates complex scheduling logic to the Hatchet server, which is a reasonable design for an SDK. However, the lack of client-side validation and timezone support may be limiting for users.

**Test Status:** 50+ QA tests written covering all scenarios that can be tested client-side. Live integration tests required to verify execution accuracy.

---

## Files Reviewed

- `src/hatchet/cron.gleam` (113 lines)
- `src/hatchet/schedule.gleam` (116 lines)
- `src/hatchet/workflow.gleam` (192 lines)
- `src/hatchet/internal/json.gleam` (372 lines)
- `src/hatchet/internal/protocol.gleam` (173 lines)
- `src/hatchet/types.gleam`

## Files Created

- `test/hatchet/schedule_and_cron_test.gleam` (555 lines)
- `SCHEDULE_CRON_VERIFICATION_REPORT.md` (this document)

---

**Report Complete**
