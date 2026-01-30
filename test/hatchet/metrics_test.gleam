import gleeunit/should
import hatchet/client
import hatchet/metrics
import hatchet/types

pub fn get_workflow_metrics_returns_metrics_when_workflow_exists_test() {
  let assert Ok(client) = client.new("localhost", "test-token")

  case metrics.get_workflow_metrics(client, "test-workflow") {
    Ok(metrics) -> {
      metrics.workflow_name
      |> should.equal("test-workflow")

      metrics.total_runs
      |> should.be_greater_than_or_equal(0)

      metrics.successful_runs
      |> should.be_greater_than_or_equal(0)
    }
    Error(_) -> should.be_true(False)
  }
}

pub fn get_workflow_metrics_includes_percentiles_test() {
  let assert Ok(client) = client.new("localhost", "test-token")

  case metrics.get_workflow_metrics(client, "test-workflow") {
    Ok(metrics) -> {
      metrics.p50_duration_ms
      |> should.be_ok()

      metrics.p95_duration_ms
      |> should.be_ok()

      metrics.p99_duration_ms
      |> should.be_ok()
    }
    Error(_) -> should.be_true(False)
  }
}

pub fn get_workflow_metrics_calculates_success_rate_test() {
  let assert Ok(client) = client.new("localhost", "test-token")

  case metrics.get_workflow_metrics(client, "test-workflow") {
    Ok(metrics) -> {
      metrics.success_rate
      |> should.be_greater_than_or_equal(0.0)

      metrics.success_rate
      |> should.be_less_than_or_equal(1.0)
    }
    Error(_) -> should.be_true(False)
  }
}

pub fn get_worker_metrics_returns_metrics_when_worker_exists_test() {
  let assert Ok(client) = client.new("localhost", "test-token")

  case metrics.get_worker_metrics(client, "worker-123") {
    Ok(metrics) -> {
      metrics.worker_id
      |> should.equal("worker-123")

      metrics.total_tasks
      |> should.be_greater_than_or_equal(0)

      metrics.successful_tasks
      |> should.be_greater_than_or_equal(0)
    }
    Error(_) -> should.be_true(False)
  }
}

pub fn get_worker_metrics_includes_active_tasks_test() {
  let assert Ok(client) = client.new("localhost", "test-token")

  case metrics.get_worker_metrics(client, "worker-123") {
    Ok(metrics) -> {
      metrics.active_tasks
      |> should.be_greater_than_or_equal(0)
    }
    Error(_) -> should.be_true(False)
  }
}
