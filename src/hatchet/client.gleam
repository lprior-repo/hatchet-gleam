import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import hatchet/internal/config.{
  type Config, MissingTokenError, from_environment_checked,
}
import hatchet/internal/worker_actor.{type WorkerMessage}
import hatchet/types.{type Client, type Worker, type WorkerConfig, type Workflow}

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
    Error(MissingTokenError) ->
      Error("HATCHET_TOKEN environment variable is required")
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
      Ok(types.create_client(config.host, config.port, token, config.namespace))
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

/// Create a new worker configuration with sensible defaults.
///
/// **Parameters:**
///   - `name`: Optional worker name (defaults to auto-generated)
///   - `slots`: Number of concurrent task slots (default: 10)
///
/// **Returns:** A `WorkerConfig` ready for use with `new_worker`
pub fn worker_config(name: Option(String), slots: Int) -> WorkerConfig {
  types.WorkerConfig(
    name: name,
    slots: slots,
    durable_slots: 0,
    labels: dict.new(),
  )
}

/// Default worker configuration with 10 slots.
pub fn default_worker_config() -> WorkerConfig {
  worker_config(None, 10)
}

/// Create a new worker that will process tasks for the given workflows.
///
/// The worker connects to the Hatchet dispatcher via gRPC and listens
/// for task assignments. When a task is received, the appropriate
/// handler from the registered workflows is invoked.
///
/// **Parameters:**
///   - `client`: The Hatchet client
///   - `config`: Worker configuration (slots, name, etc.)
///   - `workflows`: List of workflows this worker can process
///
/// **Returns:** `Ok(Worker)` on success, `Error(String)` on failure
///
/// **Example:**
/// ```gleam
/// let config = client.worker_config(Some("my-worker"), 5)
/// case client.new_worker(client, config, [my_workflow]) {
///   Ok(worker) -> client.start_worker_blocking(worker)
///   Error(e) -> io.println("Failed: " <> e)
/// }
/// ```
pub fn new_worker(
  client: Client,
  config: WorkerConfig,
  workflows: List(Workflow),
) -> Result(Worker, String) {
  new_worker_with_grpc_port(client, config, workflows, 7077)
}

/// Create a new worker with a custom gRPC port.
///
/// Use this when the dispatcher is running on a non-standard port.
pub fn new_worker_with_grpc_port(
  client: Client,
  config: WorkerConfig,
  workflows: List(Workflow),
  grpc_port: Int,
) -> Result(Worker, String) {
  case worker_actor.start(client, config, workflows, grpc_port) {
    Ok(subject) -> Ok(types.create_worker_with_subject(subject))
    Error(e) -> Error("Failed to start worker: " <> actor_error_to_string(e))
  }
}

fn actor_error_to_string(error: actor.StartError) -> String {
  case error {
    actor.InitTimeout -> "Init timeout"
    actor.InitFailed(_) -> "Init failed"
    actor.InitCrashed(_) -> "Init crashed"
  }
}

/// Start the worker and block until it shuts down.
///
/// This is the main entry point for running a worker. The function
/// will block indefinitely, processing tasks as they are assigned.
///
/// **Parameters:**
///   - `worker`: The worker to start
///
/// **Returns:** `Ok(Nil)` when the worker shuts down gracefully
///
/// **Example:**
/// ```gleam
/// case client.start_worker_blocking(worker) {
///   Ok(_) -> io.println("Worker shut down")
///   Error(e) -> io.println("Worker error: " <> e)
/// }
/// ```
pub fn start_worker_blocking(worker: Worker) -> Result(Nil, String) {
  // The worker is already running when created
  // This function monitors it and blocks until it exits
  case types.get_worker_pid(worker) {
    Some(pid) -> {
      // Monitor the worker process and block until it exits
      let monitor = process.monitor_process(pid)
      let selector =
        process.new_selector()
        |> process.selecting_process_down(monitor, fn(_down) { Nil })
      process.select_forever(selector)
      Ok(Nil)
    }
    None -> Error("Worker not properly initialized")
  }
}

/// Start the worker in the background and return a shutdown function.
///
/// Use this when you need to run the worker alongside other code.
///
/// **Parameters:**
///   - `worker`: The worker to start
///
/// **Returns:** `Ok(shutdown_fn)` where `shutdown_fn` stops the worker
pub fn start_worker(worker: Worker) -> Result(fn() -> Nil, String) {
  case types.get_worker_pid(worker) {
    Some(pid) -> {
      // Return a shutdown function
      Ok(fn() {
        send_to_pid(pid, worker_actor.Shutdown)
        Nil
      })
    }
    None -> Error("Worker not properly initialized")
  }
}

/// Stop a running worker gracefully.
///
/// This sends a shutdown signal to the worker, allowing it to
/// complete any in-flight tasks before terminating.
pub fn stop_worker(worker: Worker) -> Nil {
  case types.get_worker_pid(worker) {
    Some(pid) -> {
      send_to_pid(pid, worker_actor.Shutdown)
      Nil
    }
    None -> Nil
  }
}

/// Send a message to a process by Pid.
/// This is used to avoid circular type dependencies between types.gleam
/// and worker_actor.gleam. The message type is erased at runtime on BEAM.
@external(erlang, "erlang", "send")
fn send_to_pid(pid: process.Pid, message: a) -> a
