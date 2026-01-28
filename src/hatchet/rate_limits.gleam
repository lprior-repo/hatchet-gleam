//// Rate limit management APIs.
////
//// These functions create and manage rate limits on the Hatchet server.
//// Tasks reference rate limits by key to throttle execution.
//// The Hatchet orchestrator enforces the limits — the SDK just configures them.

import gleam/http/request
import gleam/httpc
import gleam/int
import hatchet/errors
import hatchet/internal/json as j
import hatchet/internal/protocol as p
import hatchet/types.{type Client}

/// Duration units for rate limits.
pub type RateLimitDuration {
  Second
  Minute
  Hour
  Day
  Week
  Month
  Year
}

/// Create or update a rate limit.
///
/// If a rate limit with the given key already exists, it will be updated.
///
/// ## Example
///
/// ```gleam
/// // Allow max 10 requests per minute
/// rate_limits.upsert(client, "api_calls", 10, Minute)
/// ```
pub fn upsert(
  client: Client,
  key: String,
  limit: Int,
  duration: RateLimitDuration,
) -> Result(Nil, String) {
  let req_body =
    j.encode_rate_limit_upsert(p.RateLimitUpsertRequest(
      key: key,
      limit: limit,
      duration: duration_to_string(duration),
    ))
  let url = build_base_url(client) <> "/api/v1/rate-limits"

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
        Ok(resp) if resp.status == 200 || resp.status == 201 -> Ok(Nil)
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
    Error(_) -> Error("Invalid URL")
  }
}

fn duration_to_string(duration: RateLimitDuration) -> String {
  case duration {
    Second -> "SECOND"
    Minute -> "MINUTE"
    Hour -> "HOUR"
    Day -> "DAY"
    Week -> "WEEK"
    Month -> "MONTH"
    Year -> "YEAR"
  }
}

fn build_base_url(client: Client) -> String {
  let host = types.get_host(client)
  let port = types.get_port(client)
  "http://" <> host <> ":" <> int.to_string(port)
}
