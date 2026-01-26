import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/list
import hatchet/internal/json
import hatchet/internal/protocol as p
import hatchet/types.{type Client}

pub fn publish(
  client: Client,
  event_key: String,
  data: Dynamic,
) -> Result(Nil, String) {
  publish_with_metadata(client, event_key, data, dict.new())
}

pub fn publish_with_metadata(
  client: Client,
  event_key: String,
  data: Dynamic,
  metadata: dict.Dict(String, String),
) -> Result(Nil, String) {
  let body =
    json.encode_event_publish(p.EventPublishRequest(
      event_key: event_key,
      data: data,
      metadata: metadata,
    ))

  let host = types.get_host(client)
  let port = types.get_port(client)
  let token = types.get_token(client)

  let url = "http://" <> host <> ":" <> int.to_string(port) <> "/api/v1/events"

  case request.to(url) {
    Ok(req) -> {
      let req_with_body = request.set_body(req, body)
      let req_with_type =
        request.set_header(req_with_body, "content-type", "application/json")
      let req_with_auth =
        request.set_header(req_with_type, "authorization", "Bearer " <> token)

      case httpc.send(req_with_auth) {
        Ok(response) if response.status >= 200 && response.status < 300 ->
          Ok(Nil)
        Ok(response) -> {
          Error(
            "Event publish failed with status "
            <> int.to_string(response.status),
          )
        }
        Error(_) -> Error("Network error publishing event")
      }
    }
    Error(_) -> Error("Invalid URL")
  }
}

pub fn publish_many(client: Client, events: List(Event)) -> Result(Nil, String) {
  list.fold(events, Ok(Nil), fn(acc, event) {
    case acc {
      Ok(_) ->
        publish_with_metadata(client, event.key, event.data, event.metadata)
      Error(_) -> acc
    }
  })
}

pub type Event {
  Event(key: String, data: Dynamic, metadata: dict.Dict(String, String))
}

pub fn event(key: String, data: Dynamic) -> Event {
  Event(key: key, data: data, metadata: dict.new())
}

pub fn with_metadata(event: Event, metadata: dict.Dict(String, String)) -> Event {
  Event(
    key: event.key,
    data: event.data,
    metadata: dict.merge(event.metadata, metadata),
  )
}

pub fn put_metadata(event: Event, key: String, value: String) -> Event {
  Event(
    key: event.key,
    data: event.data,
    metadata: dict.insert(event.metadata, key, value),
  )
}
