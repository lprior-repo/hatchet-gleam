import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/httpc

/// HTTP client abstraction for dependency injection and testing.
///
/// This type wraps the HTTP send function, allowing us to swap
/// implementations for testing without modifying business logic.
pub opaque type HttpClient {
  HttpClient(
    send: fn(Request(String)) -> Result(Response(String), httpc.HttpError),
  )
}

/// Create a real HTTP client that uses gleam_httpc.
///
/// This is the production implementation that makes actual network requests.
///
/// ## Example
///
/// ```gleam
/// let client = http_client.real_http_client()
/// ```
pub fn real_http_client() -> HttpClient {
  HttpClient(send: httpc.send)
}

/// Create a test HTTP client with a predefined response.
///
/// This is used for testing to avoid making actual network requests.
/// The same response is returned for all requests made with this client.
///
/// ## Parameters
///
/// - `response`: The response to return for all requests
///
/// ## Example
///
/// ```gleam
/// import gleam/http/response
/// import gleam/httpc
///
/// let response = httpc.Response(
///   status: 200,
///   headers: [],
///   body: "{\"id\": \"123\"}",
/// )
/// let client = http_client.test_http_client(response)
/// ```
pub fn test_http_client(response: Response(String)) -> HttpClient {
  HttpClient(send: fn(_req) { Ok(response) })
}

/// Send an HTTP request using the client.
///
/// This is the main interface for making HTTP requests. It delegates
/// to the underlying implementation (real or test).
///
/// ## Parameters
///
/// - `client`: The HTTP client to use
/// - `request`: The HTTP request to send
///
/// ## Returns
///
/// A `Result` containing either:
/// - `Ok(Response(String))` on success
/// - `Error(httpc.HttpError)` on failure
pub fn send(
  client: HttpClient,
  request: Request(String),
) -> Result(Response(String), httpc.HttpError) {
  client.send(request)
}

/// Create a test HTTP client that returns an error.
///
/// This is useful for testing error handling paths.
///
/// ## Parameters
///
/// - `error`: The HttpError to return for all requests
///
/// ## Example
///
/// ```gleam
/// let client = http_client.test_error_client(httpc.ResponseTimeout)
/// ```
pub fn test_error_client(error: httpc.HttpError) -> HttpClient {
  HttpClient(send: fn(_req) { Error(error) })
}
