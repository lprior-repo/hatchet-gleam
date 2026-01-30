import gleeunit/should
import hatchet/client
import hatchet/logs
import hatchet/types

pub fn default_log_query_creates_valid_query_test() {
  let query = logs.default_log_query("run-123")

  query.run_id
  |> should.equal("run-123")

  query.limit
  |> should.equal(100)

  query.offset
  |> should.equal(0)
}

pub fn default_log_query_has_no_task_run_id_test() {
  let query = logs.default_log_query("run-123")

  query.task_run_id
  |> should.equal(types.OptionNone)
}

pub fn with_task_run_id_sets_task_filter_test() {
  let query = logs.default_log_query("run-123")
  let filtered = logs.with_task_run_id(query, "task-456")

  filtered.task_run_id
  |> should.equal(types.OptionSome("task-456"))

  filtered.run_id
  |> should.equal("run-123")
}

pub fn with_limit_changes_page_size_test() {
  let query = logs.default_log_query("run-123")
  let limited = logs.with_limit(query, 50)

  limited.limit
  |> should.equal(50)

  limited.run_id
  |> should.equal("run-123")
}

pub fn with_offset_changes_page_offset_test() {
  let query = logs.default_log_query("run-123")
  let offset = logs.with_offset(query, 100)

  offset.offset
  |> should.equal(100)

  offset.run_id
  |> should.equal("run-123")
}

pub fn query_builders_preserve_chain_settings_test() {
  let query =
    logs.default_log_query("run-123")
    |> logs.with_limit(25)
    |> logs.with_offset(50)
    |> logs.with_task_run_id("task-789")

  query.run_id
  |> should.equal("run-123")

  query.limit
  |> should.equal(25)

  query.offset
  |> should.equal(50)
}

pub fn tail_returns_recent_logs_test() {
  let assert Ok(client) = client.new("localhost", "test-token")

  case logs.tail(client, "run-123") {
    Ok(logs_result) -> {
      list.length(logs_result)
      |> should.be_less_than_or_equal(50)
    }
    Error(_) -> should.be_true(False)
  }
}
