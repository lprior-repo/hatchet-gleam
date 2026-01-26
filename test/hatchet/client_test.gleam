import gleam/dict
import gleam/option
import gleeunit/should
import hatchet/client
import hatchet/types.{type Client, type WorkerConfig}

pub fn client_new_test() {
  let assert Ok(client) = client.new("localhost", "test-token")

  types.get_host(client)
  |> should.equal("localhost")

  types.get_port(client)
  |> should.equal(7070)

  types.get_token(client)
  |> should.equal("test-token")

  types.get_namespace(client)
  |> should.equal(option.None)
}

pub fn client_with_port_test() {
  let assert Ok(client) = client.new("localhost", "test-token")
  let updated = client.with_port(client, 8080)

  types.get_port(updated)
  |> should.equal(8080)

  types.get_host(updated)
  |> should.equal("localhost")

  types.get_token(updated)
  |> should.equal("test-token")
}

pub fn client_with_namespace_test() {
  let assert Ok(client) = client.new("localhost", "test-token")
  let updated = client.with_namespace(client, "production")

  types.get_namespace(updated)
  |> should.equal(option.Some("production"))

  types.get_host(updated)
  |> should.equal("localhost")
}

pub fn worker_config_default_test() {
  let config =
    types.WorkerConfig(
      name: option.None,
      slots: 10,
      durable_slots: 1,
      labels: dict.new(),
    )

  config.slots
  |> should.equal(10)

  config.durable_slots
  |> should.equal(1)

  config.name
  |> should.equal(option.None)
}

pub fn worker_config_with_values_test() {
  let config =
    types.WorkerConfig(
      name: option.Some("test-worker"),
      slots: 20,
      durable_slots: 5,
      labels: dict.from_list([#("env", "test")]),
    )

  config.name
  |> should.equal(option.Some("test-worker"))

  config.slots
  |> should.equal(20)

  config.durable_slots
  |> should.equal(5)
}
