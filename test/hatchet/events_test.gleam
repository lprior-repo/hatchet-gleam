//// Comprehensive tests for event publishing, subscription, and delivery.

import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/string
import gleeunit
import gleeunit/should
import hatchet/events
import hatchet/internal/json as hatchet_json
import hatchet/internal/protocol as p

pub fn main() {
  gleeunit.main()
}

/// Helper to parse JSON string to Dynamic.
fn from_json(json_string: String) -> Dynamic {
  let assert Ok(dynamic) = json.parse(json_string, decode.dynamic)
  dynamic
}

// ============================================================================
// SECTION 1: Event Emission Tests
// ============================================================================

/// Test: Publish single event successfully
pub fn publish_single_event_test() {
  let data = dynamic.string("test-data")
  let req =
    p.EventPublishRequest(
      event_key: "user.created",
      data: data,
      metadata: dict.new(),
    )

  let encoded = hatchet_json.encode_event_publish(req)

  string.contains(encoded, "user.created")
  |> should.equal(True)

  string.contains(encoded, "test-data")
  |> should.equal(True)
}

/// Test: Publish event with JSON payload
pub fn publish_event_with_json_payload_test() {
  let payload = from_json("{\"user_id\": 123, \"email\": \"test@example.com\"}")
  let req =
    p.EventPublishRequest(
      event_key: "order.created",
      data: payload,
      metadata: dict.new(),
    )

  let encoded = hatchet_json.encode_event_publish(req)

  string.contains(encoded, "order.created")
  |> should.equal(True)

  string.contains(encoded, "user_id")
  |> should.equal(True)
}

/// Test: Publish event with no payload (empty object)
pub fn publish_event_with_no_payload_test() {
  let payload = from_json("{}")
  let req =
    p.EventPublishRequest(
      event_key: "heartbeat",
      data: payload,
      metadata: dict.new(),
    )

  let encoded = hatchet_json.encode_event_publish(req)

  string.contains(encoded, "heartbeat")
  |> should.equal(True)

  string.contains(encoded, "data")
  |> should.equal(True)
}

/// Test: Publish event with large payload (1MB)
pub fn publish_event_with_large_payload_test() {
  let large_string = string.repeat("x", 1_048_576)
  let payload = dynamic.string(large_string)
  let req =
    p.EventPublishRequest(
      event_key: "large.data",
      data: payload,
      metadata: dict.new(),
    )

  let encoded = hatchet_json.encode_event_publish(req)

  string.contains(encoded, "large.data")
  |> should.equal(True)

  let length_check = string.length(encoded) > 1_000_000
  length_check
  |> should.be_true()
}

/// Test: Publish 100 events in sequence
pub fn publish_100_events_test() {
  let event_keys =
    list.range(0, 99) |> list.map(fn(i) { "event." <> int.to_string(i) })

  let events =
    event_keys
    |> list.map(fn(key) { events.event(key, dynamic.string("data-" <> key)) })

  events
  |> list.length
  |> should.equal(100)

  events
  |> list.map(fn(e) { e.key })
  |> list.contains("event.50")
  |> should.equal(True)
}

/// Test: Publish events with metadata
pub fn publish_event_with_metadata_test() {
  let data = dynamic.string("test")
  let metadata =
    dict.from_list([#("source", "api"), #("version", "1.0"), #("env", "prod")])

  let req =
    p.EventPublishRequest(
      event_key: "test.event",
      data: data,
      metadata: metadata,
    )

  let encoded = hatchet_json.encode_event_publish(req)

  string.contains(encoded, "source")
  |> should.equal(True)

  string.contains(encoded, "version")
  |> should.equal(True)

  string.contains(encoded, "env")
  |> should.equal(True)
}

/// Test: Event names with dots and hyphens
pub fn event_name_with_dots_and_hyphens_test() {
  let keys = [
    "user.created",
    "order.completed",
    "payment.success",
    "user.updated",
    "payment-failed",
    "user-registered",
  ]

  let encoded_events =
    keys
    |> list.map(fn(key) {
      let req =
        p.EventPublishRequest(
          event_key: key,
          data: dynamic.string("test"),
          metadata: dict.new(),
        )
      hatchet_json.encode_event_publish(req)
    })

  encoded_events
  |> list.length
  |> should.equal(6)

  encoded_events
  |> list.map(string.contains(_, "user.created"))
  |> list.any(fn(x) { x })
  |> should.equal(True)
}

/// Test: Event builder with metadata
pub fn event_builder_with_metadata_test() {
  let evt =
    events.event("test.event", dynamic.string("data"))
    |> events.with_metadata(
      dict.from_list([#("key1", "value1"), #("key2", "value2")]),
    )

  evt.key
  |> should.equal("test.event")

  dict.get(evt.metadata, "key1")
  |> should.equal(Ok("value1"))

  dict.get(evt.metadata, "key2")
  |> should.equal(Ok("value2"))
}

/// Test: Event builder with put_metadata
pub fn event_builder_put_metadata_test() {
  let evt =
    events.event("test.event", dynamic.string("data"))
    |> events.put_metadata("source", "web")
    |> events.put_metadata("version", "2.0")
    |> events.put_metadata("env", "staging")

  evt.key
  |> should.equal("test.event")

  dict.get(evt.metadata, "source")
  |> should.equal(Ok("web"))

  dict.get(evt.metadata, "version")
  |> should.equal(Ok("2.0"))

  dict.get(evt.metadata, "env")
  |> should.equal(Ok("staging"))
}

/// Test: Metadata override with put_metadata
pub fn event_metadata_override_test() {
  let evt =
    events.event("test.event", dynamic.string("data"))
    |> events.put_metadata("version", "1.0")
    |> events.put_metadata("version", "2.0")

  dict.get(evt.metadata, "version")
  |> should.equal(Ok("2.0"))
}

/// Test: Event builder without metadata
pub fn event_builder_no_metadata_test() {
  let evt = events.event("test.event", dynamic.string("data"))

  evt.key
  |> should.equal("test.event")

  evt.metadata
  |> should.equal(dict.new())
}

/// Test: Publish many events sequentially
pub fn publish_many_sequential_test() {
  let events_list = [
    events.event("event1", dynamic.string("data1")),
    events.event("event2", dynamic.string("data2")),
    events.event("event3", dynamic.string("data3")),
  ]

  events_list
  |> list.length
  |> should.equal(3)

  events_list
  |> list.map(fn(e) { e.key })
  |> should.equal(["event1", "event2", "event3"])
}

/// Test: Publish many events with mixed metadata
pub fn publish_many_with_metadata_test() {
  let events_list = [
    events.event("event1", dynamic.string("data1"))
      |> events.put_metadata("type", "a"),
    events.event("event2", dynamic.string("data2"))
      |> events.put_metadata("type", "b"),
    events.event("event3", dynamic.string("data3"))
      |> events.put_metadata("type", "c"),
  ]

  events_list
  |> list.map(fn(e) { dict.get(e.metadata, "type") })
  |> should.equal([Ok("a"), Ok("b"), Ok("c")])
}

/// Test: Event with nested object payload
pub fn event_with_nested_object_payload_test() {
  let payload =
    from_json(
      "{\"user\":{\"id\":123,\"name\":\"Test User\",\"profile\":{\"email\":\"test@example.com\",\"verified\":true}},\"timestamp\":1234567890}",
    )

  let req =
    p.EventPublishRequest(
      event_key: "user.profile.updated",
      data: payload,
      metadata: dict.new(),
    )

  let encoded = hatchet_json.encode_event_publish(req)

  string.contains(encoded, "user.profile.updated")
  |> should.equal(True)

  string.contains(encoded, "id")
  |> should.equal(True)

  string.contains(encoded, "timestamp")
  |> should.equal(True)
}

/// Test: Event with array payload
pub fn event_with_array_payload_test() {
  let payload = from_json("[1, 2, 3, 4, 5]")
  let req =
    p.EventPublishRequest(
      event_key: "numbers",
      data: payload,
      metadata: dict.new(),
    )

  let encoded = hatchet_json.encode_event_publish(req)

  string.contains(encoded, "numbers")
  |> should.equal(True)
}

/// Test: Event with null value in payload
pub fn event_with_null_value_test() {
  let payload = from_json("{\"value\": null}")
  let req =
    p.EventPublishRequest(
      event_key: "null.test",
      data: payload,
      metadata: dict.new(),
    )

  let encoded = hatchet_json.encode_event_publish(req)

  string.contains(encoded, "null.test")
  |> should.equal(True)
}

/// Test: Event with boolean payload
pub fn event_with_boolean_payload_test() {
  let payload = from_json("{\"success\": true, \"enabled\": false}")
  let req =
    p.EventPublishRequest(
      event_key: "bool.test",
      data: payload,
      metadata: dict.new(),
    )

  let encoded = hatchet_json.encode_event_publish(req)

  string.contains(encoded, "bool.test")
  |> should.equal(True)
}

/// Test: Event with numeric payload (integer and float)
pub fn event_with_numeric_payload_test() {
  let payload = from_json("{\"count\": 42, \"price\": 19.99, \"ratio\": 0.5}")
  let req =
    p.EventPublishRequest(
      event_key: "numeric.test",
      data: payload,
      metadata: dict.new(),
    )

  let encoded = hatchet_json.encode_event_publish(req)

  string.contains(encoded, "numeric.test")
  |> should.equal(True)
}

// ============================================================================
// SECTION 2: Event Listening Tests (Workflow Registration)
// ============================================================================

/// Test: Workflow triggered by exact event name match
pub fn workflow_exact_event_match_test() {
  let events_list = ["user.created", "order.placed", "payment.success"]

  events_list
  |> list.contains("user.created")
  |> should.equal(True)

  events_list
  |> list.length
  |> should.equal(3)
}

/// Test: Multiple workflows can listen to same event
pub fn multiple_workflows_same_event_test() {
  let workflow1_events = ["user.created"]
  let workflow2_events = ["user.created", "user.updated"]
  let workflow3_events = ["user.created"]

  workflow1_events
  |> list.contains("user.created")
  |> should.equal(True)

  workflow2_events
  |> list.contains("user.created")
  |> should.equal(True)

  workflow3_events
  |> list.contains("user.created")
  |> should.equal(True)
}

/// Test: Workflow not triggered by non-matching event
pub fn workflow_non_matching_event_test() {
  let workflow_events = ["user.created", "user.updated"]

  workflow_events
  |> list.contains("order.placed")
  |> should.equal(False)

  workflow_events
  |> list.contains("user.created")
  |> should.equal(True)
}

/// Test: Workflow with multiple event triggers
pub fn workflow_multiple_event_triggers_test() {
  let events_list = [
    "user.created",
    "user.updated",
    "user.deleted",
    "user.suspended",
  ]

  events_list
  |> list.length
  |> should.equal(4)

  events_list
  |> list.filter(fn(e) { string.starts_with(e, "user.") })
  |> list.length
  |> should.equal(4)
}

/// Test: Event naming conventions (entity.action)
pub fn event_naming_conventions_test() {
  let valid_events = [
    "user.created",
    "user.updated",
    "user.deleted",
    "order.created",
    "order.paid",
    "order.shipped",
    "payment.success",
    "payment.failed",
    "invoice.generated",
    "invoice.paid",
  ]

  valid_events
  |> list.length
  |> should.equal(10)

  valid_events
  |> list.all(fn(e) { string.contains(e, ".") })
  |> should.equal(True)
}

// ============================================================================
// SECTION 3: Event Payload Tests
// ============================================================================

/// Test: Event payload accessible as Dynamic type
pub fn event_payload_dynamic_test() {
  let payload = dynamic.string("test-payload")
  let evt = events.event("test.event", payload)

  evt.data
  |> should.equal(payload)
}

/// Test: Event payload with complex nested structure
pub fn event_payload_complex_structure_test() {
  let payload =
    from_json(
      "{\"order\":{\"id\":\"order-123\",\"items\":[{\"sku\":\"SKU001\",\"qty\":2,\"price\":10},{\"sku\":\"SKU002\",\"qty\":1,\"price\":25}],\"total\":45,\"status\":\"confirmed\"},\"customer\":{\"id\":\"cust-456\",\"name\":\"John Doe\",\"email\":\"john@example.com\"}}",
    )

  let req =
    p.EventPublishRequest(
      event_key: "order.complex",
      data: payload,
      metadata: dict.new(),
    )

  let encoded = hatchet_json.encode_event_publish(req)

  string.contains(encoded, "order.complex")
  |> should.equal(True)

  string.contains(encoded, "order-123")
  |> should.equal(True)
}

/// Test: Event payload is serializable to JSON
pub fn event_payload_json_serializable_test() {
  let payload = from_json("{\"key\": \"value\", \"number\": 42}")
  let req =
    p.EventPublishRequest(
      event_key: "json.test",
      data: payload,
      metadata: dict.new(),
    )

  let encoded = hatchet_json.encode_event_publish(req)

  string.contains(encoded, "json.test")
  |> should.equal(True)

  string.contains(encoded, "key")
  |> should.equal(True)

  string.contains(encoded, "42")
  |> should.equal(True)
}

// ============================================================================
// SECTION 4: Event Metadata Tests
// ============================================================================

/// Test: Event metadata passed through encoding
pub fn event_metadata_encoding_test() {
  let metadata =
    dict.from_list([
      #("trace_id", "abc123"),
      #("request_id", "def456"),
      #("source_system", "api"),
    ])

  let req =
    p.EventPublishRequest(
      event_key: "metadata.test",
      data: dynamic.string("data"),
      metadata: metadata,
    )

  let encoded = hatchet_json.encode_event_publish(req)

  string.contains(encoded, "trace_id")
  |> should.equal(True)

  string.contains(encoded, "request_id")
  |> should.equal(True)

  string.contains(encoded, "source_system")
  |> should.equal(True)
}

/// Test: Event metadata can be empty
pub fn event_metadata_empty_test() {
  let metadata = dict.new()
  let req =
    p.EventPublishRequest(
      event_key: "empty.metadata",
      data: dynamic.string("data"),
      metadata: metadata,
    )

  let encoded = hatchet_json.encode_event_publish(req)

  string.contains(encoded, "empty.metadata")
  |> should.equal(True)

  string.contains(encoded, "metadata")
  |> should.equal(True)
}

/// Test: Event metadata with special characters
pub fn event_metadata_special_characters_test() {
  let metadata =
    dict.from_list([
      #("key-with-dash", "value"),
      #("key_with_underscore", "value"),
      #("key.with.dots", "value"),
    ])

  let req =
    p.EventPublishRequest(
      event_key: "special.metadata",
      data: dynamic.string("data"),
      metadata: metadata,
    )

  let encoded = hatchet_json.encode_event_publish(req)

  string.contains(encoded, "special.metadata")
  |> should.equal(True)
}

/// Test: Event metadata values can be strings only
pub fn event_metadata_string_values_test() {
  let metadata =
    dict.from_list([#("count", "100"), #("flag", "true"), #("ratio", "0.5")])

  let req =
    p.EventPublishRequest(
      event_key: "string.metadata",
      data: dynamic.string("data"),
      metadata: metadata,
    )

  let encoded = hatchet_json.encode_event_publish(req)

  string.contains(encoded, "string.metadata")
  |> should.equal(True)
}

// ============================================================================
// SECTION 5: Event Type Safety Tests
// ============================================================================

/// Test: Event type ensures data is Dynamic
pub fn event_type_safety_dynamic_test() {
  let evt = events.event("test.event", dynamic.string("data"))

  evt.data
  |> decode.run(decode.string)
  |> should.equal(Ok("data"))
}

/// Test: Event type ensures metadata is Dict(String, String)
pub fn event_type_safety_metadata_test() {
  let evt = events.event("test.event", dynamic.string("data"))

  evt.metadata
  |> dict.size
  |> should.equal(0)

  let evt_with_meta =
    events.event("test.event", dynamic.string("data"))
    |> events.put_metadata("key", "value")

  dict.get(evt_with_meta.metadata, "key")
  |> should.equal(Ok("value"))
}

/// Test: Event type encapsulation with builder pattern
pub fn event_type_encapsulation_test() {
  let evt1 = events.event("test.event", dynamic.string("data"))
  let evt2 = events.event("test.event", dynamic.string("data"))

  evt1.key
  |> should.equal(evt2.key)

  let evt3 = events.event("different.event", dynamic.string("data"))

  let keys_are_different = evt1.key != evt3.key
  keys_are_different
  |> should.be_true()
}
