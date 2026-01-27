//// Worker Actor - Core worker process using gleam_otp
////
//// This module implements the main worker process that:
//// 1. Registers with the Hatchet dispatcher
//// 2. Listens for task assignments via gRPC streaming
//// 3. Executes task handlers
//// 4. Reports task status (started/completed/failed)
//// 5. Sends heartbeats to maintain the connection
////
//// The worker follows the Python SDK's architecture with:
//// - A main actor for coordination
//// - Separate processes for task execution
//// - Automatic reconnection with exponential backoff

import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import gleam/string
import hatchet/context.{type Context}
import hatchet/internal/ffi/protobuf
import hatchet/internal/ffi/timer
import hatchet/internal/grpc
import hatchet/internal/tls.{type TLSConfig, Insecure}
import hatchet/types.{
  type Client, type TaskDef, type Workflow, type WorkerConfig,
}

// ============================================================================
// Constants (matching Python SDK)
// ============================================================================

const heartbeat_interval_ms: Int = 4000

const max_heartbeat_failures: Int = 3

const max_reconnect_attempts: Int = 15

const recv_timeout_ms: Int = 30_000

const sdk_version: String = "0.1.0"

const gleam_version: String = "1.0.0"

// ============================================================================
// Worker Messages
// ============================================================================

pub type WorkerMessage {
  // Lifecycle
  Connect
  Reconnect(attempt: Int)
  Shutdown

  // Task handling
  TaskReceived(protobuf.AssignedAction)
  TaskCompleted(step_run_id: String, output: Dynamic)
  TaskFailed(step_run_id: String, error: String, should_retry: Bool)

  // Heartbeat
  SendHeartbeat
  HeartbeatSuccess
  HeartbeatFailed

  // Internal
  ListenLoop
  ListenError(String)
}

// ============================================================================
// Worker State
// ============================================================================

pub type WorkerState {
  WorkerState(
    // Configuration
    client: Client,
    config: WorkerConfig,
    host: String,
    grpc_port: Int,
    token: String,
    tls_config: TLSConfig,
    // Connection state
    channel: Option(grpc.Channel),
    stream: Option(grpc.Stream),
    worker_id: Option(String),
    // Workflow registry - maps action names to handlers
    action_registry: Dict(String, TaskHandler),
    // Running tasks
    running_tasks: Dict(String, Subject(TaskMessage)),
    available_slots: Int,
    // Health tracking
    heartbeat_failures: Int,
    reconnect_attempts: Int,
    is_running: Bool,
    // Self reference for scheduling
    self: Option(Subject(WorkerMessage)),
  )
}

pub type TaskHandler {
  TaskHandler(
    workflow_name: String,
    task_name: String,
    handler: fn(Context) -> Result(Dynamic, String),
    retries: Int,
  )
}

pub type TaskMessage {
  Execute
  Cancel
}

// ============================================================================
// Worker Creation
// ============================================================================

/// Start a new worker actor
pub fn start(
  client: Client,
  config: WorkerConfig,
  workflows: List(Workflow),
  grpc_port: Int,
) -> Result(Subject(WorkerMessage), actor.StartError) {
  let host = types.get_host(client)
  let token = types.get_token(client)

  // Build action registry from workflows
  let action_registry = build_action_registry(workflows)

  let initial_state =
    WorkerState(
      client: client,
      config: config,
      host: host,
      grpc_port: grpc_port,
      token: token,
      tls_config: Insecure,
      channel: None,
      stream: None,
      worker_id: None,
      action_registry: action_registry,
      running_tasks: dict.new(),
      available_slots: config.slots,
      heartbeat_failures: 0,
      reconnect_attempts: 0,
      is_running: False,
      self: None,
    )

  actor.start_spec(actor.Spec(
    init: fn() {
      // Get our own subject for scheduling
      let self = process.new_subject()

      // Schedule initial connection
      process.send(self, Connect)

      let state = WorkerState(..initial_state, self: Some(self), is_running: True)

      actor.Ready(state, process.new_selector())
    },
    init_timeout: 30_000,
    loop: handle_message,
  ))
}

/// Build the action registry from workflow definitions
fn build_action_registry(workflows: List(Workflow)) -> Dict(String, TaskHandler) {
  list.fold(workflows, dict.new(), fn(registry, workflow) {
    list.fold(workflow.tasks, registry, fn(reg, task) {
      // Action name format: workflow_name:task_name
      let action_name = workflow.name <> ":" <> task.name
      let handler =
        TaskHandler(
          workflow_name: workflow.name,
          task_name: task.name,
          handler: task.handler,
          retries: task.retries,
        )
      dict.insert(reg, action_name, handler)
    })
  })
}

// ============================================================================
// Message Handler
// ============================================================================

fn handle_message(
  msg: WorkerMessage,
  state: WorkerState,
) -> actor.Next(WorkerMessage, WorkerState) {
  case msg {
    Connect -> handle_connect(state)
    Reconnect(attempt) -> handle_reconnect(attempt, state)
    Shutdown -> handle_shutdown(state)
    TaskReceived(action) -> handle_task_received(action, state)
    TaskCompleted(step_run_id, output) ->
      handle_task_completed(step_run_id, output, state)
    TaskFailed(step_run_id, error, should_retry) ->
      handle_task_failed(step_run_id, error, should_retry, state)
    SendHeartbeat -> handle_send_heartbeat(state)
    HeartbeatSuccess -> handle_heartbeat_success(state)
    HeartbeatFailed -> handle_heartbeat_failed(state)
    ListenLoop -> handle_listen_loop(state)
    ListenError(err) -> handle_listen_error(err, state)
  }
}

// ============================================================================
// Connection Handling
// ============================================================================

fn handle_connect(state: WorkerState) -> actor.Next(WorkerMessage, WorkerState) {
  log_info("Connecting to Hatchet dispatcher at " <> state.host <> ":" <> int_to_string(state.grpc_port))

  // Connect to gRPC server
  case grpc.connect(state.host, state.grpc_port, state.tls_config, 30_000) {
    Ok(channel) -> {
      log_info("Connected to dispatcher, registering worker...")

      // Register the worker
      case register_worker(channel, state) {
        Ok(worker_id) -> {
          log_info("Worker registered with ID: " <> worker_id)

          // Start listening for tasks
          case grpc.listen_v2(channel, worker_id, state.token) {
            Ok(stream) -> {
              log_info("Started listening for task assignments")

              // Schedule heartbeat and listen loop
              schedule_message(state, SendHeartbeat, heartbeat_interval_ms)
              schedule_message(state, ListenLoop, 0)

              let new_state =
                WorkerState(
                  ..state,
                  channel: Some(channel),
                  stream: Some(stream),
                  worker_id: Some(worker_id),
                  reconnect_attempts: 0,
                  heartbeat_failures: 0,
                )

              actor.continue(new_state)
            }
            Error(e) -> {
              log_error("Failed to start listening: " <> e)
              grpc.close(channel)
              schedule_reconnect(state)
            }
          }
        }
        Error(e) -> {
          log_error("Failed to register worker: " <> e)
          grpc.close(channel)
          schedule_reconnect(state)
        }
      }
    }
    Error(e) -> {
      log_error("Failed to connect: " <> e)
      schedule_reconnect(state)
    }
  }
}

fn handle_reconnect(
  attempt: Int,
  state: WorkerState,
) -> actor.Next(WorkerMessage, WorkerState) {
  case attempt > max_reconnect_attempts {
    True -> {
      log_error("Max reconnection attempts reached, shutting down")
      actor.Stop(process.Normal)
    }
    False -> {
      // Exponential backoff: 1s, 2s, 4s, 8s... up to 30s
      let delay_ms = min(1000 * pow(2, attempt - 1), 30_000)
      log_info(
        "Reconnecting in "
        <> int_to_string(delay_ms)
        <> "ms (attempt "
        <> int_to_string(attempt)
        <> "/"
        <> int_to_string(max_reconnect_attempts)
        <> ")",
      )

      timer.sleep_ms(delay_ms)

      let new_state = WorkerState(..state, reconnect_attempts: attempt)
      handle_connect(new_state)
    }
  }
}

fn schedule_reconnect(
  state: WorkerState,
) -> actor.Next(WorkerMessage, WorkerState) {
  let attempt = state.reconnect_attempts + 1
  schedule_message(state, Reconnect(attempt), 100)
  actor.continue(WorkerState(..state, reconnect_attempts: attempt))
}

fn register_worker(
  channel: grpc.Channel,
  state: WorkerState,
) -> Result(String, String) {
  // Get list of action names
  let actions = dict.keys(state.action_registry)

  // Build runtime info
  let runtime_info =
    protobuf.RuntimeInfo(
      sdk_version: sdk_version,
      language: protobuf.Gleam,
      language_version: gleam_version,
      os: get_os_info(),
      extra: None,
    )

  // Build registration request
  let request =
    protobuf.WorkerRegisterRequest(
      worker_name: option.unwrap(state.config.name, "gleam-worker"),
      actions: actions,
      services: [],
      max_runs: Some(state.config.slots),
      labels: dict.new(),
      webhook_id: None,
      runtime_info: Some(runtime_info),
    )

  // Encode and send
  case protobuf.encode_worker_register_request(request) {
    Ok(encoded) -> {
      case grpc.register_worker(channel, encoded) {
        Ok(response) -> Ok(response.worker_id)
        Error(e) -> Error(e)
      }
    }
    Error(e) -> {
      case e {
        protobuf.ProtobufEncodeError(msg) -> Error("Encode error: " <> msg)
        protobuf.ProtobufDecodeError(msg) -> Error("Decode error: " <> msg)
      }
    }
  }
}

// ============================================================================
// Task Handling
// ============================================================================

fn handle_listen_loop(
  state: WorkerState,
) -> actor.Next(WorkerMessage, WorkerState) {
  case state.stream {
    Some(stream) -> {
      case grpc.recv_assigned_action(stream, recv_timeout_ms) {
        Ok(action) -> {
          // Process the received action
          case state.self {
            Some(self) -> process.send(self, TaskReceived(action))
            None -> Nil
          }

          // Continue listening
          schedule_message(state, ListenLoop, 0)
          actor.continue(state)
        }
        Error("timeout") -> {
          // Timeout is normal, continue listening
          schedule_message(state, ListenLoop, 0)
          actor.continue(state)
        }
        Error(e) -> {
          log_error("Listen error: " <> e)
          schedule_message(state, ListenError(e), 0)
          actor.continue(state)
        }
      }
    }
    None -> {
      // No stream, try to reconnect
      schedule_reconnect(state)
    }
  }
}

fn handle_listen_error(
  _error: String,
  state: WorkerState,
) -> actor.Next(WorkerMessage, WorkerState) {
  // Close existing connections and reconnect
  case state.stream {
    Some(stream) -> grpc.close_stream(stream)
    None -> Nil
  }
  case state.channel {
    Some(channel) -> grpc.close(channel)
    None -> Nil
  }

  let new_state =
    WorkerState(..state, channel: None, stream: None, worker_id: None)
  schedule_reconnect(new_state)
}

fn handle_task_received(
  action: protobuf.AssignedAction,
  state: WorkerState,
) -> actor.Next(WorkerMessage, WorkerState) {
  // Check if we have capacity
  case state.available_slots > 0 {
    True -> {
      // Find the handler for this action
      let action_name = action.step_name

      case dict.get(state.action_registry, action_name) {
        Some(handler) -> {
          log_info("Received task: " <> action_name)

          // Send ACKNOWLEDGED event
          send_task_event(
            state,
            action,
            protobuf.StepEventTypeAcknowledged,
            "{}",
          )

          // Execute the task (in the current process for now)
          // In production, this should spawn a separate process
          execute_task(action, handler, state)
        }
        None -> {
          // Also try with workflow:task format
          case find_handler_by_step(action.step_name, state.action_registry) {
            Some(handler) -> {
              log_info("Received task: " <> action.step_name)
              send_task_event(
                state,
                action,
                protobuf.StepEventTypeAcknowledged,
                "{}",
              )
              execute_task(action, handler, state)
            }
            None -> {
              log_error("No handler for action: " <> action_name)
              actor.continue(state)
            }
          }
        }
      }
    }
    False -> {
      log_warning("No available slots, task will be requeued")
      actor.continue(state)
    }
  }
}

fn find_handler_by_step(
  step_name: String,
  registry: Dict(String, TaskHandler),
) -> Option(TaskHandler) {
  // Search through registry for a matching task name
  dict.fold(registry, None, fn(acc, _key, handler) {
    case acc {
      Some(_) -> acc
      None ->
        case handler.task_name == step_name {
          True -> Some(handler)
          False -> None
        }
    }
  })
}

fn execute_task(
  action: protobuf.AssignedAction,
  handler: TaskHandler,
  state: WorkerState,
) -> actor.Next(WorkerMessage, WorkerState) {
  // Send STARTED event
  send_task_event(state, action, protobuf.StepEventTypeStarted, "{}")

  // Create context
  let log_fn = fn(msg: String) {
    log_info("[" <> action.step_name <> "] " <> msg)
  }

  let ctx =
    context.from_assigned_action(
      action,
      option.unwrap(state.worker_id, ""),
      dict.new(),
      log_fn,
    )

  // Execute the handler
  case handler.handler(ctx) {
    Ok(output) -> {
      // Encode output as JSON
      let output_json = encode_output(output)

      // Send COMPLETED event
      send_task_event(state, action, protobuf.StepEventTypeCompleted, output_json)

      log_info("Task completed: " <> action.step_name)
      actor.continue(state)
    }
    Error(error) -> {
      // Encode error
      let error_json = json.to_string(json.object([#("error", json.string(error))]))

      // Send FAILED event
      send_task_event(state, action, protobuf.StepEventTypeFailed, error_json)

      log_error("Task failed: " <> action.step_name <> " - " <> error)
      actor.continue(state)
    }
  }
}

fn send_task_event(
  state: WorkerState,
  action: protobuf.AssignedAction,
  event_type: protobuf.StepActionEventType,
  payload: String,
) -> Nil {
  case state.channel {
    Some(channel) -> {
      let event =
        protobuf.StepActionEvent(
          worker_id: option.unwrap(state.worker_id, ""),
          job_id: action.job_id,
          job_run_id: action.job_run_id,
          step_id: action.step_id,
          step_run_id: action.step_run_id,
          action_id: action.action_id,
          event_timestamp: current_time_ms(),
          event_type: event_type,
          event_payload: payload,
          retry_count: Some(action.retry_count),
          should_not_retry: None,
        )

      case grpc.send_step_action_event(channel, event, state.token) {
        Ok(_) -> Nil
        Error(e) -> log_error("Failed to send event: " <> e)
      }
    }
    None -> log_error("No channel to send event")
  }
}

fn handle_task_completed(
  step_run_id: String,
  _output: Dynamic,
  state: WorkerState,
) -> actor.Next(WorkerMessage, WorkerState) {
  // Remove from running tasks and free up a slot
  let new_running = dict.delete(state.running_tasks, step_run_id)
  let new_state =
    WorkerState(
      ..state,
      running_tasks: new_running,
      available_slots: state.available_slots + 1,
    )
  actor.continue(new_state)
}

fn handle_task_failed(
  step_run_id: String,
  _error: String,
  _should_retry: Bool,
  state: WorkerState,
) -> actor.Next(WorkerMessage, WorkerState) {
  // Remove from running tasks and free up a slot
  let new_running = dict.delete(state.running_tasks, step_run_id)
  let new_state =
    WorkerState(
      ..state,
      running_tasks: new_running,
      available_slots: state.available_slots + 1,
    )
  actor.continue(new_state)
}

// ============================================================================
// Heartbeat Handling
// ============================================================================

fn handle_send_heartbeat(
  state: WorkerState,
) -> actor.Next(WorkerMessage, WorkerState) {
  case state.channel, state.worker_id {
    Some(channel), Some(worker_id) -> {
      case grpc.send_heartbeat(channel, worker_id, state.token) {
        Ok(_) -> {
          schedule_message(state, HeartbeatSuccess, 0)
          actor.continue(state)
        }
        Error(_) -> {
          schedule_message(state, HeartbeatFailed, 0)
          actor.continue(state)
        }
      }
    }
    _, _ -> {
      // Not connected, skip heartbeat
      actor.continue(state)
    }
  }
}

fn handle_heartbeat_success(
  state: WorkerState,
) -> actor.Next(WorkerMessage, WorkerState) {
  // Reset failure count and schedule next heartbeat
  let new_state = WorkerState(..state, heartbeat_failures: 0)
  schedule_message(new_state, SendHeartbeat, heartbeat_interval_ms)
  actor.continue(new_state)
}

fn handle_heartbeat_failed(
  state: WorkerState,
) -> actor.Next(WorkerMessage, WorkerState) {
  let failures = state.heartbeat_failures + 1
  log_warning(
    "Heartbeat failed ("
    <> int_to_string(failures)
    <> "/"
    <> int_to_string(max_heartbeat_failures)
    <> ")",
  )

  case failures >= max_heartbeat_failures {
    True -> {
      log_error("Max heartbeat failures, reconnecting...")
      schedule_message(state, ListenError("heartbeat timeout"), 0)
      actor.continue(WorkerState(..state, heartbeat_failures: failures))
    }
    False -> {
      schedule_message(state, SendHeartbeat, heartbeat_interval_ms)
      actor.continue(WorkerState(..state, heartbeat_failures: failures))
    }
  }
}

// ============================================================================
// Shutdown
// ============================================================================

fn handle_shutdown(state: WorkerState) -> actor.Next(WorkerMessage, WorkerState) {
  log_info("Shutting down worker...")

  // Close stream and channel
  case state.stream {
    Some(stream) -> grpc.close_stream(stream)
    None -> Nil
  }
  case state.channel {
    Some(channel) -> grpc.close(channel)
    None -> Nil
  }

  actor.Stop(process.Normal)
}

// ============================================================================
// Utility Functions
// ============================================================================

fn schedule_message(state: WorkerState, msg: WorkerMessage, delay_ms: Int) -> Nil {
  case state.self {
    Some(self) -> {
      case delay_ms > 0 {
        True -> {
          // Use process.send_after for delayed messages
          process.send_after(self, delay_ms, msg)
          Nil
        }
        False -> {
          process.send(self, msg)
          Nil
        }
      }
    }
    None -> Nil
  }
}

fn encode_output(output: Dynamic) -> String {
  // Try to encode as JSON, fall back to string representation
  json.to_string(json.string(string.inspect(output)))
}

fn current_time_ms() -> Int {
  do_current_time_ms()
}

@external(erlang, "hatchet_time_ffi", "system_time_ms")
fn do_current_time_ms() -> Int

fn get_os_info() -> String {
  do_get_os_info()
}

@external(erlang, "hatchet_os_ffi", "get_os_info")
fn do_get_os_info() -> String

fn int_to_string(i: Int) -> String {
  do_int_to_string(i)
}

@external(erlang, "erlang", "integer_to_binary")
fn do_int_to_string(i: Int) -> String

fn pow(base: Int, exp: Int) -> Int {
  do_pow(base, exp)
}

@external(erlang, "math", "pow")
fn do_pow_float(base: Int, exp: Int) -> Float

fn do_pow(base: Int, exp: Int) -> Int {
  float_to_int(do_pow_float(base, exp))
}

@external(erlang, "erlang", "trunc")
fn float_to_int(f: Float) -> Int

fn min(a: Int, b: Int) -> Int {
  case a < b {
    True -> a
    False -> b
  }
}

// Logging helpers
fn log_info(msg: String) -> Nil {
  io.println("[INFO] " <> msg)
}

fn log_warning(msg: String) -> Nil {
  io.println("[WARN] " <> msg)
}

fn log_error(msg: String) -> Nil {
  io.println("[ERROR] " <> msg)
}
