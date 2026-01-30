import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/option
import hatchet/errors
import hatchet/internal/http as h
import hatchet/internal/json as j
import hatchet/internal/protocol as p
import hatchet/types.{type Client}

/// List all registered workflows.
///
/// Returns metadata for all workflows including their triggers,
/// concurrency settings, and status.
///
/// ## Example
///
/// ```gleam
/// case workflows.list(client) {
///   Ok(list) -> io.debug(list)
///   Error(e) -> io.println(e)
/// }
/// ```
pub fn list(client: Client) -> Result(List(p.WorkflowMetadata), String) {
  let url = h.build_base_url(client) <> "/workflows"

  case h.make_authenticated_request(client, url, option.None) {
    Ok(req) -> {
      case httpc.send(req) {
        Ok(resp) if resp.status == 200 -> {
          case j.decode_workflow_list(resp.body) {
            Ok(list_resp) -> Ok(list_resp.workflows)
            Error(e) -> {
              Error(
                errors.to_simple_string(errors.decode_error(
                  "workflow list response",
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

/// Get metadata for a specific workflow by name.
///
/// Returns detailed workflow metadata including triggers,
/// concurrency settings, and status.
///
/// ## Example
///
/// ```gleam
/// case workflows.get(client, "my-workflow") {
///   Ok(metadata) -> io.debug(metadata)
///   Error(e) -> io.println(e)
/// }
/// ```
pub fn get(
  client: Client,
  workflow_name: String,
) -> Result(p.WorkflowMetadata, String) {
  let url = h.build_base_url(client) <> "/workflows/" <> workflow_name

  case h.make_authenticated_request(client, url, option.None) {
    Ok(req) -> {
      case httpc.send(req) {
        Ok(resp) if resp.status == 200 -> {
          case j.decode_workflow_metadata(resp.body) {
            Ok(metadata) -> Ok(metadata)
            Error(e) -> {
              Error(
                errors.to_simple_string(errors.decode_error(
                  "workflow metadata",
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

/// Delete a workflow by name.
///
/// This removes the workflow definition and all associated triggers.
/// Note: Running workflow executions are not affected.
///
/// ## Example
///
/// ```gleam
/// case workflows.delete(client, "my-workflow") {
///   Ok(Nil) -> io.println("Workflow deleted")
///   Error(e) -> io.println(e)
/// }
/// ```
pub fn delete(client: Client, workflow_name: String) -> Result(Nil, String) {
  let url = h.build_base_url(client) <> "/workflows/" <> workflow_name

  case h.make_authenticated_request(client, url, option.None) {
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
