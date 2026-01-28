////!
////| `HATCHET_NAMESPACE` | Tenant namespace | `None` | No |
//// Configuration loaded from environment variables.
////
//// This type encapsulates all configuration that can be loaded from the
//// environment. It provides type-safe access to configuration values.
////
//// ## Fields
////
//// - `host`: The Hatchet server hostname (from `HATCHET_HOST`, default: "localhost")
//// - `port`: The REST API port (from `HATCHET_PORT`, default: 7070)
//// - `grpc_port`: The gRPC dispatcher port (from `HATCHET_GRPC_PORT`, default: 7070)
//// - `token`: The API authentication token (from `HATCHET_TOKEN`)
//// - `namespace`: Optional tenant namespace (from `HATCHET_NAMESPACE`)
//// - `tls_ca`: Path to CA certificate for TLS (from `HATCHET_TLS_CA`)
//// - `tls_cert`: Path to client certificate for mTLS (from `HATCHET_TLS_CERT`)
//// - `tls_key`: Path to client private key for mTLS (from `HATCHET_TLS_KEY`)
////
//// ## Validation
////
//// The `token` field may be `None` when using `from_environment()` for
//// flexibility in testing. Use `from_environment_checked()` to enforce
//// that a token is present.
//// Error type for configuration loading failures.
////
//// These errors indicate missing or invalid configuration values.
//// Load configuration from environment variables.
////
//// This reads all supported environment variables and constructs a `Config`.
//// Default values are used where applicable. The token is optional to support
//// testing scenarios - use `from_environment_checked()` to enforce token presence.
////
//// **Returns:** A `Config` with values from environment
////
//// **Environment Variables Read:**
//// - `HATCHET_HOST` - Server hostname (default: "localhost")
//// - `HATCHET_PORT` - REST API port (default: 7070)
//// - `HATCHET_GRPC_PORT` - gRPC port (default: 7070)
//// - `HATCHET_TOKEN` - API token (optional)
//// - `HATCHET_NAMESPACE` - Tenant namespace (optional)
//// - `HATCHET_TLS_CA` - CA certificate path (optional)
//// - `HATCHET_TLS_CERT` - Client certificate path (optional)
//// - `HATCHET_TLS_KEY` - Client private key path (optional)
////
//// **Examples:**
//// ```gleam
//// // Basic usage - accepts missing token
//// let cfg = config.from_environment()
//// ```
////
//// **See also:** `from_environment_checked()` for strict validation
//// Load configuration from environment with validation.
////
//// This is a stricter variant of `from_environment()` that returns a `Result`
//// and requires the `HATCHET_TOKEN` to be set. Use this in production code
//// to fail fast when authentication is not configured.
////
//// **Returns:** `Ok(Config)` if all required values are present, `Error(ConfigError)` otherwise
////
//// **Errors:**
//// - `MissingTokenError` - When `HATCHET_TOKEN` is not set
//// - `InvalidPortError` - When a port value cannot be parsed
////
//// **Examples:**
//// ```gleam
//// case config.from_environment_checked() {
////   Ok(cfg) -> {
////     let client = client.with_config(cfg)
////     // ...
////   }
////   Error(MissingTokenError) -> {
////     io.println("HATCHET_TOKEN environment variable is required")
////   }
////   Error(_) -> {
////     io.println("Invalid configuration")
////   }
//// }
//// ```
//// Load configuration from a dictionary of values.
////
//// This allows injecting configuration values programmatically, useful for
//// testing or when configuration comes from a source other than environment
//// variables.
////
//// **Parameters:**
//// - `values`: A dictionary of configuration keys to values
////
//// **Returns:** A `Config` with the provided values, using defaults for missing keys
////
//// **Supported Keys:**
//// - `"host"` - Server hostname
//// - `"port"` - REST API port
//// - `"grpc_port"` - gRPC port
//// - `"token"` - API token
//// - `"namespace"` - Tenant namespace
//// - `"tls_ca"` - CA certificate path
//// - `"tls_cert"` - Client certificate path
//// - `"tls_key"` - Client private key path
////
//// **Examples:**
//// ```gleam
//// let cfg =
////   dict.from_list([
////     #("host", "hatchet.example.com"),
////     #("token", "my-secret-token"),
////   ])
////   |> config.from_dict()
//// ```
//// Get the default HTTP/HTTPS REST API URL for this configuration.
////
//// Returns the base URL for REST API calls based on the configured host
//// and port. TLS configuration is NOT considered - use `grpc_url()` for
//// the gRPC endpoint.
////
//// **Examples:**
//// ```gleam
//// let cfg = config.from_environment()
//// let base_url = config.rest_url(cfg)  // "http://localhost:7070"
//// ```
//// Get the default gRPC URL for this configuration.
////
//// Returns the gRPC dispatcher URL based on the configured host and
//// gRPC port. This does NOT include TLS/mTLS configuration which must
//// be applied separately when establishing the connection.
////
//// **Examples:**
//// ```gleam
//// let cfg = config.from_environment()
//// let grpc = config.grpc_url(cfg)  // "localhost:7070"
//// ```
//// Check if this configuration has TLS/mTLS certificates configured.
////
//// Returns `True` if any TLS certificate paths are set. This is a hint
//// to the connection layer about whether to attempt a TLS connection.
////
//// **Return Values:**
//// - `True` - CA cert, client cert, or client key is set
//// - `False` - No TLS configuration present
////
//// **Examples:**
//// ```gleam
//// let cfg = config.from_environment()
//// case config.has_tls(cfg) {
////   True -> "Using TLS connection"
////   False -> "Using insecure connection"
//// }
//// ```

//! This module provides environment-based configuration loading for the Hatchet SDK.
//! It follows the 12-factor app principles, reading configuration from environment
//! variables at runtime.
//!
//! ## Environment Variables
//!
//! | Variable | Description | Default | Required |
//! |----------|-------------|---------|----------|
//! | `HATCHET_HOST` | Hatchet server hostname | `localhost` | No |
//! | `HATCHET_PORT` | Hatchet REST API port | `7070` | No |
//! | `HATCHET_TOKEN` | API authentication token | - | Yes* |
//! | `HATCHET_GRPC_PORT` | gRPC dispatcher port | `7070` | No |
//! | `HATCHET_TLS_CA` | Path to CA certificate | `None` | No |
//! | `HATCHET_TLS_CERT` | Path to client certificate | `None` | No |
//! | `HATCHET_TLS_KEY` | Path to client private key | `None` | No |
//!
//! *Token is required when using `from_environment()` without overrides.
//!
//! ## Usage
//!
//! ```gleam
//! import hatchet/internal/config
//! import hatchet/client
//!
//! // Load all config from environment
//! case config.from_environment() {
//!   Ok(cfg) -> client.with_config(cfg)
//!   Error(e) -> io.println("Config error: " <> e)
//! }
//!
//! // Load with required token check
//! case config.from_environment_checked() {
//!   Ok(cfg) -> client.with_config(cfg)
//!   Error(e) -> io.println("Missing: " <> e)
//! }
//! ```

/// Configuration Module
///
import envoy
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

pub type Config {
  Config(
    host: String,
    port: Int,
    grpc_port: Int,
    token: Option(String),
    namespace: Option(String),
    tls_ca: Option(String),
    tls_cert: Option(String),
    tls_key: Option(String),
  )
}

pub type ConfigError {
  MissingTokenError
  InvalidPortError(String)
  InvalidTLSError(String)
}

pub fn from_environment() -> Config {
  Config(
    host: get_env_or_default("HATCHET_HOST", "localhost"),
    port: parse_port(get_env("HATCHET_PORT"), 7070),
    grpc_port: parse_port(get_env("HATCHET_GRPC_PORT"), 7070),
    // Default is 7070 for gRPC
    // Try HATCHET_CLIENT_TOKEN as fallback (Docker uses this name)
    token: get_env_with_fallback("HATCHET_TOKEN", "HATCHET_CLIENT_TOKEN"),
    namespace: get_env("HATCHET_NAMESPACE"),
    tls_ca: get_env("HATCHET_TLS_CA"),
    tls_cert: get_env("HATCHET_TLS_CERT"),
    tls_key: get_env("HATCHET_TLS_KEY"),
  )
}

pub fn from_environment_checked() -> Result(Config, ConfigError) {
  let cfg = from_environment()
  case cfg.token {
    None -> Error(MissingTokenError)
    Some(_) -> Ok(cfg)
  }
}

pub fn from_dict(values: dict.Dict(String, String)) -> Config {
  Config(
    host: dict.get(values, "host")
      |> result.unwrap("localhost"),
    port: dict.get(values, "port")
      |> result.map(parse_int_port)
      |> result.unwrap(7070),
    grpc_port: dict.get(values, "grpc_port")
      |> result.map(parse_int_port)
      |> result.unwrap(7070),
    token: result_to_option(dict.get(values, "token")),
    namespace: result_to_option(dict.get(values, "namespace")),
    tls_ca: result_to_option(dict.get(values, "tls_ca")),
    tls_cert: result_to_option(dict.get(values, "tls_cert")),
    tls_key: result_to_option(dict.get(values, "tls_key")),
  )
}

// Helper to convert Result to Option for dict.get results
fn result_to_option(result: Result(a, e)) -> Option(a) {
  case result {
    Ok(value) -> Some(value)
    Error(_) -> None
  }
}

pub fn rest_url(config: Config) -> String {
  "http://" <> config.host <> ":" <> int.to_string(config.port)
}

pub fn grpc_url(config: Config) -> String {
  config.host <> ":" <> int.to_string(config.grpc_port)
}

pub fn has_tls(config: Config) -> Bool {
  list.any([config.tls_ca, config.tls_cert, config.tls_key], fn(field) {
    case field {
      None -> False
      Some(_) -> True
    }
  })
}

// ============================================================================
// INTERNAL HELPERS
// ============================================================================

fn get_env(key: String) -> Option(String) {
  case envoy.get(key) {
    Ok(value) -> Some(value)
    Error(_) -> None
  }
}

fn get_env_with_fallback(key: String, fallback_key: String) -> Option(String) {
  case get_env(key) {
    Some(value) -> Some(value)
    None -> get_env(fallback_key)
  }
}

fn get_env_or_default(key: String, default: String) -> String {
  case get_env(key) {
    None -> default
    Some(value) -> value
  }
}

fn parse_port(maybe_port: Option(String), default: Int) -> Int {
  case maybe_port {
    None -> default
    Some(port_str) -> {
      case int.parse(port_str) {
        Ok(port) if port > 0 && port <= 65_535 -> port
        _ -> default
      }
    }
  }
}

fn parse_int_port(port_str: String) -> Int {
  case int.parse(port_str) {
    Ok(port) if port > 0 && port <= 65_535 -> port
    _ -> 7070
  }
}

import gleam/dict
