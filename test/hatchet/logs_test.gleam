import envoy
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import hatchet/client
import hatchet/logs
import hatchet/types

fn with_live_client(f: fn(types.Client) -> Nil) -> Nil {
  case envoy.get("HATCHET_LIVE_TEST") {
    Ok("1") -> {
      let token = case envoy.get("HATCHET_CLIENT_TOKEN") {
        Ok(t) -> t
        Error(_) ->
          case envoy.get("HATCHET_TOKEN") {
            Ok(t) -> t
            Error(_) -> ""
          }
      }
      case token {
        "" -> Nil
        t -> {
          let host =
            envoy.get("HATCHET_HOST")
            |> result_or("localhost")
          let assert Ok(c) = client.new(host, t)
          f(c)
        }
      }
    }
    _ -> Nil
  }
}

fn result_or(r: Result(a, e), default: a) -> a {
  case r {
    Ok(v) -> v
    Error(_) -> default
  }
}

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
  |> should.equal(None)
}

pub fn with_task_run_id_sets_task_filter_test() {
  let query = logs.default_log_query("run-123")
  let filtered = logs.with_task_run_id(query, "task-456")

  filtered.task_run_id
  |> should.equal(Some("task-456"))

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
  with_live_client(fn(client) {
    case logs.tail(client, "run-123") {
      Ok(logs_result) -> {
        should.be_true(list.length(logs_result) <= 50)
      }
      Error(_) -> should.be_true(False)
    }
  })
}
