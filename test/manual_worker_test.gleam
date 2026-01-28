//// Manual Worker Test
////
//// This demonstrates how to create and start a worker.
//// To run this against a real Hatchet server:
//// 1. Start Hatchet with docker-compose (see docs/HATCHET.md)
//// 2. Set HATCHET_TOKEN environment variable
//// 3. Run: gleam run -m manual_worker_test

import gleam/dict
import gleam/dynamic
import gleam/io
import gleam/option.{None, Some}
import hatchet/client
import hatchet/types

/// Example task handler that processes incoming data
fn example_task(ctx: types.TaskContext) -> Result(dynamic.Dynamic, String) {
  // Log the task execution
  ctx.logger("Starting example task")

  // Access input data (available as ctx.input)
  let _input = ctx.input

  // Log workflow and task IDs
  ctx.logger("Workflow Run ID: " <> ctx.workflow_run_id)
  ctx.logger("Task Run ID: " <> ctx.task_run_id)

  // Return success with some output
  Ok(dynamic.string("Task completed successfully"))
}

/// Example on_failure handler
fn handle_failure(failure_ctx: types.FailureContext) -> Result(Nil, String) {
  io.println("❌ Workflow failed!")
  io.println("  Failed task: " <> failure_ctx.failed_task)
  io.println("  Error: " <> failure_ctx.error)
  Ok(Nil)
}

pub fn main() {
  io.println("🚀 Hatchet Worker Manual Test")
  io.println("==============================")

  // Create client from environment
  let client = case client.from_environment() {
    Ok(c) -> {
      io.println("✅ Client created successfully")
      c
    }
    Error(e) -> {
      io.println("❌ Failed to create client: " <> e)
      io.println("   Set HATCHET_HOST and HATCHET_TOKEN environment variables")
      panic as "Client creation failed"
    }
  }

  // Create a workflow
  io.println("\n📋 Creating workflow...")
  let workflow =
    types.Workflow(
      name: "test-workflow",
      description: Some("Manual test workflow"),
      version: Some("1.0.0"),
      tasks: [
        types.TaskDef(
          name: "example-task",
          handler: example_task,
          parents: [],
          retries: 3,
          retry_backoff: Some(types.Exponential(1000, 30_000)),
          execution_timeout_ms: Some(60_000),
          schedule_timeout_ms: None,
          rate_limits: [],
          concurrency: None,
          skip_if: None,
          wait_for: None,
          is_durable: False,
          checkpoint_key: None,
        ),
      ],
      on_failure: Some(handle_failure),
      cron: None,
      events: [],
      concurrency: None,
    )

  // Create worker config
  io.println("⚙️  Creating worker config...")
  let config =
    types.WorkerConfig(
      name: Some("manual-test-worker"),
      slots: 5,
      durable_slots: 0,
      labels: dict.from_list([
        #("environment", "test"),
        #("version", "1.0.0"),
      ]),
    )

  // Create worker
  io.println("🔧 Creating worker...")
  let worker = case client.new_worker(client, config, [workflow]) {
    Ok(w) -> {
      io.println("✅ Worker created successfully")
      w
    }
    Error(e) -> {
      io.println("❌ Failed to create worker: " <> e)
      panic as "Worker creation failed"
    }
  }

  io.println("\n🎯 Worker is now running and will:")
  io.println("   1. Register with Hatchet dispatcher")
  io.println("   2. Listen for task assignments via gRPC stream")
  io.println("   3. Execute task handlers with proper context")
  io.println("   4. Send heartbeats every 4 seconds")
  io.println("   5. Report task completion/failure events")
  io.println("\n💡 To test: Submit a workflow via Hatchet dashboard or CLI")
  io.println("   Press Ctrl+C to stop\n")

  // Start worker (blocking)
  case client.start_worker_blocking(worker) {
    Ok(_) -> {
      io.println("✅ Worker shut down gracefully")
    }
    Error(e) -> {
      io.println("❌ Worker error: " <> e)
    }
  }
}
