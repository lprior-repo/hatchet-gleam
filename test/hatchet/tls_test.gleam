//// TLS/mTLS integration tests.
////
//// These tests verify that TLS and mTLS configurations work correctly
//// with the client and worker. They run unit tests only (no live server required).

import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import hatchet/client
import hatchet/internal/tls
import hatchet/types

pub fn main() {
  gleeunit.main()
}

// ============================================================================
// Client TLS Option Tests
// ============================================================================

pub fn client_with_tls_test() {
  let assert Ok(base_client) = client.new("localhost", "test-token")
  let tls_client = client.with_tls(base_client, "/path/to/ca.pem")

  let tls_config = types.get_tls_config(tls_client)

  case tls_config {
    tls.Tls(ca_path) -> ca_path |> should.equal("/path/to/ca.pem")
    _ -> should.fail()
  }
}

pub fn client_with_mtls_test() {
  let assert Ok(base_client) = client.new("localhost", "test-token")
  let mtls_client =
    client.with_mtls(
      base_client,
      "/path/to/ca.pem",
      "/path/to/cert.pem",
      "/path/to/key.pem",
    )

  let tls_config = types.get_tls_config(mtls_client)

  case tls_config {
    tls.Mtls(ca, cert, key) -> {
      ca |> should.equal("/path/to/ca.pem")
      cert |> should.equal("/path/to/cert.pem")
      key |> should.equal("/path/to/key.pem")
    }
    _ -> should.fail()
  }
}

pub fn client_with_insecure_test() {
  let assert Ok(base_client) = client.new("localhost", "test-token")
  let insecure_client = client.with_insecure(base_client)

  let tls_config = types.get_tls_config(insecure_client)

  tls_config |> should.equal(tls.Insecure)
}

pub fn client_tls_preserves_other_config_test() {
  let assert Ok(base_client) = client.new("localhost", "test-token")
  let tls_client = client.with_tls(base_client, "/ca.pem")

  types.get_host(tls_client) |> should.equal("localhost")
  types.get_token(tls_client) |> should.equal("test-token")
  types.get_port(tls_client) |> should.equal(7070)
  types.get_namespace(tls_client) |> should.equal(None)
}

pub fn client_mtls_preserves_namespace_test() {
  let assert Ok(base_client) = client.new("localhost", "test-token")
  let namespaced_client = client.with_namespace(base_client, "tenant-123")
  let mtls_client = client.with_mtls(namespaced_client, "/ca", "/cert", "/key")

  case types.get_namespace(mtls_client) {
    Some(ns) -> ns |> should.equal("tenant-123")
    None -> should.fail()
  }
}

pub fn client_insecure_preserves_config_test() {
  let assert Ok(base_client) = client.new("localhost", "test-token")
  let port_client = client.with_port(base_client, 8080)
  let insecure_client = client.with_insecure(port_client)

  types.get_host(insecure_client) |> should.equal("localhost")
  types.get_port(insecure_client) |> should.equal(8080)
  types.get_token(insecure_client) |> should.equal("test-token")
}

// ============================================================================
// Client Option Chaining Tests
// ============================================================================

pub fn client_chain_tls_with_namespace_test() {
  let assert Ok(base_client) = client.new("localhost", "test-token")
  let configured_client =
    base_client
    |> client.with_namespace("prod")
    |> client.with_tls("/etc/ssl/ca.pem")

  case types.get_namespace(configured_client) {
    Some(ns) -> ns |> should.equal("prod")
    None -> should.fail()
  }

  let tls_config = types.get_tls_config(configured_client)
  case tls_config {
    tls.Tls(ca) -> ca |> should.equal("/etc/ssl/ca.pem")
    _ -> should.fail()
  }
}

pub fn client_chain_mtls_with_port_test() {
  let assert Ok(base_client) = client.new("localhost", "test-token")
  let configured_client =
    base_client
    |> client.with_port(9090)
    |> client.with_mtls("/ca", "/cert", "/key")

  types.get_port(configured_client) |> should.equal(9090)

  let tls_config = types.get_tls_config(configured_client)
  case tls_config {
    tls.Mtls(_, _, _) -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn client_chain_insecure_with_namespace_test() {
  let assert Ok(base_client) = client.new("localhost", "test-token")
  let configured_client =
    base_client
    |> client.with_namespace("dev")
    |> client.with_port(8080)
    |> client.with_insecure()

  case types.get_namespace(configured_client) {
    Some(ns) -> ns |> should.equal("dev")
    None -> should.fail()
  }

  types.get_port(configured_client) |> should.equal(8080)
  types.get_tls_config(configured_client) |> should.equal(tls.Insecure)
}

// ============================================================================
// TLS Security Detection Tests
// ============================================================================

pub fn client_tls_is_secure_test() {
  let assert Ok(base_client) = client.new("localhost", "test-token")
  let tls_client = client.with_tls(base_client, "/ca.pem")

  let tls_config = types.get_tls_config(tls_client)
  tls.is_secure(tls_config) |> should.be_true()
}

pub fn client_mtls_is_secure_test() {
  let assert Ok(base_client) = client.new("localhost", "test-token")
  let mtls_client = client.with_mtls(base_client, "/ca", "/cert", "/key")

  let tls_config = types.get_tls_config(mtls_client)
  tls.is_secure(tls_config) |> should.be_true()
}

pub fn client_insecure_is_not_secure_test() {
  let assert Ok(base_client) = client.new("localhost", "test-token")
  let insecure_client = client.with_insecure(base_client)

  let tls_config = types.get_tls_config(insecure_client)
  tls.is_secure(tls_config) |> should.be_false()
}

pub fn client_default_is_insecure_test() {
  let assert Ok(base_client) = client.new("localhost", "test-token")

  let tls_config = types.get_tls_config(base_client)
  tls_config |> should.equal(tls.Insecure)
  tls.is_secure(tls_config) |> should.be_false()
}

// ============================================================================
// Multiple TLS Transitions Tests
// ============================================================================

pub fn client_transition_from_insecure_to_tls_test() {
  let assert Ok(base_client) = client.new("localhost", "test-token")
  let insecure_client = client.with_insecure(base_client)
  let tls_client = client.with_tls(insecure_client, "/ca.pem")

  let tls_config = types.get_tls_config(tls_client)
  case tls_config {
    tls.Tls(_) -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn client_transition_from_tls_to_mtls_test() {
  let assert Ok(base_client) = client.new("localhost", "test-token")
  let tls_client = client.with_tls(base_client, "/ca.pem")
  let mtls_client = client.with_mtls(tls_client, "/ca2", "/cert", "/key")

  let tls_config = types.get_tls_config(mtls_client)
  case tls_config {
    tls.Mtls(ca, cert, key) -> {
      ca |> should.equal("/ca2")
      cert |> should.equal("/cert")
      key |> should.equal("/key")
    }
    _ -> should.fail()
  }
}

pub fn client_transition_from_mtls_to_insecure_test() {
  let assert Ok(base_client) = client.new("localhost", "test-token")
  let mtls_client = client.with_mtls(base_client, "/ca", "/cert", "/key")
  let insecure_client = client.with_insecure(mtls_client)

  let tls_config = types.get_tls_config(insecure_client)
  tls_config |> should.equal(tls.Insecure)
}
