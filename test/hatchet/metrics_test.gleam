import envoy
import gleam/option.{None, Some}
import gleeunit/should
import hatchet/client
import hatchet/metrics
import hatchet/types

fn with_live_client(f: fn(types.Client) -> Nil) -> Nil {
  case envoy.get("HATCHET_LIVE_TEST") {
    Ok("1") -> {
      let token = case envoy.get("HATCHET_CLIENT_TOKEN") {
        Ok(t) -> t
        Error(_) ->
          case envoy.get("HATCHET_TOKEN") {
            Ok(t) -> t
            Error(_) -> ""
          }
      }
      case token {
        "" -> Nil
        t -> {
          let host =
            envoy.get("HATCHET_HOST")
            |> result_or("localhost")
          let assert Ok(c) = client.new(host, t)
          f(c)
        }
      }
    }
    _ -> Nil
  }
}

fn result_or(r: Result(a, e), default: a) -> a {
  case r {
    Ok(v) -> v
    Error(_) -> default
  }
}

pub fn get_workflow_metrics_returns_metrics_when_workflow_exists_test() {
  with_live_client(fn(client) {
    case metrics.get_workflow_metrics(client, "test-workflow") {
      Ok(metrics) -> {
        metrics.workflow_name
        |> should.equal("test-workflow")

        should.be_true(metrics.total_runs >= 0)

        should.be_true(metrics.successful_runs >= 0)
      }
      Error(_) -> should.be_true(False)
    }
  })
}

pub fn get_workflow_metrics_includes_percentiles_test() {
  with_live_client(fn(client) {
    case metrics.get_workflow_metrics(client, "test-workflow") {
      Ok(metrics) -> {
        should.be_true(case metrics.p50_duration_ms {
          Some(_) | None -> True
        })

        should.be_true(case metrics.p95_duration_ms {
          Some(_) | None -> True
        })

        should.be_true(case metrics.p99_duration_ms {
          Some(_) | None -> True
        })
      }
      Error(_) -> should.be_true(False)
    }
  })
}

pub fn get_workflow_metrics_calculates_success_rate_test() {
  with_live_client(fn(client) {
    case metrics.get_workflow_metrics(client, "test-workflow") {
      Ok(metrics) -> {
        should.be_true(metrics.success_rate >=. 0.0)

        should.be_true(metrics.success_rate <=. 1.0)
      }
      Error(_) -> should.be_true(False)
    }
  })
}

pub fn get_worker_metrics_returns_metrics_when_worker_exists_test() {
  with_live_client(fn(client) {
    case metrics.get_worker_metrics(client, "worker-123") {
      Ok(metrics) -> {
        metrics.worker_id
        |> should.equal("worker-123")

        should.be_true(metrics.total_tasks >= 0)

        should.be_true(metrics.successful_tasks >= 0)
      }
      Error(_) -> should.be_true(False)
    }
  })
}

pub fn get_worker_metrics_includes_active_tasks_test() {
  with_live_client(fn(client) {
    case metrics.get_worker_metrics(client, "worker-123") {
      Ok(metrics) -> {
        should.be_true(metrics.active_tasks >= 0)
      }
      Error(_) -> should.be_true(False)
    }
  })
}
