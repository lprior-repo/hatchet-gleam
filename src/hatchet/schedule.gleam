//// Schedule management APIs for one-time future workflow runs.
////
//// These functions manage scheduled workflow runs that trigger at
//// a specific time. The Hatchet orchestrator handles the scheduling.

import gleam/dynamic.{type Dynamic}
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/int
import hatchet/internal/json as j
import hatchet/internal/protocol as p
import hatchet/types.{type Client, type Workflow}

/// Schedule a one-time workflow run at a specific time.
///
/// `trigger_at` should be an ISO 8601 timestamp string.
/// Returns the schedule ID on success.
///
/// ## Example
///
/// ```gleam
/// schedule.create(client, my_workflow, "2024-12-25T00:00:00Z", input)
/// ```
pub fn create(
  client: Client,
  workflow: Workflow,
  trigger_at: String,
  input: Dynamic,
) -> Result(String, String) {
  let req_body =
    j.encode_schedule_create(p.ScheduleCreateRequest(
      trigger_at: trigger_at,
      input: input,
    ))
  let url =
    build_base_url(client)
    <> "/api/v1/workflows/"
    <> workflow.name
    <> "/schedules"

  case request.to(url) {
    Ok(req) -> {
      let req =
        req
        |> request.set_body(req_body)
        |> request.set_header("content-type", "application/json")
        |> request.set_header(
          "authorization",
          "Bearer " <> types.get_token(client),
        )

      case httpc.send(req) {
        Ok(resp) if resp.status == 200 || resp.status == 201 -> {
          case j.decode_schedule_response(resp.body) {
            Ok(sched_resp) -> Ok(sched_resp.schedule_id)
            Error(e) -> Error("Failed to decode response: " <> e)
          }
        }
        Ok(resp) ->
          Error("API error: " <> int.to_string(resp.status) <> " " <> resp.body)
        Error(_) -> Error("Network error")
      }
    }
    Error(_) -> Error("Invalid URL")
  }
}

/// Delete a scheduled run by its ID.
pub fn delete(client: Client, schedule_id: String) -> Result(Nil, String) {
  let url = build_base_url(client) <> "/api/v1/schedules/" <> schedule_id
  case request.to(url) {
    Ok(req) -> {
      let req =
        req
        |> request.set_method(http.Delete)
        |> request.set_header(
          "authorization",
          "Bearer " <> types.get_token(client),
        )

      case httpc.send(req) {
        Ok(resp) if resp.status == 200 || resp.status == 204 -> Ok(Nil)
        Ok(resp) ->
          Error("API error: " <> int.to_string(resp.status) <> " " <> resp.body)
        Error(_) -> Error("Network error")
      }
    }
    Error(_) -> Error("Invalid URL")
  }
}

fn build_base_url(client: Client) -> String {
  let host = types.get_host(client)
  let port = types.get_port(client)
  "http://" <> host <> ":" <> int.to_string(port)
}
