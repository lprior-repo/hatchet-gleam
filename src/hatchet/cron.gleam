//// Cron management APIs for Hatchet workflows.
////
//// These functions manage cron-based recurring workflow triggers.
//// The Hatchet orchestrator handles the actual scheduling — the SDK
//// just provides the configuration and management interface.

import gleam/dynamic.{type Dynamic}
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/int
import hatchet/internal/json as j
import hatchet/internal/protocol as p
import hatchet/types.{type Client, type Workflow}

/// Create a named cron trigger for a workflow.
///
/// The Hatchet server will automatically run the workflow according
/// to the cron expression. Returns the cron ID on success.
///
/// ## Example
///
/// ```gleam
/// cron.create(client, my_workflow, "nightly-job", "0 0 * * *", input)
/// ```
pub fn create(
  client: Client,
  workflow: Workflow,
  name: String,
  expression: String,
  input: Dynamic,
) -> Result(String, String) {
  let req_body =
    j.encode_cron_create(p.CronCreateRequest(
      name: name,
      expression: expression,
      input: input,
    ))
  let url =
    build_base_url(client) <> "/api/v1/workflows/" <> workflow.name <> "/crons"

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
          case j.decode_cron_response(resp.body) {
            Ok(cron_resp) -> Ok(cron_resp.cron_id)
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

/// Delete a cron trigger by its ID.
pub fn delete(client: Client, cron_id: String) -> Result(Nil, String) {
  let url = build_base_url(client) <> "/api/v1/crons/" <> cron_id
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
