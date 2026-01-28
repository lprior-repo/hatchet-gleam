import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/httpc
import gleam/list
import gleam/option
import hatchet/errors
import hatchet/internal/http as h
import hatchet/internal/json
import hatchet/internal/protocol as p
import hatchet/types.{type Client}

/// Publish an event to the Hatchet server.
///
/// This triggers any workflows that are listening for this event.
///
/// **Parameters:**
///   - `client`: The Hatchet client
///   - `event_key`: The unique key for this event
///   - `data`: The event data (arbitrary Dynamic value)
///
/// **Returns:** `Ok(Nil)` on success, `Error(String)` on failure
///
/// **Examples:**
/// ```gleam
/// let assert Ok(_) = events.publish(
///   cli,
///   "user.created",
///   dynamic.from("{\"user_id\": 123}")
/// )
/// ```
pub fn publish(
  client: Client,
  event_key: String,
  data: Dynamic,
) -> Result(Nil, String) {
  publish_with_metadata(client, event_key, data, dict.new())
}

/// Publish an event with metadata to the Hatchet server.
///
/// This triggers any workflows that are listening for this event.
/// Metadata can be used for filtering and routing.
///
/// **Parameters:**
///   - `client`: The Hatchet client
///   - `event_key`: The unique key for this event
///   - `data`: The event data (arbitrary Dynamic value)
///   - `metadata`: Additional metadata for the event
///
/// **Returns:** `Ok(Nil)` on success, `Error(String)` on failure
///
/// **Examples:**
/// ```gleam
/// let assert Ok(_) = events.publish_with_metadata(
///   cli,
///   "user.created",
///   dynamic.from("{\"user_id\": 123}"),
///   dict.from_list([#("source", "web"), #("version", "1.0")])
/// )
/// ```
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

  let url = h.build_base_url(client) <> "/api/v1/events"

  case h.make_authenticated_request(client, url, option.Some(body)) {
    Ok(req) -> {
      case httpc.send(req) {
        Ok(response) if response.status >= 200 && response.status < 300 ->
          Ok(Nil)
        Ok(response) -> {
          Error(
            errors.to_simple_string(errors.api_http_error(response.status, "")),
          )
        }
        Error(_) ->
          Error(
            errors.to_simple_string(errors.network_error("publishing event")),
          )
      }
    }
    Error(e) -> Error(e)
  }
}

/// Publish multiple events at once.
///
/// Events are published sequentially. If one fails, no further events are published.
///
/// **Parameters:**
///   - `client`: The Hatchet client
///   - `events`: List of events to publish
///
/// **Returns:** `Ok(Nil)` if all events published, `Error(String)` on first failure
///
/// **Examples:**
/// ```gleam
/// let events_list = [
///   events.event("event1", dynamic.from("{}")),
///   events.event("event2", dynamic.from("{}")),
/// ]
/// let assert Ok(_) = events.publish_many(cli, events_list)
/// ```
pub fn publish_many(client: Client, events: List(Event)) -> Result(Nil, String) {
  list.fold(events, Ok(Nil), fn(acc, event) {
    case acc {
      Ok(_) ->
        publish_with_metadata(client, event.key, event.data, event.metadata)
      Error(_) -> acc
    }
  })
}

/// Type representing an event to be published.
///
/// Events can be created using the `event()` builder function
/// and configured with metadata using `with_metadata()` and `put_metadata()`.
///
/// **Examples:**
/// ```gleam
/// let evt = events.event("my-event", dynamic.from("{}"))
/// ```
pub type Event {
  Event(key: String, data: Dynamic, metadata: dict.Dict(String, String))
}

/// Create a new event with empty metadata.
///
/// **Parameters:**
///   - `key`: The event key
///   - `data`: The event data
///
/// **Returns:** An `Event` with empty metadata
///
/// **Examples:**
/// ```gleam
/// let evt = events.event("user.created", dynamic.from("{\"id\":123}"))
/// ```
pub fn event(key: String, data: Dynamic) -> Event {
  Event(key: key, data: data, metadata: dict.new())
}

/// Add metadata to an event.
///
/// Merges the provided metadata with the event's existing metadata.
/// The provided metadata takes precedence on key conflicts.
///
/// **Parameters:**
///   - `event`: The event to configure
///   - `metadata`: Metadata dictionary to merge
///
/// **Returns:** The updated event with merged metadata
///
/// **Examples:**
/// ```gleam
/// let evt = events.event("my-event", dynamic.from("{}"))
///   |> events.with_metadata(dict.from_list([#("source", "web")]))
/// ```
pub fn with_metadata(event: Event, metadata: dict.Dict(String, String)) -> Event {
  Event(
    key: event.key,
    data: event.data,
    metadata: dict.merge(event.metadata, metadata),
  )
}

/// Add a single metadata key-value pair to an event.
///
/// This inserts a new key-value pair into the event's metadata.
/// If the key already exists, its value is replaced.
///
/// **Parameters:**
///   - `event`: The event to configure
///   - `key`: The metadata key
///   - `value`: The metadata value
///
/// **Returns:** The updated event with additional metadata
///
/// **Examples:**
/// ```gleam
/// let evt = events.event("my-event", dynamic.from("{}"))
///   |> events.put_metadata("source", "web")
///   |> events.put_metadata("version", "1.0")
/// ```
pub fn put_metadata(event: Event, key: String, value: String) -> Event {
  Event(
    key: event.key,
    data: event.data,
    metadata: dict.insert(event.metadata, key, value),
  )
}
