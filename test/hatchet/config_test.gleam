import gleam/option
import gleeunit/should
import hatchet/config
import hatchet/types

pub fn config_has_required_fields_test() {
  let test_config =
    config.Config(
      host: "localhost",
      port: 7070,
      token: "test-token",
      tenant_id: "tenant-123",
      namespace: option.None,
      tls_config: option.None,
    )

  test_config.host
  |> should.equal("localhost")

  test_config.port
  |> should.equal(7070)

  test_config.token
  |> should.equal("test-token")
}

pub fn config_supports_optional_namespace_test() {
  let config_with_namespace =
    config.Config(
      host: "localhost",
      port: 7070,
      token: "test-token",
      tenant_id: "tenant-123",
      namespace: option.Some("production"),
      tls_config: option.None,
    )

  config_with_namespace.namespace
  |> should.equal(option.Some("production"))
}

pub fn config_without_namespace_has_none_test() {
  let config_no_namespace =
    config.Config(
      host: "localhost",
      port: 7070,
      token: "test-token",
      tenant_id: "tenant-123",
      namespace: option.None,
      tls_config: option.None,
    )

  config_no_namespace.namespace
  |> should.equal(option.None)
}

pub fn tls_config_has_all_required_fields_test() {
  let tls_config =
    config.TlsConfig(
      ca_cert_path: option.Some("/path/to/ca.crt"),
      ca_cert_dir: option.Some("/path/to/certs"),
      verify_host: True,
      verify_peer: True,
    )

  tls_config.ca_cert_path
  |> should.equal(option.Some("/path/to/ca.crt"))

  tls_config.ca_cert_dir
  |> should.equal(option.Some("/path/to/certs"))

  tls_config.verify_host
  |> should.equal(True)

  tls_config.verify_peer
  |> should.equal(True)
}

pub fn tls_config_supports_optional_paths_test() {
  let minimal_tls =
    config.TlsConfig(
      ca_cert_path: option.None,
      ca_cert_dir: option.None,
      verify_host: False,
      verify_peer: False,
    )

  minimal_tls.ca_cert_path
  |> should.equal(option.None)

  minimal_tls.ca_cert_dir
  |> should.equal(option.None)

  minimal_tls.verify_host
  |> should.equal(False)

  minimal_tls.verify_peer
  |> should.equal(False)
}

pub fn to_client_converts_config_to_client_test() {
  let cfg =
    config.Config(
      host: "custom-host",
      port: 9090,
      token: "custom-token",
      tenant_id: "tenant-456",
      namespace: option.Some("staging"),
      tls_config: option.None,
    )

  let client = config.to_client(cfg)

  types.get_host(client)
  |> should.equal("custom-host")

  types.get_port(client)
  |> should.equal(9090)

  types.get_token(client)
  |> should.equal("custom-token")
}

pub fn to_client_preserves_namespace_test() {
  let cfg =
    config.Config(
      host: "localhost",
      port: 7070,
      token: "test-token",
      tenant_id: "tenant-123",
      namespace: option.Some("production"),
      tls_config: option.None,
    )

  let client = config.to_client(cfg)

  types.get_namespace(client)
  |> should.equal(option.Some("production"))
}

pub fn config_values_are_immutable_test() {
  let original =
    config.Config(
      host: "localhost",
      port: 7070,
      token: "test-token",
      tenant_id: "tenant-123",
      namespace: option.None,
      tls_config: option.None,
    )

  let modified =
    config.Config(
      host: "modified-host",
      port: 8080,
      token: "modified-token",
      tenant_id: "tenant-456",
      namespace: option.None,
      tls_config: option.None,
    )

  original.host
  |> should.equal("localhost")

  original.port
  |> should.equal(7070)

  modified.host
  |> should.equal("modified-host")

  modified.port
  |> should.equal(8080)
}
