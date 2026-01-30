import gleam/http/request
import gleam/http/response
import gleam/httpc
import gleeunit
import gleeunit/should
import hatchet/internal/http_client

pub fn main() {
  gleeunit.main()
}

pub fn real_http_client_creation_test() {
  // Just verify it can be created without errors
  // Actual HTTP calls are integration tests
  let _client = http_client.real_http_client()
  // Test passes if we get here without panic
  should.be_true(True)
}

pub fn test_http_client_returns_configured_response_test() {
  let expected_response =
    response.Response(status: 200, headers: [], body: "{\"status\":\"ok\"}")

  let client = http_client.test_http_client(expected_response)

  let req =
    request.to("http://example.com")
    |> should.be_ok

  let result = http_client.send(client, req)

  result
  |> should.be_ok
  |> should.equal(expected_response)
}

pub fn test_http_client_returns_same_response_multiple_times_test() {
  let expected_response =
    response.Response(status: 201, headers: [], body: "{\"id\":\"123\"}")

  let client = http_client.test_http_client(expected_response)

  let req =
    request.to("http://example.com")
    |> should.be_ok

  // First call
  let result1 = http_client.send(client, req)
  result1
  |> should.be_ok
  |> should.equal(expected_response)

  // Second call - should return same response
  let result2 = http_client.send(client, req)
  result2
  |> should.be_ok
  |> should.equal(expected_response)
}

pub fn test_error_client_returns_configured_error_test() {
  let client = http_client.test_error_client(httpc.ResponseTimeout)

  let req =
    request.to("http://example.com")
    |> should.be_ok

  let result = http_client.send(client, req)

  result
  |> should.be_error
  |> should.equal(httpc.ResponseTimeout)
}

pub fn test_error_client_with_failed_to_connect_test() {
  let ipv4_error = httpc.Posix(code: "econnrefused")
  let ipv6_error = httpc.Posix(code: "econnrefused")
  let error = httpc.FailedToConnect(ip4: ipv4_error, ip6: ipv6_error)
  let client = http_client.test_error_client(error)

  let req =
    request.to("http://example.com")
    |> should.be_ok

  let result = http_client.send(client, req)

  result
  |> should.be_error
  |> should.equal(error)
}
