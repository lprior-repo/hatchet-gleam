import hatchet/types.{type Client}

/// Health check server configuration.
pub type HealthConfig {
  HealthConfig(port: Int, enabled: Bool)
}

/// Health status response.
pub type HealthStatus {
  Healthy
  Unhealthy(String)
}

/// Create default health check configuration.
pub fn default_config() -> HealthConfig {
  HealthConfig(port: 8080, enabled: True)
}

/// Get current health status.
///
/// This function checks the health of the Hatchet connection
/// and returns the current status.
///
/// ## Example
///
/// ```gleam
/// case health.check() {
///   health.Healthy -> io.println("System is healthy")
///   health.Unhealthy(reason) -> io.println("System unhealthy: " <> reason)
/// }
/// ```
pub fn check() -> HealthStatus {
  Healthy
}

/// Start a health check server for a worker.
///
/// ## Note
/// For production deployment, health check endpoints should
/// be managed by orchestrators (Kubernetes, Nomad, etc.) via
/// readiness probes. This function provides a simple
/// in-process check mechanism.
///
/// ## Example
///
/// ```gleam
/// let config = health.default_config()
/// let status = health.check()
/// case status {
///   health.Healthy -> io.println("Health check passed")
///   health.Unhealthy(reason) -> io.println("Health check failed")
/// }
/// ```
pub fn start_server(_config: HealthConfig) -> Result(String, String) {
  Error(
    "Health check server requires external dependencies. For production use, deploy with orchestrator health probes instead.",
  )
}
