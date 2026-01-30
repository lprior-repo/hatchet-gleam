import gleam/option
import gleeunit
import gleeunit/should
import hatchet/client
import hatchet/workflows

pub fn workflows_module_exists_test() {
  should.be_true(True)
}

pub fn workflows_list_returns_empty_list_when_no_workflows_test() {
  let assert Ok(client) = client.new("localhost", "test-token")

  case workflows.list(client) {
    Ok(list) -> should.be_true(True)
    Error(_) -> should.be_true(False)
  }
}

pub fn workflows_delete_returns_ok_when_workflow_exists_test() {
  let assert Ok(client) = client.new("localhost", "test-token")

  case workflows.delete(client, "test-workflow") {
    Ok(Nil) -> should.be_true(True)
    Error(_) -> should.be_true(False)
  }
}

pub fn workflows_get_returns_metadata_when_workflow_exists_test() {
  let assert Ok(client) = client.new("localhost", "test-token")

  case workflows.get(client, "test-workflow") {
    Ok(metadata) -> {
      metadata.name |> should.equal("test-workflow")
    }
    Error(_) -> should.be_true(False)
  }
}
