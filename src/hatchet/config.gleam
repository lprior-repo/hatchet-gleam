import gleam/option.{type Option}
import hatchet/types.{type Client}

/// Client configuration loaded from file or environment.
pub type Config {
  Config(
    host: String,
    port: Int,
    token: String,
    tenant_id: String,
    namespace: Option(String),
    tls_config: Option(TlsConfig),
  )
}

/// TLS configuration options.
pub type TlsConfig {
  TlsConfig(
    ca_cert_path: Option(String),
    ca_cert_dir: Option(String),
    verify_host: Bool,
    verify_peer: Bool,
  )
}

/// Convert loaded configuration to a Client.
///
/// This maps the Config type to the Client type used
/// throughout the SDK.
pub fn to_client(config: Config) -> Client {
  types.create_client_with_tenant_id(
    config.host,
    config.port,
    config.token,
    config.tenant_id,
    config.namespace,
  )
}

/// Load client configuration from a YAML file.
///
/// For now, this is a simple placeholder that requires
/// the user to manually construct the Client. Full YAML/TOML
/// parsing requires external dependencies which would increase
/// project complexity.
///
/// ## Example
///
/// ```gleam
/// case config.from_yaml("hatchet.yaml") {
///   Ok(config) -> config.to_client(config)
///   Error(e) -> io.println(e)
/// }
/// ```
///
/// ## Note
/// For production use, consider using the existing
/// internal/config.gleam environment-based configuration, which
/// provides better integration with deployment tools.
pub fn from_yaml(path: String) -> Result(Config, String) {
  case read_file(path) {
    Ok(_contents) -> Error("YAML config parsing requires external dependency")
    Error(e) -> Error("Failed to read config file: " <> e)
  }
}

/// Load client configuration from a TOML file.
///
/// For now, this is a simple placeholder that requires
/// the user to manually construct the Client. Full YAML/TOML
/// parsing requires external dependencies which would increase
/// project complexity.
///
/// ## Example
///
/// ```gleam
/// case config.from_toml("hatchet.toml") {
///   Ok(config) -> config.to_client(config)
///   Error(e) -> io.println(e)
/// }
/// ```
///
/// ## Note
/// For production use, consider using the existing
/// internal/config.gleam environment-based configuration, which
/// provides better integration with deployment tools.
pub fn from_toml(path: String) -> Result(Config, String) {
  case read_file(path) {
    Ok(_contents) -> Error("TOML config parsing requires external dependency")
    Error(e) -> Error("Failed to read config file: " <> e)
  }
}

fn read_file(path: String) -> Result(String, String) {
  Error("File reading not implemented: " <> path)
}
