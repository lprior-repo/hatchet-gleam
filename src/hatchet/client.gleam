import gleam/option
import hatchet/types.{type Client, type Worker, type WorkerConfig, type Workflow}

pub fn new(host: String, token: String) -> Result(Client, String) {
  Ok(types.create_client(host, 7070, token, option.None))
}

pub fn with_port(client: Client, port: Int) -> Client {
  types.create_client(
    types.get_host(client),
    port,
    types.get_token(client),
    types.get_namespace(client),
  )
}

pub fn with_namespace(client: Client, namespace: String) -> Client {
  types.create_client(
    types.get_host(client),
    types.get_port(client),
    types.get_token(client),
    option.Some(namespace),
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
