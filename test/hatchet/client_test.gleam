import gleam/dict
import gleam/option
import gleeunit/should
import hatchet/client
import hatchet/internal/config
import hatchet/types

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

// ============================================================================
// Worker Config Helper Tests
// ============================================================================

pub fn worker_config_helper_test() {
  let config = client.worker_config(option.Some("my-worker"), 15)

  config.name
  |> should.equal(option.Some("my-worker"))

  config.slots
  |> should.equal(15)
}

pub fn default_worker_config_test() {
  let config = client.default_worker_config()

  config.name
  |> should.equal(option.None)

  config.slots
  |> should.equal(10)
}

// ============================================================================
// TLS Configuration Tests
// ============================================================================

pub fn client_with_tls_test() {
  let assert Ok(base_client) = client.new("api.hatchet.run", "token")
  let tls_client = client.with_tls(base_client, "/etc/ssl/certs/ca.pem")

  types.get_host(tls_client)
  |> should.equal("api.hatchet.run")

  types.get_token(tls_client)
  |> should.equal("token")
}

pub fn client_with_mtls_test() {
  let assert Ok(base_client) = client.new("api.hatchet.run", "token")
  let mtls_client =
    client.with_mtls(
      base_client,
      "/etc/ssl/certs/ca.pem",
      "/etc/hatchet/client.pem",
      "/etc/hatchet/client-key.pem",
    )

  types.get_host(mtls_client)
  |> should.equal("api.hatchet.run")
}

pub fn client_with_insecure_test() {
  let assert Ok(base_client) = client.new("localhost", "dev-token")
  let insecure_client = client.with_insecure(base_client)

  types.get_host(insecure_client)
  |> should.equal("localhost")

  types.get_port(insecure_client)
  |> should.equal(7070)
}

// ============================================================================
// Client Creation Tests
// ============================================================================

pub fn client_from_config_success_test() {
  let cfg =
    config.Config(
      host: "localhost",
      port: 7070,
      grpc_port: 7077,
      token: option.Some("test-token"),
      namespace: option.None,
      tls_ca: option.None,
      tls_cert: option.None,
      tls_key: option.None,
    )

  case client.with_config(cfg) {
    Ok(client) -> {
      types.get_host(client)
      |> should.equal("localhost")

      types.get_token(client)
      |> should.equal("test-token")
    }
    Error(_) -> should.fail()
  }
}

pub fn client_from_config_no_token_test() {
  let cfg =
    config.Config(
      host: "localhost",
      port: 7070,
      grpc_port: 7077,
      token: option.None,
      namespace: option.None,
      tls_ca: option.None,
      tls_cert: option.None,
      tls_key: option.None,
    )

  case client.with_config(cfg) {
    Ok(_) -> should.fail()
    Error(msg) ->
      msg |> should.equal("Token is required for client configuration")
  }
}

// ============================================================================
// Multiple Client Management Tests
// ============================================================================

pub fn multiple_clients_test() {
  let assert Ok(client1) = client.new("host1", "token1")
  let assert Ok(client2) = client.new("host2", "token2")

  types.get_host(client1)
  |> should.equal("host1")

  types.get_host(client2)
  |> should.equal("host2")

  types.get_token(client1)
  |> should.equal("token1")

  types.get_token(client2)
  |> should.equal("token2")
}

pub fn client_immutability_test() {
  let assert Ok(base) = client.new("localhost", "token")
  let with_port = client.with_port(base, 8080)
  let with_namespace = client.with_namespace(base, "prod")

  types.get_port(base)
  |> should.equal(7070)

  types.get_port(with_port)
  |> should.equal(8080)

  types.get_namespace(base)
  |> should.equal(option.None)

  types.get_namespace(with_namespace)
  |> should.equal(option.Some("prod"))

  types.get_port(with_namespace)
  |> should.equal(7070)
}

// ============================================================================
// Worker Config Builder Tests
// ============================================================================

pub fn worker_config_with_labels_test() {
  let config =
    types.WorkerConfig(
      name: option.Some("labeled-worker"),
      slots: 15,
      durable_slots: 2,
      labels: dict.from_list([#("region", "us-west"), #("env", "prod")]),
    )

  case dict.get(config.labels, "region") {
    Ok(value) -> value |> should.equal("us-west")
    Error(_) -> should.fail()
  }

  case dict.get(config.labels, "env") {
    Ok(value) -> value |> should.equal("prod")
    Error(_) -> should.fail()
  }
}

pub fn worker_config_durable_slots_test() {
  let config =
    types.WorkerConfig(
      name: option.None,
      slots: 10,
      durable_slots: 3,
      labels: dict.new(),
    )

  config.durable_slots
  |> should.equal(3)
}

// ============================================================================
// Namespace and Tenant Tests
// ============================================================================

pub fn client_namespace_chain_test() {
  let assert Ok(client) = client.new("localhost", "token")
  let with_ns = client.with_namespace(client, "tenant-a")
  let changed_ns = client.with_namespace(with_ns, "tenant-b")

  types.get_namespace(changed_ns)
  |> should.equal(option.Some("tenant-b"))
}

pub fn client_default_tenant_test() {
  let assert Ok(client) = client.new("localhost", "token")

  types.get_tenant_id(client)
  |> should.equal("default")
}

// ============================================================================
// Port Configuration Tests
// ============================================================================

pub fn client_custom_port_test() {
  let assert Ok(base) = client.new("localhost", "token")
  let custom = client.with_port(base, 9090)

  types.get_port(custom)
  |> should.equal(9090)
}

pub fn client_port_chain_test() {
  let assert Ok(base) = client.new("localhost", "token")
  let port1 = client.with_port(base, 8080)
  let port2 = client.with_port(port1, 9090)

  types.get_port(port2)
  |> should.equal(9090)
}

// ============================================================================
// Error Handling Tests
// ============================================================================

pub fn client_register_workflows_empty_list_test() {
  let assert Ok(client) = client.new("localhost", "test-token")

  client.register_workflows(client, [])
  |> should.equal(Ok(Nil))
}
