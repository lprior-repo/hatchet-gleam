import gleam/http/request
import gleam/int
import gleam/option
import hatchet/types.{type Client}

pub fn build_base_url(client: Client) -> String {
  let host = types.get_host(client)
  let port = types.get_port(client)
  let tenant_id = types.get_tenant_id(client)
  "http://"
  <> host
  <> ":"
  <> int.to_string(port)
  <> "/api/v1/tenants/"
  <> tenant_id
}

pub fn make_authenticated_request(
  client: Client,
  url: String,
  body: option.Option(String),
) -> Result(request.Request(String), String) {
  case request.to(url) {
    Ok(req) -> {
      let req = case body {
        option.Some(b) ->
          req
          |> request.set_body(b)
          |> request.set_header("content-type", "application/json")
        option.None -> req
      }

      let req =
        req
        |> request.set_header(
          "authorization",
          "Bearer " <> types.get_token(client),
        )

      Ok(req)
    }
    Error(_) -> Error("Invalid URL")
  }
}
