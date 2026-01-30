import gleam/httpc
import gleam/int
import gleam/option.{type Option, None, Some}
import hatchet/errors
import hatchet/internal/http as h
import hatchet/internal/json as j
import hatchet/internal/protocol as p
import hatchet/types.{type Client}

/// Query options for listing logs.
pub type LogQueryOptions {
  LogQueryOptions(
    run_id: String,
    task_run_id: Option(String),
    limit: Int,
    offset: Int,
  )
}

/// Create default log query options.
pub fn default_log_query(run_id: String) -> LogQueryOptions {
  LogQueryOptions(
    run_id: run_id,
    task_run_id: option.None,
    limit: 100,
    offset: 0,
  )
}

/// Set task run ID filter on log query.
pub fn with_task_run_id(
  query: LogQueryOptions,
  task_run_id: String,
) -> LogQueryOptions {
  LogQueryOptions(..query, task_run_id: option.Some(task_run_id))
}

/// Set pagination limit on log query.
pub fn with_limit(query: LogQueryOptions, limit: Int) -> LogQueryOptions {
  LogQueryOptions(..query, limit: limit)
}

/// Set pagination offset on log query.
pub fn with_offset(query: LogQueryOptions, offset: Int) -> LogQueryOptions {
  LogQueryOptions(..query, offset: offset)
}

/// List logs for a workflow run with pagination support.
///
/// Returns log entries for a run, optionally filtered by task,
/// with pagination support for large log sets.
///
/// ## Example
///
/// ```gleam
/// let query = logs.default_log_query("run-123")
///   |> logs.with_limit(50)
///   |> logs.with_task_run_id("task-456")
///
/// case logs.list(client, query) {
///   Ok(result) -> {
///     io.println("Logs: " <> string.length(result.logs))
///     io.println("Has more: " <> result.has_more)
///   }
///   Error(e) -> io.println(e)
/// }
/// ```
pub fn list(
  client: Client,
  query: LogQueryOptions,
) -> Result(p.LogListResponse, String) {
  let base_url = h.build_base_url(client) <> "/runs/" <> query.run_id <> "/logs"
  let url =
    base_url
    <> "?limit="
    <> int.to_string(query.limit)
    <> "&offset="
    <> int.to_string(query.offset)

  let url = case query.task_run_id {
    option.Some(task_id) -> url <> "&task_run_id=" <> task_id
    option.None -> url
  }

  case h.make_authenticated_request(client, url, option.None) {
    Ok(req) -> {
      case httpc.send(req) {
        Ok(resp) if resp.status == 200 -> {
          case j.decode_log_list(resp.body) {
            Ok(result) -> Ok(result)
            Error(e) -> {
              Error(errors.to_simple_string(errors.decode_error("log list", e)))
            }
          }
        }
        Ok(resp) ->
          Error(
            errors.to_simple_string(errors.api_http_error(
              resp.status,
              resp.body,
            )),
          )
        Error(_) -> Error(errors.to_simple_string(errors.network_error("")))
      }
    }
    Error(e) -> Error(e)
  }
}

/// Tail logs for a workflow run (most recent entries).
///
/// Returns the most recent log entries for a run.
/// Equivalent to listing logs with a small limit.
///
/// ## Example
///
/// ```gleam
/// case logs.tail(client, "run-123") {
///   Ok(logs) -> io.debug(logs)
///   Error(e) -> io.println(e)
/// }
/// ```
pub fn tail(client: Client, run_id: String) -> Result(List(p.LogEntry), String) {
  let query =
    LogQueryOptions(
      run_id: run_id,
      task_run_id: option.None,
      limit: 50,
      offset: 0,
    )

  case list(client, query) {
    Ok(result) -> Ok(result.logs)
    Error(e) -> Error(e)
  }
}
