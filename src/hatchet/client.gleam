import gleam/dict
import gleam/erlang/process
import gleam/http
import gleam/http/request
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import hatchet/errors
import hatchet/internal/config.{
  type Config, MissingTokenError, from_environment_checked,
}
import hatchet/internal/http as h
import hatchet/internal/http_client.{type HttpClient}
import hatchet/internal/json as j
import hatchet/internal/protocol as p
import hatchet/internal/tls
import hatchet/internal/worker_actor
import hatchet/run
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

/// Create a worker directly from a Config record.
///
/// This is a convenience function that extracts TLS configuration from the
/// Config and passes it to the worker. Use this when you have a Config
/// from `config.from_environment()` or `config.from_dict()`.
///
/// **Parameters:**
///   - `config`: A `Config` from `hatchet/internal/config`
///   - `worker_config`: Worker configuration (slots, name, etc.)
///   - `workflows`: List of workflows this worker can process
///
/// **Returns:** `Ok(Worker)` on success, `Error(String)` on failure
///
/// **Examples:**
/// ```gleam
/// import hatchet/internal/config
///
/// let cfg = config.from_environment()
/// let worker_cfg = client.worker_config(Some("my-worker"), 5)
/// case client.new_worker_from_config(cfg, worker_cfg, [my_workflow]) {
///   Ok(worker) -> client.start_worker_blocking(worker)
///   Error(e) -> io.println("Failed: " <> e)
/// }
/// ```
pub fn new_worker_from_config(
  config: Config,
  worker_config: WorkerConfig,
  workflows: List(Workflow),
) -> Result(Worker, String) {
  case config.token {
    None -> Error("Token is required for worker configuration")
    Some(token) -> {
      let client =
        types.create_client(config.host, config.port, token, config.namespace)
      let tls_config =
        tls.from_parts(config.tls_ca, config.tls_cert, config.tls_key)
      case tls_config {
        Ok(tls_cfg) ->
          new_worker_with_grpc_port(
            client,
            worker_config,
            workflows,
            config.grpc_port,
            Some(tls_cfg),
          )
        Error(e) ->
          Error("Invalid TLS configuration: " <> tls_error_to_string(e))
      }
    }
  }
}

/// Create a client with TLS encryption and server verification.
///
/// Use this for production connections where you want encrypted communication
/// with server certificate verification. You must provide a path to the CA
/// certificate that signed the server's certificate.
///
/// **Parameters:**
///   - `client`: The base client configuration
///   - `ca_path`: Path to the CA certificate file for server verification
///
/// **Returns:** A new `Client` with TLS enabled
///
/// **Examples:**
/// ```gleam
/// client.new("api.hatchet.run", "token")
///   |> result.map(fn(c) { client.with_tls(c, "/etc/ssl/certs/ca.pem") })
/// ```
pub fn with_tls(client: Client, ca_path: String) -> Client {
  let tls_config = tls.Tls(ca_path: ca_path)
  types.create_client_with_tls(
    types.get_host(client),
    types.get_port(client),
    types.get_token(client),
    types.get_namespace(client),
    tls_config,
  )
}

/// Create a client with mutual TLS (mTLS) authentication.
///
/// Use this for production connections requiring both server and client
/// certificate verification. You must provide paths to:
/// - The CA certificate (verifies the server)
/// - The client certificate (authenticates the client)
/// - The client private key (signs the client handshake)
///
/// **Parameters:**
///   - `client`: The base client configuration
///   - `ca_path`: Path to the CA certificate file
///   - `cert_path`: Path to the client certificate file
///   - `key_path`: Path to the client private key file
///
/// **Returns:** A new `Client` with mTLS enabled
///
/// **Examples:**
/// ```gleam
/// client.new("api.hatchet.run", "token")
///   |> result.map(fn(c) {
///     client.with_mtls(
///       c,
///       "/etc/ssl/certs/ca.pem",
///       "/etc/hatchet/client.pem",
///       "/etc/hatchet/client-key.pem",
///     )
///   })
/// ```
pub fn with_mtls(
  client: Client,
  ca_path: String,
  cert_path: String,
  key_path: String,
) -> Client {
  let tls_config =
    tls.Mtls(ca_path: ca_path, cert_path: cert_path, key_path: key_path)
  types.create_client_with_tls(
    types.get_host(client),
    types.get_port(client),
    types.get_token(client),
    types.get_namespace(client),
    tls_config,
  )
}

/// Create a client with insecure (no TLS) connection.
///
/// This explicitly sets the client to use plain HTTP/gRPC without encryption.
/// Only use this for local development and testing. Never use in production.
///
/// **Parameters:**
///   - `client`: The base client configuration
///
/// **Returns:** A new `Client` with insecure mode enabled
///
/// **Examples:**
/// ```gleam
/// // For local development
/// client.new("localhost", "dev-token")
///   |> result.map(fn(c) { client.with_insecure(c) })
/// ```
pub fn with_insecure(client: Client) -> Client {
  types.create_client_with_tls(
    types.get_host(client),
    types.get_port(client),
    types.get_token(client),
    types.get_namespace(client),
    tls.Insecure,
  )
}

fn tls_error_to_string(err: tls.TLSConfigError) -> String {
  case err {
    tls.MissingCA -> "TLS requires CA certificate"
    tls.MissingCert -> "mTLS requires client certificate"
    tls.MissingKey -> "mTLS requires client private key"
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

/// Register a workflow with the Hatchet server via REST API.
///
/// **Parameters:**
///   - `client`: The Hatchet client
///   - `workflow`: The workflow to register
///
/// **Returns:** `Ok(Nil)` on success, `Error(String)` on failure
///
/// **Examples:**
/// ```gleam
/// let workflow = workflow.new("my-workflow")
///   |> workflow.task("my-task", fn(ctx) { Ok(dynamic.string("done")) })
///
/// case client.register_workflow(client, workflow) {
///   Ok(_) -> io.println("Workflow registered")
///   Error(e) -> io.println("Failed: " <> e)
/// }
/// ```
pub fn register_workflow(
  client: Client,
  workflow: Workflow,
) -> Result(Nil, String) {
  register_workflow_with_http(client, workflow, http_client.real_http_client())
}

/// Register a workflow with an injected HTTP client.
///
/// This is the internal version that accepts an HttpClient for testing.
///
/// **Parameters:**
///   - `client`: The Hatchet client
///   - `workflow`: The workflow to register
///   - `http`: The HTTP client to use for requests
///
/// **Returns:** `Ok(Nil)` on success, `Error(String)` on failure
pub fn register_workflow_with_http(
  client: Client,
  workflow: Workflow,
  http: HttpClient,
) -> Result(Nil, String) {
  let protocol_req = run.convert_workflow_to_protocol_for_test(workflow)
  let req_body = j.encode_workflow_create(protocol_req)
  let base_url = h.build_base_url(client)
  let url = base_url <> "/api/v1/tenants/default/workflows"

  case h.make_authenticated_request(client, url, option.Some(req_body)) {
    Ok(req) -> {
      case http_client.send(http, req) {
        Ok(resp) if resp.status == 200 || resp.status == 201 -> Ok(Nil)
        Ok(resp) -> {
          Error(
            errors.to_simple_string(errors.api_http_error(
              resp.status,
              resp.body,
            )),
          )
        }
        Error(_) -> Error(errors.to_simple_string(errors.network_error("")))
      }
    }
    Error(e) -> Error(e)
  }
}

/// Register multiple workflows at once.
///
/// **Parameters:**
///   - `client`: The Hatchet client
///   - `workflows`: List of workflows to register
///
/// **Returns:** `Ok(Nil)` on success, `Error(String)` on failure
pub fn register_workflows(
  client: Client,
  workflows: List(Workflow),
) -> Result(Nil, String) {
  case workflows {
    [] -> Ok(Nil)
    [workflow, ..rest] -> {
      case register_workflow(client, workflow) {
        Ok(_) -> register_workflows(client, rest)
        Error(e) -> Error(e)
      }
    }
  }
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
  new_worker_with_grpc_port(client, config, workflows, 7077, None)
}

/// Create a new worker with a custom gRPC port.
///
/// Use this when the dispatcher is running on a non-standard port.
///
/// **Parameters:**
///   - `client`: The Hatchet client
///   - `config`: Worker configuration (slots, name, etc.)
///   - `workflows`: List of workflows this worker can process
///   - `grpc_port`: The gRPC dispatcher port
///   - `tls_config`: Optional TLS/mTLS configuration
///
/// **Returns:** `Ok(Worker)` on success, `Error(String)` on failure
pub fn new_worker_with_grpc_port(
  client: Client,
  config: WorkerConfig,
  workflows: List(Workflow),
  grpc_port: Int,
  tls_config: Option(tls.TLSConfig),
) -> Result(Worker, String) {
  case worker_actor.start(client, config, workflows, grpc_port, tls_config) {
    Ok(subject) -> Ok(types.create_worker_with_subject(subject))
    Error(e) -> Error("Failed to start worker: " <> actor_error_to_string(e))
  }
}

fn actor_error_to_string(error: actor.StartError) -> String {
  case error {
    actor.InitTimeout -> "Init timeout"
    actor.InitFailed(_) -> "Init failed"
    actor.InitExited(_) -> "Init exited"
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
      let monitor = process.monitor(pid)
      let selector =
        process.new_selector()
        |> process.select_specific_monitor(monitor, fn(_down) { Nil })
      process.selector_receive_forever(selector)
      Ok(Nil)
    }
    None ->
      Error(
        errors.to_simple_string(errors.network_error("Worker not initialized")),
      )
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
    None ->
      Error(
        errors.to_simple_string(errors.network_error("Worker not initialized")),
      )
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

/// Pause a worker, stopping it from accepting new tasks.
///
/// Existing in-progress tasks will complete, but no new tasks
/// will be assigned until the worker is resumed.
///
/// ## Example
///
/// ```gleam
/// case worker.pause(worker, client) {
///   Ok(Nil) -> io.println("Worker paused")
///   Error(e) -> io.println(e)
/// }
/// ```
pub fn pause_worker(worker: Worker, client: Client) -> Result(Nil, String) {
  pause_worker_with_http(worker, client, http_client.real_http_client())
}

/// Pause a worker with an injected HTTP client.
///
/// This is the internal version that accepts an HttpClient for testing.
///
/// **Parameters:**
///   - `worker`: The worker to pause
///   - `client`: The Hatchet client
///   - `http`: The HTTP client to use for requests
///
/// **Returns:** `Ok(Nil)` on success, `Error(String)` on failure
pub fn pause_worker_with_http(
  worker: Worker,
  client: Client,
  http: HttpClient,
) -> Result(Nil, String) {
  let worker_id = types.get_worker_id(worker)
  let url = h.build_base_url(client) <> "/workers/" <> worker_id <> "/pause"

  case h.make_authenticated_request(client, url, option.None) {
    Ok(req) -> {
      let req =
        req
        |> request.set_method(http.Post)
        |> request.set_body(
          j.encode_worker_pause(p.WorkerPauseRequest(worker_id: worker_id)),
        )
        |> request.set_header("content-type", "application/json")

      case http_client.send(http, req) {
        Ok(resp) if resp.status == 200 || resp.status == 204 -> Ok(Nil)
        Ok(resp) ->
          Error(
            errors.to_simple_string(errors.api_http_error(
              resp.status,
              resp.body,
            )),
          )
        Error(_) -> Error(errors.to_simple_string(errors.network_error("")))
      }
    }
    Error(e) -> Error(e)
  }
}

/// Resume a paused worker, allowing it to accept new tasks.
///
/// The worker will begin receiving new task assignments
/// from the Hatchet orchestrator.
///
/// ## Example
///
/// ```gleam
/// case worker.resume(worker, client) {
///   Ok(Nil) -> io.println("Worker resumed")
///   Error(e) -> io.println(e)
/// }
/// ```
pub fn resume_worker(worker: Worker, client: Client) -> Result(Nil, String) {
  resume_worker_with_http(worker, client, http_client.real_http_client())
}

/// Resume a worker with an injected HTTP client.
///
/// This is the internal version that accepts an HttpClient for testing.
///
/// **Parameters:**
///   - `worker`: The worker to resume
///   - `client`: The Hatchet client
///   - `http`: The HTTP client to use for requests
///
/// **Returns:** `Ok(Nil)` on success, `Error(String)` on failure
pub fn resume_worker_with_http(
  worker: Worker,
  client: Client,
  http: HttpClient,
) -> Result(Nil, String) {
  let worker_id = types.get_worker_id(worker)
  let url = h.build_base_url(client) <> "/workers/" <> worker_id <> "/resume"

  case h.make_authenticated_request(client, url, option.None) {
    Ok(req) -> {
      let req =
        req
        |> request.set_method(http.Post)
        |> request.set_body(
          j.encode_worker_resume(p.WorkerResumeRequest(worker_id: worker_id)),
        )
        |> request.set_header("content-type", "application/json")

      case http_client.send(http, req) {
        Ok(resp) if resp.status == 200 || resp.status == 204 -> Ok(Nil)
        Ok(resp) ->
          Error(
            errors.to_simple_string(errors.api_http_error(
              resp.status,
              resp.body,
            )),
          )
        Error(_) -> Error(errors.to_simple_string(errors.network_error("")))
      }
    }
    Error(e) -> Error(e)
  }
}

/// Send a message to a process by Pid.
/// This is used to avoid circular type dependencies between types.gleam
/// and worker_actor.gleam. The message type is erased at runtime on BEAM.
@external(erlang, "erlang", "send")
fn send_to_pid(pid: process.Pid, message: a) -> a
