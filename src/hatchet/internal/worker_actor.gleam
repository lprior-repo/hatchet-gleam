//// Worker Actor - Core worker process using gleam_otp
////
//// This module implements the main worker process that:
//// 1. Registers with the Hatchet dispatcher
//// 2. Listens for task assignments via gRPC streaming
//// 3. Executes task handlers in isolated processes
//// 4. Reports task status (started/completed/failed)
//// 5. Sends heartbeats to maintain the connection
////
//// Architecture:
//// - Main actor: Coordinates state, handles messages
//// - Listener process: Separate process for gRPC recv (non-blocking)
//// - Task processes: Each task runs in isolated process with timeout

import gleam/bool
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Pid, type Subject}
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import gleam/string

import hatchet/errors
import hatchet/internal/ffi/protobuf
import hatchet/internal/grpc
import hatchet/internal/json as j
import hatchet/internal/protocol as p
import hatchet/internal/task_executor
import hatchet/internal/tls.{type TLSConfig}
import hatchet/task
import hatchet/types.{type Client, type WorkerConfig, type Workflow}

// ============================================================================
// Constants (matching Python SDK)
// ============================================================================

const heartbeat_interval_ms: Int = 4000

const max_heartbeat_failures: Int = 3

const max_reconnect_attempts: Int = 15

const default_task_timeout_ms: Int = 300_000

// 5 minutes

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

  // From listener process
  TaskAssigned(protobuf.AssignedAction)
  ListenerError(String)
  ListenerStopped

  // From task processes
  TaskStarted(step_run_id: String)
  TaskCompleted(step_run_id: String, output: String)
  TaskFailed(step_run_id: String, error: String, should_retry: Bool)
  TaskTimeout(step_run_id: String)
  TaskSlotReleased(step_run_id: String)

  // Heartbeat
  SendHeartbeat
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
    // Listener process
    listener_pid: Option(Pid),
    // Workflow registry - maps action names to handlers
    action_registry: Dict(String, TaskHandler),
    // Running tasks - maps step_run_id to task info
    running_tasks: Dict(String, RunningTask),
    available_slots: Int,
    // Completed task outputs - maps workflow_run_id to (step_name -> output)
    // Used for local parent output tracking within a workflow run
    completed_outputs: Dict(String, Dict(String, String)),
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
    handler: fn(types.TaskContext) -> Result(Dynamic, String),
    retries: Int,
    timeout_ms: Int,
    skip_if: Option(fn(types.TaskContext) -> Bool),
    cancel_if: Option(fn(types.TaskContext) -> Bool),
  )
}

pub type RunningTask {
  RunningTask(
    action: protobuf.AssignedAction,
    handler: TaskHandler,
    pid: Pid,
    started_at: Int,
  )
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
  tls_config: Option(tls.TLSConfig),
) -> Result(Subject(WorkerMessage), actor.StartError) {
  let host = types.get_host(client)
  let token = types.get_token(client)
  let tls = option.unwrap(tls_config, tls.Insecure)

  // Build action registry from workflows
  let action_registry = build_action_registry(workflows)

  let initial_state =
    WorkerState(
      client: client,
      config: config,
      host: host,
      grpc_port: grpc_port,
      token: token,
      tls_config: tls,
      channel: None,
      stream: None,
      worker_id: None,
      listener_pid: None,
      action_registry: action_registry,
      running_tasks: dict.new(),
      available_slots: config.slots,
      completed_outputs: dict.new(),
      heartbeat_failures: 0,
      reconnect_attempts: 0,
      is_running: False,
      self: None,
    )

  actor.new_with_initialiser(30_000, fn(subject) {
    // Schedule initial connection
    process.send(subject, Connect)

    let state =
      WorkerState(..initial_state, self: Some(subject), is_running: True)

    // Build selector that receives messages on our subject
    let selector =
      process.new_selector()
      |> process.select(subject)

    actor.initialised(state)
    |> actor.selecting(selector)
    |> actor.returning(subject)
    |> Ok
  })
  |> actor.on_message(handle_message)
  |> actor.start
  |> result.map(fn(started) { started.data })
}

/// Build the action registry from workflow definitions
fn build_action_registry(workflows: List(Workflow)) -> Dict(String, TaskHandler) {
  list.fold(workflows, dict.new(), fn(registry, workflow) {
    // Register regular task handlers
    let reg_with_tasks =
      list.fold(workflow.tasks, registry, fn(reg, task) {
        // Action name format: workflow_name:task_name
        let action_name = workflow.name <> ":" <> task.name
        let timeout = case task.execution_timeout_ms {
          Some(t) -> t
          None -> default_task_timeout_ms
        }
        let handler =
          TaskHandler(
            workflow_name: workflow.name,
            task_name: task.name,
            handler: task.handler,
            retries: task.retries,
            timeout_ms: timeout,
            skip_if: task.skip_if,
            cancel_if: task.cancel_if,
          )
        // Register both formats for matching
        reg
        |> dict.insert(action_name, handler)
        |> dict.insert(task.name, handler)
      })

    // Register on_failure handler if present
    // The server sends this with action name: workflow_name:on_failure
    let reg_after_failure = case workflow.on_failure {
      Some(failure_fn) -> {
        let failure_action = workflow.name <> ":on_failure"
        let failure_handler =
          TaskHandler(
            workflow_name: workflow.name,
            task_name: "on_failure",
            handler: fn(task_ctx) {
              // Convert TaskContext to FailureContext
              // The input contains the failure info from the server
              let failure_ctx =
                types.FailureContext(
                  workflow_run_id: task_ctx.workflow_run_id,
                  failed_task: "",
                  error: "",
                  input: task_ctx.input,
                  step_run_errors: task.get_step_run_errors(task_ctx),
                )
              case failure_fn(failure_ctx) {
                Ok(_) -> Ok(dynamic.string("on_failure completed"))
                Error(e) -> Error(e)
              }
            },
            retries: 0,
            timeout_ms: default_task_timeout_ms,
            skip_if: None,
            cancel_if: None,
          )
        reg_with_tasks
        |> dict.insert(failure_action, failure_handler)
        |> dict.insert("on_failure", failure_handler)
      }
      None -> reg_with_tasks
    }

    // Register on_success handler if present
    // The server sends this with action name: workflow_name:on_success
    case workflow.on_success {
      Some(success_fn) -> {
        let success_action = workflow.name <> ":on_success"
        let success_handler =
          TaskHandler(
            workflow_name: workflow.name,
            task_name: "on_success",
            handler: fn(task_ctx) {
              // Convert TaskContext to SuccessContext
              // The input contains the success info from the server
              let success_ctx =
                types.SuccessContext(
                  workflow_run_id: task_ctx.workflow_run_id,
                  input: task_ctx.input,
                  output: task_ctx.input,
                )
              case success_fn(success_ctx) {
                Ok(_) -> Ok(dynamic.string("on_success completed"))
                Error(e) -> Error(e)
              }
            },
            retries: 0,
            timeout_ms: default_task_timeout_ms,
            skip_if: None,
            cancel_if: None,
          )
        reg_after_failure
        |> dict.insert(success_action, success_handler)
        |> dict.insert("on_success", success_handler)
      }
      None -> reg_after_failure
    }
  })
}

// ============================================================================
// Message Handler
// ============================================================================

fn handle_message(
  state: WorkerState,
  msg: WorkerMessage,
) -> actor.Next(WorkerState, WorkerMessage) {
  case msg {
    Connect -> handle_connect(state)
    Reconnect(attempt) -> handle_reconnect(attempt, state)
    Shutdown -> handle_shutdown(state)

    TaskAssigned(action) -> handle_task_assigned(action, state)
    ListenerError(err) -> handle_listener_error(err, state)
    ListenerStopped -> handle_listener_stopped(state)

    TaskStarted(step_run_id) -> handle_task_started(step_run_id, state)
    TaskCompleted(step_run_id, output) ->
      handle_task_completed(step_run_id, output, state)
    TaskFailed(step_run_id, error, should_retry) ->
      handle_task_failed(step_run_id, error, should_retry, state)
    TaskTimeout(step_run_id) -> handle_task_timeout(step_run_id, state)
    TaskSlotReleased(_step_run_id) -> {
      // Task released its slot - free one slot without removing the task
      // (task is still running, just not counting against concurrency)
      actor.continue(
        WorkerState(..state, available_slots: state.available_slots + 1),
      )
    }

    SendHeartbeat -> handle_send_heartbeat(state)
  }
}

// ============================================================================
// Connection Handling
// ============================================================================

fn handle_connect(state: WorkerState) -> actor.Next(WorkerState, WorkerMessage) {
  log_info(
    "Connecting to Hatchet dispatcher at "
    <> state.host
    <> ":"
    <> int_to_string(state.grpc_port),
  )

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

              // Start listener process
              let listener_pid = start_listener_process(stream, state)

              // Schedule heartbeat
              schedule_heartbeat(state)

              let new_state =
                WorkerState(
                  ..state,
                  channel: Some(channel),
                  stream: Some(stream),
                  worker_id: Some(worker_id),
                  listener_pid: Some(listener_pid),
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
) -> actor.Next(WorkerState, WorkerMessage) {
  case attempt > max_reconnect_attempts {
    True -> {
      log_error("Max reconnection attempts reached, shutting down")
      actor.stop()
    }
    False -> {
      // Non-blocking exponential backoff: schedule Connect after delay
      // This avoids blocking the actor process during backoff
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

      schedule_message(state, Connect, delay_ms)

      let new_state = WorkerState(..state, reconnect_attempts: attempt)
      actor.continue(new_state)
    }
  }
}

fn schedule_reconnect(
  state: WorkerState,
) -> actor.Next(WorkerState, WorkerMessage) {
  let attempt = state.reconnect_attempts + 1
  schedule_message(state, Reconnect(attempt), 100)
  actor.continue(WorkerState(..state, reconnect_attempts: attempt))
}

fn register_worker(
  channel: grpc.Channel,
  state: WorkerState,
) -> Result(String, String) {
  // Get list of action names (only fully-qualified ones with ':' separator)
  let actions =
    dict.keys(state.action_registry)
    |> list.filter(fn(name) { string.contains(name, ":") })

  // Build runtime info
  // Use GO as SDK language since upstream doesn't have a GLEAM enum value.
  // Both run on BEAM/compiled, so GO is the closest match for "compiled language".
  // Identify as Gleam via the extra field.
  let runtime_info =
    protobuf.RuntimeInfo(
      sdk_version: sdk_version,
      language: protobuf.Go,
      language_version: gleam_version,
      os: get_os_info(),
      extra: Some("gleam"),
    )

  // Convert string labels to WorkerLabel type
  let labels =
    dict.fold(state.config.labels, dict.new(), fn(acc, key, value) {
      dict.insert(acc, key, protobuf.StringLabel(value))
    })

  // Build registration request
  let request =
    protobuf.WorkerRegisterRequest(
      worker_name: option.unwrap(state.config.name, "gleam-worker"),
      actions: actions,
      services: [],
      max_runs: Some(state.config.slots),
      labels: labels,
      webhook_id: None,
      runtime_info: Some(runtime_info),
    )

  // Encode and send
  case protobuf.encode_worker_register_request(request) {
    Ok(encoded) -> {
      case grpc.register_worker(channel, encoded, state.token) {
        Ok(response) -> Ok(response.worker_id)
        Error(e) -> Error(e)
      }
    }
    Error(e) -> {
      case e {
        protobuf.ProtobufEncodeError(msg) -> {
          Error(
            errors.to_simple_string(errors.decode_error(
              "worker register request",
              msg,
            )),
          )
        }
        protobuf.ProtobufDecodeError(msg) -> {
          Error(
            errors.to_simple_string(errors.decode_error(
              "worker register request",
              msg,
            )),
          )
        }
      }
    }
  }
}

// ============================================================================
// Listener Process (runs in separate process to avoid blocking)
// ============================================================================

fn start_listener_process(stream: grpc.Stream, state: WorkerState) -> Pid {
  let parent = case state.self {
    Some(s) -> s
    None -> panic as "Worker self not set"
  }

  // Spawn a process that loops receiving from the stream
  process.spawn(fn() { listener_loop(stream, parent) })
}

fn listener_loop(stream: grpc.Stream, parent: Subject(WorkerMessage)) -> Nil {
  // Short timeout so we can check for shutdown
  case grpc.recv_assigned_action(stream, 5000) {
    Ok(action) -> {
      process.send(parent, TaskAssigned(action))
      listener_loop(stream, parent)
    }
    Error("timeout") -> {
      // Normal timeout, continue listening
      listener_loop(stream, parent)
    }
    Error("stream_closed") -> {
      process.send(parent, ListenerStopped)
      Nil
    }
    Error(e) -> {
      process.send(parent, ListenerError(e))
      Nil
    }
  }
}

fn handle_listener_error(
  error: String,
  state: WorkerState,
) -> actor.Next(WorkerState, WorkerMessage) {
  log_error("Listener error: " <> error)
  cleanup_connections(state)
  schedule_reconnect(
    WorkerState(
      ..state,
      channel: None,
      stream: None,
      worker_id: None,
      listener_pid: None,
    ),
  )
}

fn handle_listener_stopped(
  state: WorkerState,
) -> actor.Next(WorkerState, WorkerMessage) {
  log_warning("Listener stopped, reconnecting...")
  cleanup_connections(state)
  schedule_reconnect(
    WorkerState(
      ..state,
      channel: None,
      stream: None,
      worker_id: None,
      listener_pid: None,
    ),
  )
}

fn cleanup_connections(state: WorkerState) -> Nil {
  // Kill the listener process first to stop it sending messages
  case state.listener_pid {
    Some(pid) -> process.kill(pid)
    None -> Nil
  }
  case state.stream {
    Some(stream) -> grpc.close_stream(stream)
    None -> Nil
  }
  case state.channel {
    Some(channel) -> grpc.close(channel)
    None -> Nil
  }
  Nil
}

// ============================================================================
// Task Handling
// ============================================================================

fn handle_task_assigned(
  action: protobuf.AssignedAction,
  state: WorkerState,
) -> actor.Next(WorkerState, WorkerMessage) {
  // Check if we have capacity
  case state.available_slots > 0 {
    True -> {
      // Find the handler for this action
      case find_handler(action.step_name, state.action_registry) {
        Some(handler) -> {
          log_info("Received task: " <> action.step_name)

          // Spawn task in separate process
          let task_pid = spawn_task_process(action, handler, state)

          // Track the running task with handler info for retry decisions
          let running_task =
            RunningTask(
              action: action,
              handler: handler,
              pid: task_pid,
              started_at: current_time_ms(),
            )

          let new_running =
            dict.insert(state.running_tasks, action.step_run_id, running_task)

          // Schedule timeout
          schedule_message(
            state,
            TaskTimeout(action.step_run_id),
            handler.timeout_ms,
          )

          actor.continue(
            WorkerState(
              ..state,
              running_tasks: new_running,
              available_slots: state.available_slots - 1,
            ),
          )
        }
        None -> {
          log_error("No handler for action: " <> action.step_name)
          // Send failed event for unknown action
          send_task_failed_event(state, action, "No handler registered")
          actor.continue(state)
        }
      }
    }
    False -> {
      log_warning(
        "No available slots for task: "
        <> action.step_name
        <> " (task will be requeued by dispatcher)",
      )
      // Don't ACK - let dispatcher reassign
      actor.continue(state)
    }
  }
}

fn find_handler(
  step_name: String,
  registry: Dict(String, TaskHandler),
) -> Option(TaskHandler) {
  case dict.get(registry, step_name) {
    Ok(h) -> Some(h)
    Error(_) -> {
      // Try to find by task name part (after colon)
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
  }
}

fn spawn_task_process(
  action: protobuf.AssignedAction,
  handler: TaskHandler,
  state: WorkerState,
) -> Pid {
  let parent = case state.self {
    Some(s) -> s
    None -> panic as "Worker self not set"
  }
  let worker_id = option.unwrap(state.worker_id, "")
  let channel = state.channel
  let token = state.token
  let client = state.client

  // Get local parent outputs for this workflow run if available
  let local_parent_outputs =
    dict.get(state.completed_outputs, action.workflow_run_id)
    |> result.unwrap(dict.new())

  process.spawn(fn() {
    execute_task_in_process(
      action,
      handler,
      worker_id,
      channel,
      token,
      local_parent_outputs,
      client,
      parent,
    )
  })
}

/// Execute a task in a separate process using the pure task_executor module.
///
/// This is a thin adapter that bridges between the actor-based worker and
/// the pure task execution logic. It:
/// 1. Builds a TaskSpec and TaskEffects from the action and handler
/// 2. Delegates execution to task_executor.execute_task
/// 3. Sends protocol events and actor messages based on ExecutionResult
fn execute_task_in_process(
  action: protobuf.AssignedAction,
  handler: TaskHandler,
  worker_id: String,
  channel: Option(grpc.Channel),
  token: String,
  local_parent_outputs: Dict(String, String),
  client: Client,
  parent: Subject(WorkerMessage),
) -> Nil {
  // Notify parent we started
  process.send(parent, TaskStarted(action.step_run_id))

  // Build TaskSpec from action and handler
  let task_handler =
    task_executor.TaskHandler(
      workflow_name: handler.workflow_name,
      task_name: handler.task_name,
      handler: handler.handler,
      retries: handler.retries,
      timeout_ms: handler.timeout_ms,
      skip_if: handler.skip_if,
      cancel_if: handler.cancel_if,
    )

  let spec =
    task_executor.TaskSpec(
      action: action,
      handler: task_handler,
      worker_id: worker_id,
      parent_outputs: local_parent_outputs,
    )

  // Create TaskEffects with closures for side effects
  let effects =
    task_executor.TaskEffects(
      log: fn(msg: String) { log_info("[" <> action.step_name <> "] " <> msg) },
      emit_event: fn(event_type, payload) {
        send_event_from_task(
          channel,
          token,
          action,
          worker_id,
          event_type,
          payload,
        )
      },
      release_slot: fn() {
        process.send(parent, TaskSlotReleased(action.step_run_id))
        Ok(Nil)
      },
      refresh_timeout: fn(increment_ms) {
        let payload = "{\"increment_ms\":" <> int_to_string(increment_ms) <> "}"
        send_event_from_task(
          channel,
          token,
          action,
          worker_id,
          protobuf.StepEventTypeRefreshTimeout,
          payload,
        )
        Ok(Nil)
      },
      cancel: fn() {
        send_event_from_task(
          channel,
          token,
          action,
          worker_id,
          protobuf.StepEventTypeCancelled,
          "{}",
        )
        Ok(Nil)
      },
      spawn_workflow: fn(workflow_name, input, metadata) {
        spawn_child_workflow(client, workflow_name, input, metadata)
      },
    )

  // Execute task using pure task_executor logic
  let result = task_executor.execute_task(spec, effects)

  // Handle result and send appropriate messages to parent
  case result {
    task_executor.Completed(output) -> {
      process.send(
        parent,
        TaskCompleted(action.step_run_id, output.output_json),
      )
    }
    task_executor.Skipped(output) -> {
      process.send(
        parent,
        TaskCompleted(action.step_run_id, output.output_json),
      )
    }
    task_executor.Failed(error) -> {
      // Send FAILED event with should_not_retry flag
      send_event_from_task_with_retry(
        channel,
        token,
        action,
        worker_id,
        protobuf.StepEventTypeFailed,
        // Build error payload from TaskError
        json.to_string(
          json.object([
            #("error", json.string(error.error)),
            #("retry_count", json.int(error.retry_count)),
            #("max_retries", json.int(handler.retries)),
            #("should_retry", json.bool(error.should_retry)),
          ]),
        ),
        Some(bool.negate(error.should_retry)),
      )
      process.send(
        parent,
        TaskFailed(action.step_run_id, error.error, error.should_retry),
      )
    }
    task_executor.Cancelled(cancelled) -> {
      process.send(
        parent,
        TaskFailed(action.step_run_id, cancelled.reason, False),
      )
    }
  }
}

fn send_event_from_task(
  channel: Option(grpc.Channel),
  token: String,
  action: protobuf.AssignedAction,
  worker_id: String,
  event_type: protobuf.StepActionEventType,
  payload: String,
) -> Nil {
  send_event_from_task_with_retry(
    channel,
    token,
    action,
    worker_id,
    event_type,
    payload,
    None,
  )
}

fn send_event_from_task_with_retry(
  channel: Option(grpc.Channel),
  token: String,
  action: protobuf.AssignedAction,
  worker_id: String,
  event_type: protobuf.StepActionEventType,
  payload: String,
  should_not_retry: Option(Bool),
) -> Nil {
  case channel {
    Some(ch) -> {
      let event =
        protobuf.StepActionEvent(
          worker_id: worker_id,
          job_id: action.job_id,
          job_run_id: action.job_run_id,
          step_id: action.step_id,
          step_run_id: action.step_run_id,
          action_id: action.action_id,
          event_timestamp: current_time_ms(),
          event_type: event_type,
          event_payload: payload,
          retry_count: Some(action.retry_count),
          should_not_retry: should_not_retry,
        )

      case grpc.send_step_action_event(ch, event, token) {
        Ok(_) -> Nil
        Error(e) -> log_error("Failed to send event: " <> e)
      }
    }
    None -> log_error("No channel to send event")
  }
}

fn handle_task_started(
  step_run_id: String,
  state: WorkerState,
) -> actor.Next(WorkerState, WorkerMessage) {
  log_info("Task started: " <> step_run_id)
  actor.continue(state)
}

fn handle_task_completed(
  step_run_id: String,
  output: String,
  state: WorkerState,
) -> actor.Next(WorkerState, WorkerMessage) {
  log_info("Task completed: " <> step_run_id)

  // Get the running task info to store output
  let new_completed_outputs = case dict.get(state.running_tasks, step_run_id) {
    Ok(running_task) -> {
      let workflow_run_id = running_task.action.workflow_run_id
      let step_name = running_task.action.step_name

      // Get or create the outputs dict for this workflow run
      let workflow_outputs =
        dict.get(state.completed_outputs, workflow_run_id)
        |> result.unwrap(dict.new())

      // Store this task's output
      let updated_workflow_outputs =
        dict.insert(workflow_outputs, step_name, output)

      // Update the completed outputs
      dict.insert(
        state.completed_outputs,
        workflow_run_id,
        updated_workflow_outputs,
      )
    }
    Error(_) -> state.completed_outputs
  }

  // Remove from running tasks and free slot
  let new_running = dict.delete(state.running_tasks, step_run_id)

  // Clean up completed_outputs for workflow runs with no remaining tasks
  let final_completed_outputs =
    cleanup_stale_outputs(new_running, new_completed_outputs)

  actor.continue(
    WorkerState(
      ..state,
      running_tasks: new_running,
      completed_outputs: final_completed_outputs,
      available_slots: state.available_slots + 1,
    ),
  )
}

fn handle_task_failed(
  step_run_id: String,
  error: String,
  should_retry: Bool,
  state: WorkerState,
) -> actor.Next(WorkerState, WorkerMessage) {
  // Log with retry information
  let retry_info = case should_retry {
    True -> " (will be retried by server)"
    False -> " (max retries exceeded)"
  }
  log_error("Task failed: " <> step_run_id <> " - " <> error <> retry_info)

  // Remove from running tasks and free slot
  let new_running = dict.delete(state.running_tasks, step_run_id)
  actor.continue(
    WorkerState(
      ..state,
      running_tasks: new_running,
      available_slots: state.available_slots + 1,
    ),
  )
}

fn handle_task_timeout(
  step_run_id: String,
  state: WorkerState,
) -> actor.Next(WorkerState, WorkerMessage) {
  // Check if task is still running
  case dict.get(state.running_tasks, step_run_id) {
    Ok(running_task) -> {
      let action = running_task.action
      let handler = running_task.handler

      // Determine if we should retry based on handler config
      let should_retry = action.retry_count < handler.retries
      let retry_info = case should_retry {
        True -> " (will be retried by server)"
        False -> " (max retries exceeded)"
      }

      log_error(
        "Task timeout: "
        <> step_run_id
        <> " after "
        <> int_to_string(handler.timeout_ms)
        <> "ms"
        <> retry_info,
      )

      // Kill the task process
      process.kill(running_task.pid)

      // Send FAILED event for timeout with retry info
      send_task_timeout_event(state, action, handler)

      // Remove from running tasks and free slot
      let new_running = dict.delete(state.running_tasks, step_run_id)
      actor.continue(
        WorkerState(
          ..state,
          running_tasks: new_running,
          available_slots: state.available_slots + 1,
        ),
      )
    }
    Error(_) -> {
      // Task already completed, ignore timeout
      actor.continue(state)
    }
  }
}

fn send_task_timeout_event(
  state: WorkerState,
  action: protobuf.AssignedAction,
  handler: TaskHandler,
) -> Nil {
  case state.channel {
    Some(channel) -> {
      let should_retry = action.retry_count < handler.retries

      let error_json =
        json.to_string(
          json.object([
            #("error", json.string("Task execution timeout")),
            #("timeout_ms", json.int(handler.timeout_ms)),
            #("retry_count", json.int(action.retry_count)),
            #("max_retries", json.int(handler.retries)),
            #("should_retry", json.bool(should_retry)),
          ]),
        )

      let event =
        protobuf.StepActionEvent(
          worker_id: option.unwrap(state.worker_id, ""),
          job_id: action.job_id,
          job_run_id: action.job_run_id,
          step_id: action.step_id,
          step_run_id: action.step_run_id,
          action_id: action.action_id,
          event_timestamp: current_time_ms(),
          event_type: protobuf.StepEventTypeFailed,
          event_payload: error_json,
          retry_count: Some(action.retry_count),
          // Tell server not to retry if we've exceeded max
          should_not_retry: Some(bool.negate(should_retry)),
        )

      case grpc.send_step_action_event(channel, event, state.token) {
        Ok(_) -> Nil
        Error(e) -> log_error("Failed to send timeout event: " <> e)
      }
    }
    None -> Nil
  }
}

fn send_task_failed_event(
  state: WorkerState,
  action: protobuf.AssignedAction,
  error: String,
) -> Nil {
  case state.channel {
    Some(channel) -> {
      let error_json =
        json.to_string(json.object([#("error", json.string(error))]))

      let event =
        protobuf.StepActionEvent(
          worker_id: option.unwrap(state.worker_id, ""),
          job_id: action.job_id,
          job_run_id: action.job_run_id,
          step_id: action.step_id,
          step_run_id: action.step_run_id,
          action_id: action.action_id,
          event_timestamp: current_time_ms(),
          event_type: protobuf.StepEventTypeFailed,
          event_payload: error_json,
          retry_count: Some(action.retry_count),
          should_not_retry: None,
        )

      case grpc.send_step_action_event(channel, event, state.token) {
        Ok(_) -> Nil
        Error(e) -> log_error("Failed to send failed event: " <> e)
      }
    }
    None -> Nil
  }
}

// ============================================================================
// Heartbeat Handling
// ============================================================================

fn handle_send_heartbeat(
  state: WorkerState,
) -> actor.Next(WorkerState, WorkerMessage) {
  case state.channel, state.worker_id {
    Some(channel), Some(worker_id) -> {
      case grpc.send_heartbeat(channel, worker_id, state.token) {
        Ok(_) -> {
          // Reset failure count and schedule next heartbeat
          schedule_heartbeat(state)
          actor.continue(WorkerState(..state, heartbeat_failures: 0))
        }
        Error(_) -> {
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
              cleanup_connections(state)
              schedule_reconnect(
                WorkerState(
                  ..state,
                  channel: None,
                  stream: None,
                  worker_id: None,
                  listener_pid: None,
                  heartbeat_failures: failures,
                ),
              )
            }
            False -> {
              schedule_heartbeat(state)
              actor.continue(WorkerState(..state, heartbeat_failures: failures))
            }
          }
        }
      }
    }
    _, _ -> {
      // Not connected, skip heartbeat
      actor.continue(state)
    }
  }
}

fn schedule_heartbeat(state: WorkerState) -> Nil {
  schedule_message(state, SendHeartbeat, heartbeat_interval_ms)
}

// ============================================================================
// Shutdown
// ============================================================================

fn handle_shutdown(state: WorkerState) -> actor.Next(WorkerState, WorkerMessage) {
  log_info("Shutting down worker...")

  // Kill any running tasks
  let _ =
    dict.each(state.running_tasks, fn(_id, task) { process.kill(task.pid) })

  // Close connections
  cleanup_connections(state)

  actor.stop()
}

// ============================================================================
// Output Cleanup
// ============================================================================

/// Remove completed_outputs entries for workflow runs that have no remaining
/// running tasks. This prevents unbounded memory growth for long-running workers.
fn cleanup_stale_outputs(
  running_tasks: Dict(String, RunningTask),
  completed_outputs: Dict(String, Dict(String, String)),
) -> Dict(String, Dict(String, String)) {
  // Build set of workflow_run_ids that still have running tasks
  let active_workflow_runs =
    dict.fold(running_tasks, dict.new(), fn(acc, _id, task) {
      dict.insert(acc, task.action.workflow_run_id, True)
    })

  // Remove entries for workflow runs with no active tasks
  dict.fold(completed_outputs, dict.new(), fn(acc, wf_run_id, outputs) {
    case dict.get(active_workflow_runs, wf_run_id) {
      Ok(_) -> dict.insert(acc, wf_run_id, outputs)
      Error(_) -> acc
    }
  })
}

// ============================================================================
// Child Workflow Spawning
// ============================================================================

fn spawn_child_workflow(
  client: Client,
  workflow_name: String,
  input: Dynamic,
  metadata: Dict(String, String),
) -> Result(String, String) {
  let run_req =
    p.WorkflowRunRequest(
      workflow_name: workflow_name,
      input: input,
      metadata: metadata,
      priority: None,
      sticky: False,
      run_key: None,
    )

  let req_body = j.encode_workflow_run(run_req)
  let base_url = build_base_url(client)
  let url = base_url <> "/api/v1/workflows/" <> workflow_name <> "/run"

  case request.to(url) {
    Ok(req) -> {
      let req =
        req
        |> request.set_body(req_body)
        |> request.set_header("content-type", "application/json")
        |> request.set_header(
          "authorization",
          "Bearer " <> types.get_token(client),
        )

      case httpc.send(req) {
        Ok(resp) if resp.status == 200 -> {
          case j.decode_workflow_run_response(resp.body) {
            Ok(run_resp) -> Ok(run_resp.run_id)
            Error(e) -> Error("Failed to decode response: " <> e)
          }
        }
        Ok(resp) -> {
          Error("API error: " <> int.to_string(resp.status) <> " " <> resp.body)
        }
        Error(_) -> Error("Network error")
      }
    }
    Error(_) -> Error("Invalid URL")
  }
}

fn build_base_url(client: Client) -> String {
  let host = types.get_host(client)
  let port = types.get_port(client)
  "http://" <> host <> ":" <> int.to_string(port)
}

// ============================================================================
// Utility Functions
// ============================================================================

fn schedule_message(
  state: WorkerState,
  msg: WorkerMessage,
  delay_ms: Int,
) -> Nil {
  case state.self {
    Some(self) -> {
      case delay_ms > 0 {
        True -> {
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
