////!
//// Test: Creating config from empty dict uses defaults.
////
//// When no values are provided, all fields should have sensible defaults:
//// - host: "localhost"
//// - port: 7070
//// - grpc_port: 7070
//// - token: None
//// - namespace: None
//// - tls_ca: None
//// - tls_cert: None
//// - tls_key: None
//// Test: Creating config from dict with custom host.
////
//// The host field should be overridden when provided in the dict.
//// Test: Creating config from dict with custom port.
////
//// The port field should be overridden when provided as a valid integer string.
//// Test: Creating config from dict with custom gRPC port.
////
//// The grpc_port field should be overridden when provided.
//// Test: Creating config from dict with token.
////
//// The token field should be set when provided in the dict.
//// Test: Creating config from dict with namespace.
////
//// The namespace field should be set when provided.
//// Test: Creating config from dict with TLS CA certificate.
////
//// The tls_ca field should be set when a certificate path is provided.
//// Test: Creating config from dict with mTLS certificates.
////
//// Both tls_cert and tls_key should be set when provided for mTLS.
//// Test: Creating config from dict with all fields.
////
//// When all fields are provided, none should use defaults.
//// Test: Invalid port string falls back to default.
////
//// When the port string cannot be parsed as an integer, the default
//// port (7070) should be used instead.
//// Test: Out-of-range port falls back to default.
////
//// When the port is outside the valid range (1-65535), the default
//// should be used.
//// Test: Zero port falls back to default.
////
//// Port 0 is reserved and not usable. The default should be used.
//// Test: Negative port falls back to default.
////
//// Negative port numbers are invalid. The default should be used.
//// Test: Maximum valid port is accepted.
////
//// Port 65535 is the maximum valid port number and should be accepted.
//// Test: Minimum valid port is accepted.
////
//// Port 1 is the minimum valid port number and should be accepted.
//// Test: REST URL for default localhost config.
////
//// The default config should generate "http://localhost:7070"
//// Test: REST URL for custom host and port.
////
//// Custom host and port should be reflected in the generated URL.
//// Test: gRPC URL for default config.
////
//// The default config should generate "localhost:7070" for gRPC.
//// Test: gRPC URL for custom host and port.
////
//// Custom host and gRPC port should be reflected in the generated URL.
//// Test: has_tls returns false when no TLS config.
////
//// A config without any TLS fields should not be detected as TLS-enabled.
//// Test: has_tls returns true when CA cert is set.
////
//// A config with just a CA certificate should be detected as TLS-enabled.
//// Test: has_tls returns true when client cert is set.
////
//// A config with just a client certificate should be detected as TLS-enabled.
//// Test: has_tls returns true when client key is set.
////
//// A config with just a client key should be detected as TLS-enabled.
//// Test: has_tls returns true when all TLS fields are set.
////
//// A config with all mTLS fields should be detected as TLS-enabled.
//// Test: Empty string token is treated as present.
////
//// An empty string token is still "set" - we distinguish between
//// None (not set) and Some("") (set but empty).
//// Test: Empty string host is accepted.
////
//// An empty string host is technically valid (though not useful).
//// The config module doesn't validate, it just loads.
//// Test: Whitespace-only token is preserved.
////
//// Whitespace tokens are unusual but valid. They should be preserved
//// as-is for the application layer to validate.
//// Test: Special characters in namespace are preserved.
////
//// Namespaces may contain special characters (dots, dashes, etc.).
//// These should be preserved as-is.
//// Test: Complete config for production scenario.
////
//// Verify a realistic production configuration with all fields set.
//// Test: Minimal config for development scenario.
////
//// Verify a minimal development configuration works.
//// Test: Config from dict overrides defaults selectively.
////
//// When only some fields are provided, others should use defaults.
//// Test: Config records are immutable.
////
//// Gleam records are immutable by default. This test verifies that
//// modifying a "copy" of config doesn't affect the original.

//! Comprehensive test suite for the configuration module following Martin Fowler's
//! testing philosophy:
//!
//! 1. Tests serve as documentation - each test clearly describes expected behavior
//! 2. Tests behavior over implementation - we verify config values, not code paths
//! 3. Edge cases covered - missing values, invalid values, boundary conditions
//! 4. Clear test names that describe the scenario
//!
//! Note: Tests that require environment variable manipulation must be run
//! in isolation or with proper setup/teardown to avoid interference.

/// Configuration Module Tests
///
import gleam/dict
import gleam/option
import gleeunit
import gleeunit/should
import hatchet/internal/config

pub fn main() {
  gleeunit.main()
}

// ============================================================================
// FROM_DICT FUNCTION TESTS
// ============================================================================

pub fn from_dict_empty_uses_defaults_test() {
  let cfg = config.from_dict(dict.new())

  cfg.host
  |> should.equal("localhost")

  cfg.port
  |> should.equal(7070)

  cfg.grpc_port
  |> should.equal(7070)

  cfg.token
  |> should.equal(option.None)

  cfg.namespace
  |> should.equal(option.None)

  cfg.tls_ca
  |> should.equal(option.None)

  cfg.tls_cert
  |> should.equal(option.None)

  cfg.tls_key
  |> should.equal(option.None)
}

pub fn from_dict_custom_host_test() {
  let values =
    dict.from_list([
      #("host", "hatchet.example.com"),
    ])

  let cfg = config.from_dict(values)

  cfg.host
  |> should.equal("hatchet.example.com")

  // Other fields should use defaults
  cfg.port
  |> should.equal(7070)
}

pub fn from_dict_custom_port_test() {
  let values =
    dict.from_list([
      #("port", "8080"),
    ])

  let cfg = config.from_dict(values)

  cfg.port
  |> should.equal(8080)
}

pub fn from_dict_custom_grpc_port_test() {
  let values =
    dict.from_list([
      #("grpc_port", "7070"),
    ])

  let cfg = config.from_dict(values)

  cfg.grpc_port
  |> should.equal(7070)
}

pub fn from_dict_with_token_test() {
  let values =
    dict.from_list([
      #("token", "test-token-12345"),
    ])

  let cfg = config.from_dict(values)

  cfg.token
  |> should.equal(option.Some("test-token-12345"))
}

pub fn from_dict_with_namespace_test() {
  let values =
    dict.from_list([
      #("namespace", "tenant-123"),
    ])

  let cfg = config.from_dict(values)

  cfg.namespace
  |> should.equal(option.Some("tenant-123"))
}

pub fn from_dict_with_tls_ca_test() {
  let values =
    dict.from_list([
      #("tls_ca", "/path/to/ca.pem"),
    ])

  let cfg = config.from_dict(values)

  cfg.tls_ca
  |> should.equal(option.Some("/path/to/ca.pem"))
}

pub fn from_dict_with_mtls_certificates_test() {
  let values =
    dict.from_list([
      #("tls_ca", "/path/to/ca.pem"),
      #("tls_cert", "/path/to/client.pem"),
      #("tls_key", "/path/to/client-key.pem"),
    ])

  let cfg = config.from_dict(values)

  cfg.tls_ca
  |> should.equal(option.Some("/path/to/ca.pem"))

  cfg.tls_cert
  |> should.equal(option.Some("/path/to/client.pem"))

  cfg.tls_key
  |> should.equal(option.Some("/path/to/client-key.pem"))
}

pub fn from_dict_with_all_fields_test() {
  let values =
    dict.from_list([
      #("host", "api.hatchet.run"),
      #("port", "443"),
      #("grpc_port", "7070"),
      #("token", "secret-token"),
      #("namespace", "prod"),
      #("tls_ca", "/etc/ssl/certs/ca.pem"),
      #("tls_cert", "/etc/hatchet/client.pem"),
      #("tls_key", "/etc/hatchet/client-key.pem"),
    ])

  let cfg = config.from_dict(values)

  cfg.host
  |> should.equal("api.hatchet.run")

  cfg.port
  |> should.equal(443)

  cfg.grpc_port
  |> should.equal(7070)

  cfg.token
  |> should.equal(option.Some("secret-token"))

  cfg.namespace
  |> should.equal(option.Some("prod"))

  cfg.tls_ca
  |> should.equal(option.Some("/etc/ssl/certs/ca.pem"))

  cfg.tls_cert
  |> should.equal(option.Some("/etc/hatchet/client.pem"))

  cfg.tls_key
  |> should.equal(option.Some("/etc/hatchet/client-key.pem"))
}

// ============================================================================
// INVALID PORT HANDLING TESTS
// ============================================================================

pub fn from_dict_invalid_port_uses_default_test() {
  let values =
    dict.from_list([
      #("port", "not-a-number"),
    ])

  let cfg = config.from_dict(values)

  cfg.port
  |> should.equal(7070)
}

pub fn from_dict_out_of_range_port_uses_default_test() {
  let values =
    dict.from_list([
      #("port", "99999"),
    ])

  let cfg = config.from_dict(values)

  cfg.port
  |> should.equal(7070)
}

pub fn from_dict_zero_port_uses_default_test() {
  let values =
    dict.from_list([
      #("port", "0"),
    ])

  let cfg = config.from_dict(values)

  cfg.port
  |> should.equal(7070)
}

pub fn from_dict_negative_port_uses_default_test() {
  let values =
    dict.from_list([
      #("port", "-1"),
    ])

  let cfg = config.from_dict(values)

  cfg.port
  |> should.equal(7070)
}

pub fn from_dict_max_valid_port_test() {
  let values =
    dict.from_list([
      #("port", "65535"),
    ])

  let cfg = config.from_dict(values)

  cfg.port
  |> should.equal(65_535)
}

pub fn from_dict_min_valid_port_test() {
  let values =
    dict.from_list([
      #("port", "1"),
    ])

  let cfg = config.from_dict(values)

  cfg.port
  |> should.equal(1)
}

// ============================================================================
// URL GENERATION TESTS
// ============================================================================

pub fn rest_url_default_config_test() {
  let cfg =
    config.Config(
      host: "localhost",
      port: 7070,
      grpc_port: 7070,
      token: option.None,
      namespace: option.None,
      tls_ca: option.None,
      tls_cert: option.None,
      tls_key: option.None,
    )

  config.rest_url(cfg)
  |> should.equal("http://localhost:7070")
}

pub fn rest_url_custom_host_port_test() {
  let cfg =
    config.Config(
      host: "api.hatchet.run",
      port: 443,
      grpc_port: 7070,
      token: option.None,
      namespace: option.None,
      tls_ca: option.None,
      tls_cert: option.None,
      tls_key: option.None,
    )

  config.rest_url(cfg)
  |> should.equal("http://api.hatchet.run:443")
}

pub fn grpc_url_default_config_test() {
  let cfg =
    config.Config(
      host: "localhost",
      port: 7070,
      grpc_port: 7070,
      token: option.None,
      namespace: option.None,
      tls_ca: option.None,
      tls_cert: option.None,
      tls_key: option.None,
    )

  config.grpc_url(cfg)
  |> should.equal("localhost:7070")
}

pub fn grpc_url_custom_host_port_test() {
  let cfg =
    config.Config(
      host: "hatchet.example.com",
      port: 7070,
      grpc_port: 8443,
      token: option.None,
      namespace: option.None,
      tls_ca: option.None,
      tls_cert: option.None,
      tls_key: option.None,
    )

  config.grpc_url(cfg)
  |> should.equal("hatchet.example.com:8443")
}

// ============================================================================
// TLS DETECTION TESTS
// ============================================================================

pub fn has_tls_returns_false_when_no_tls_test() {
  let cfg =
    config.Config(
      host: "localhost",
      port: 7070,
      grpc_port: 7070,
      token: option.None,
      namespace: option.None,
      tls_ca: option.None,
      tls_cert: option.None,
      tls_key: option.None,
    )

  config.has_tls(cfg)
  |> should.be_false()
}

pub fn has_tls_returns_true_when_ca_set_test() {
  let cfg =
    config.Config(
      host: "localhost",
      port: 7070,
      grpc_port: 7070,
      token: option.None,
      namespace: option.None,
      tls_ca: option.Some("/path/to/ca.pem"),
      tls_cert: option.None,
      tls_key: option.None,
    )

  config.has_tls(cfg)
  |> should.be_true()
}

pub fn has_tls_returns_true_when_cert_set_test() {
  let cfg =
    config.Config(
      host: "localhost",
      port: 7070,
      grpc_port: 7070,
      token: option.None,
      namespace: option.None,
      tls_ca: option.None,
      tls_cert: option.Some("/path/to/cert.pem"),
      tls_key: option.None,
    )

  config.has_tls(cfg)
  |> should.be_true()
}

pub fn has_tls_returns_true_when_key_set_test() {
  let cfg =
    config.Config(
      host: "localhost",
      port: 7070,
      grpc_port: 7070,
      token: option.None,
      namespace: option.None,
      tls_ca: option.None,
      tls_cert: option.None,
      tls_key: option.Some("/path/to/key.pem"),
    )

  config.has_tls(cfg)
  |> should.be_true()
}

pub fn has_tls_returns_true_when_all_tls_set_test() {
  let cfg =
    config.Config(
      host: "localhost",
      port: 7070,
      grpc_port: 7070,
      token: option.None,
      namespace: option.None,
      tls_ca: option.Some("/path/to/ca.pem"),
      tls_cert: option.Some("/path/to/cert.pem"),
      tls_key: option.Some("/path/to/key.pem"),
    )

  config.has_tls(cfg)
  |> should.be_true()
}

// ============================================================================
// EDGE CASE TESTS
// ============================================================================

pub fn from_dict_empty_string_token_is_some_test() {
  let values =
    dict.from_list([
      #("token", ""),
    ])

  let cfg = config.from_dict(values)

  cfg.token
  |> should.equal(option.Some(""))
}

pub fn from_dict_empty_string_host_test() {
  let values =
    dict.from_list([
      #("host", ""),
    ])

  let cfg = config.from_dict(values)

  cfg.host
  |> should.equal("")
}

pub fn from_dict_whitespace_token_preserved_test() {
  let values =
    dict.from_list([
      #("token", "   "),
    ])

  let cfg = config.from_dict(values)

  cfg.token
  |> should.equal(option.Some("   "))
}

pub fn from_dict_special_chars_namespace_preserved_test() {
  let values =
    dict.from_list([
      #("namespace", "tenant-123.env.prod"),
    ])

  let cfg = config.from_dict(values)

  cfg.namespace
  |> should.equal(option.Some("tenant-123.env.prod"))
}

// ============================================================================
// INTEGRATION TESTS
// ============================================================================

pub fn production_config_scenario_test() {
  let values =
    dict.from_list([
      #("host", "hatchet.production.example.com"),
      #("port", "443"),
      #("grpc_port", "7070"),
      #("token", "prod-token-abc123"),
      #("namespace", "production"),
      #("tls_ca", "/etc/ssl/hatchet/ca.pem"),
      #("tls_cert", "/etc/ssl/hatchet/client.prod.pem"),
      #("tls_key", "/etc/ssl/hatchet/client.prod.key.pem"),
    ])

  let cfg = config.from_dict(values)

  // Verify all fields
  cfg.host
  |> should.equal("hatchet.production.example.com")

  cfg.port
  |> should.equal(443)

  cfg.grpc_port
  |> should.equal(7070)

  cfg.token
  |> should.equal(option.Some("prod-token-abc123"))

  cfg.namespace
  |> should.equal(option.Some("production"))

  cfg.tls_ca
  |> should.equal(option.Some("/etc/ssl/hatchet/ca.pem"))

  cfg.tls_cert
  |> should.equal(option.Some("/etc/ssl/hatchet/client.prod.pem"))

  cfg.tls_key
  |> should.equal(option.Some("/etc/ssl/hatchet/client.prod.key.pem"))

  // Verify URL generation
  config.rest_url(cfg)
  |> should.equal("http://hatchet.production.example.com:443")

  config.grpc_url(cfg)
  |> should.equal("hatchet.production.example.com:7070")

  // Verify TLS detection
  config.has_tls(cfg)
  |> should.be_true()
}

pub fn development_config_scenario_test() {
  let values =
    dict.from_list([
      #("token", "dev-token"),
    ])

  let cfg = config.from_dict(values)

  // Host and ports use defaults
  cfg.host
  |> should.equal("localhost")

  cfg.port
  |> should.equal(7070)

  cfg.grpc_port
  |> should.equal(7070)

  // Token is set
  cfg.token
  |> should.equal(option.Some("dev-token"))

  // No TLS
  config.has_tls(cfg)
  |> should.be_false()
}

pub fn selective_override_maintains_defaults_test() {
  let values =
    dict.from_list([
      #("host", "custom-host"),
      #("token", "custom-token"),
      // port and grpc_port intentionally omitted
    ])

  let cfg = config.from_dict(values)

  cfg.host
  |> should.equal("custom-host")

  cfg.token
  |> should.equal(option.Some("custom-token"))

  // Defaults for omitted fields
  cfg.port
  |> should.equal(7070)

  cfg.grpc_port
  |> should.equal(7070)

  cfg.namespace
  |> should.equal(option.None)
}

// ============================================================================
// IMMUTABILITY TESTS
// ============================================================================

pub fn config_immutability_test() {
  let original =
    config.Config(
      host: "localhost",
      port: 7070,
      grpc_port: 7070,
      token: option.Some("token"),
      namespace: option.None,
      tls_ca: option.None,
      tls_cert: option.None,
      tls_key: option.None,
    )

  // Create a modified copy
  let modified =
    config.Config(
      host: "different-host",
      port: original.port,
      grpc_port: original.grpc_port,
      token: original.token,
      namespace: original.namespace,
      tls_ca: original.tls_ca,
      tls_cert: original.tls_cert,
      tls_key: original.tls_key,
    )

  // Original should be unchanged
  original.host
  |> should.equal("localhost")

  modified.host
  |> should.equal("different-host")
}
