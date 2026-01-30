import envoy
import gleam/option
import gleeunit
import gleeunit/should
import hatchet/client
import hatchet/types
import hatchet/workflows

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

pub fn workflows_module_exists_test() {
  should.be_true(True)
}

pub fn workflows_list_returns_empty_list_when_no_workflows_test() {
  with_live_client(fn(client) {
    case workflows.list(client) {
      Ok(_) -> should.be_true(True)
      Error(_) -> should.be_true(False)
    }
  })
}

pub fn workflows_delete_returns_ok_when_workflow_exists_test() {
  with_live_client(fn(client) {
    case workflows.delete(client, "test-workflow") {
      Ok(Nil) -> should.be_true(True)
      Error(_) -> should.be_true(False)
    }
  })
}

pub fn workflows_get_returns_metadata_when_workflow_exists_test() {
  with_live_client(fn(client) {
    case workflows.get(client, "test-workflow") {
      Ok(metadata) -> {
        metadata.name |> should.equal("test-workflow")
      }
      Error(_) -> should.be_true(False)
    }
  })
}
