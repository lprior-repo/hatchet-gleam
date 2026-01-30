import gleam/httpc
import gleam/option
import hatchet/errors
import hatchet/internal/http as h
import hatchet/internal/json as j
import hatchet/internal/protocol as p
import hatchet/types.{type Client}

/// Get metrics for a specific workflow.
///
/// Returns statistics including total runs, success rate,
/// and duration percentiles.
///
/// ## Example
///
/// ```gleam
/// case metrics.get_workflow_metrics(client, "my-workflow") {
///   Ok(metrics) -> io.debug(metrics)
///   Error(e) -> io.println(e)
/// }
/// ```
pub fn get_workflow_metrics(
  client: Client,
  workflow_name: String,
) -> Result(p.WorkflowMetrics, String) {
  let url = h.build_base_url(client) <> "/metrics/workflows/" <> workflow_name

  case h.make_authenticated_request(client, url, option.None) {
    Ok(req) -> {
      case httpc.send(req) {
        Ok(resp) if resp.status == 200 -> {
          case j.decode_workflow_metrics(resp.body) {
            Ok(metrics) -> Ok(metrics)
            Error(e) -> {
              Error(
                errors.to_simple_string(errors.decode_error(
                  "workflow metrics",
                  e,
                )),
              )
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

/// Get metrics for a specific worker.
///
/// Returns statistics including task counts, success/failure rates,
/// and uptime metrics.
///
/// ## Example
///
/// ```gleam
/// case metrics.get_worker_metrics(client, "worker-123") {
///   Ok(metrics) -> io.debug(metrics)
///   Error(e) -> io.println(e)
/// }
/// ```
pub fn get_worker_metrics(
  client: Client,
  worker_id: String,
) -> Result(p.WorkerMetrics, String) {
  let url = h.build_base_url(client) <> "/metrics/workers/" <> worker_id

  case h.make_authenticated_request(client, url, option.None) {
    Ok(req) -> {
      case httpc.send(req) {
        Ok(resp) if resp.status == 200 -> {
          case j.decode_worker_metrics(resp.body) {
            Ok(metrics) -> Ok(metrics)
            Error(e) -> {
              Error(
                errors.to_simple_string(errors.decode_error("worker metrics", e)),
              )
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
