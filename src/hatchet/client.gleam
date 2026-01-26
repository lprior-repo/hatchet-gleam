import gleam/option.{None, Some}
import hatchet/internal/config.{type Config, from_environment_checked, MissingTokenError}
import hatchet/types.{
  type Client, type Worker, type WorkerConfig, type Workflow,
}

/// Create a new Hatchet client with the given host and token.
///
/// The default REST API port (7070) is used. Use `with_port()` to specify
/// a custom port.
///
/// **Parameters:**
///   - `host`: The Hatchet server hostname (e.g., "localhost", "api.hatchet.run")
///   - `token`: The API authentication token
///
/// **Returns:** A configured `Client` wrapped in `Result`
///
/// **Examples:**
/// ```gleam
/// case client.new("localhost", "my-token") {
///   Ok(client) -> // Use client
///   Error(err) -> // Handle error
/// }
/// ```
pub fn new(host: String, token: String) -> Result(Client, String) {
  Ok(types.create_client(host, 7070, token, None))
}

/// Create a new Hatchet client from environment configuration.
///
/// This reads configuration from environment variables (see `hatchet/internal/config`)
/// and creates a client. The token is not required to be set, allowing flexibility
/// in test scenarios.
///
/// **Returns:** A configured `Client` if the token is present, otherwise an error
///
/// **Environment Variables:**
/// - `HATCHET_HOST` - Server hostname (default: "localhost")
/// - `HATCHET_PORT` - REST API port (default: 7070)
/// - `HATCHET_TOKEN` - API token (required)
/// - `HATCHET_NAMESPACE` - Tenant namespace (optional)
///
/// **Examples:**
/// ```gleam
/// // Set environment variables first:
/// // HATCHET_HOST=localhost HATCHET_TOKEN=my-token
///
/// case client.from_environment() {
///   Ok(client) -> // Use client
///   Error(err) -> // Handle error
/// }
/// ```
pub fn from_environment() -> Result(Client, String) {
  let cfg = from_environment_checked()
  case cfg {
    Ok(config) -> with_config(config)
    Error(MissingTokenError) -> Error("HATCHET_TOKEN environment variable is required")
    _ -> Error("Invalid configuration")
  }
}

/// Create a client from a Config record.
///
/// This allows programmatic configuration, useful for testing or when
/// configuration comes from sources other than environment variables.
///
/// **Parameters:**
///   - `config`: A `Config` from `hatchet/internal/config`
///
/// **Returns:** A configured `Client` if the token is present, otherwise an error
///
/// **Examples:**
/// ```gleam
/// import hatchet/internal/config
///
/// let cfg = config.Config(
///   host: "localhost",
///   port: 7070,
///   grpc_port: 7077,
///   token: option.Some("my-token"),
///   namespace: option.None,
///   tls_ca: option.None,
///   tls_cert: option.None,
///   tls_key: option.None,
/// )
/// case client.with_config(cfg) {
///   Ok(client) -> // Use client
///   Error(err) -> // Handle error
/// }
/// ```
pub fn with_config(config: Config) -> Result(Client, String) {
  case config.token {
    None -> Error("Token is required for client configuration")
    Some(token) ->
      Ok(types.create_client(
        config.host,
        config.port,
        token,
        config.namespace,
      ))
  }
}

/// Set a custom port for the client connection.
///
/// **Parameters:**
///   - `client`: The base client configuration
///   - `port`: The port number to connect to (typically 7070 for REST API)
///
/// **Returns:** A new `Client` with the updated port
///
/// **Examples:**
/// ```gleam
/// client.new("localhost", "token")
///   |> result.map(fn(c) { client.with_port(c, 8080) })
/// ```
pub fn with_port(client: Client, port: Int) -> Client {
  types.create_client(
    types.get_host(client),
    port,
    types.get_token(client),
    types.get_namespace(client),
  )
}

/// Set a namespace for the client connection.
///
/// Namespaces allow multi-tenancy by routing requests to a specific
/// tenant namespace.
///
/// **Parameters:**
///   - `client`: The base client configuration
///   - `namespace`: The namespace to route requests to
///
/// **Returns:** A new `Client` with the namespace configured
///
/// **Examples:**
/// ```gleam
/// client.new("localhost", "token")
///   |> result.map(fn(c) { client.with_namespace(c, "tenant-123") })
/// ```
pub fn with_namespace(client: Client, namespace: String) -> Client {
  types.create_client(
    types.get_host(client),
    types.get_port(client),
    types.get_token(client),
    Some(namespace),
  )
}

pub fn new_worker(
  client: Client,
  _config: WorkerConfig,
  _workflows: List(Workflow),
) -> Result(Worker, String) {
  Ok(types.create_worker("worker_" <> types.get_token(client)))
}

pub fn start_worker_blocking(_worker: Worker) -> Result(Nil, String) {
  Ok(Nil)
}

pub fn start_worker(_worker: Worker) -> Result(fn() -> Nil, String) {
  Ok(fn() { Nil })
}
