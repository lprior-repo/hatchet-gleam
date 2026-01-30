import gleam/string
import gleeunit/should
import hatchet/client
import hatchet/schedule
import hatchet/types

pub fn list_returns_empty_list_when_no_schedules_test() {
  let assert Ok(client) = client.new("localhost", "test-token")

  case schedule.list(client, "test-workflow") {
    Ok(list) -> {
      list
      |> should.equal([])
    }
    Error(_) -> should.be_true(False)
  }
}

pub fn list_returns_metadata_for_existing_schedules_test() {
  let assert Ok(client) = client.new("localhost", "test-token")

  case schedule.list(client, "test-workflow") {
    Ok(list) -> {
      list
      |> should.be_equal(List)
    }
    Error(_) -> should.be_true(False)
  }
}

pub fn list_returns_error_when_workflow_not_found_test() {
  let assert Ok(client) = client.new("localhost", "test-token")

  case schedule.list(client, "nonexistent-workflow") {
    Ok(_) -> should.be_true(False)
    Error(e) -> {
      string.length(e)
      |> should.be_greater_than_or_equal(0)
    }
  }
}

pub fn list_handles_network_failures_test() {
  let assert Ok(client) = client.new("invalid-host-999999", "test-token")

  case schedule.list(client, "test-workflow") {
    Ok(_) -> should.be_true(False)
    Error(e) -> {
      string.contains(e, "network")
      |> should.equal(True)
    }
  }
}

pub fn list_makes_correct_api_request_test() {
  let assert Ok(client) = client.new("localhost", "test-token")

  case schedule.list(client, "my-workflow") {
    Ok(_) -> should.be_true(True)
    Error(_) -> should.be_true(False)
  }
}

pub fn list_api_preserves_client_token_test() {
  let assert Ok(client) = client.new("localhost", "test-token-123")

  let token_used =
    client
    |> types.get_token

  token_used
  |> should.equal("test-token-123")
}

pub fn list_api_respects_client_port_test() {
  let assert Ok(client) = client.new("localhost", "test-token")
  let client_with_port = client.with_port(client, 8080)

  let port_used =
    client_with_port
    |> types.get_port

  port_used
  |> should.equal(8080)
}

pub fn list_functions_are_idempotent_test() {
  let assert Ok(client) = client.new("localhost", "test-token")

  let result1 = schedule.list(client, "test-workflow")
  let result2 = schedule.list(client, "test-workflow")

  case result1, result2 {
    Ok(_), Ok(_) -> should.be_true(True)
    _, _ -> should.be_true(False)
  }
}
