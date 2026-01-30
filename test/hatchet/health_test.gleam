import gleam/string
import gleeunit/should
import hatchet/health

pub fn default_config_returns_valid_config_test() {
  let config = health.default_config()

  config.port
  |> should.equal(8080)

  config.enabled
  |> should.equal(True)
}

pub fn health_config_has_required_fields_test() {
  let config = health.HealthConfig(port: 9090, enabled: False)

  config.port
  |> should.equal(9090)

  config.enabled
  |> should.equal(False)
}

pub fn health_config_supports_custom_port_test() {
  let config = health.HealthConfig(port: 3000, enabled: True)

  config.port
  |> should.equal(3000)
}

pub fn health_config_supports_enabled_flag_test() {
  let enabled_config = health.HealthConfig(port: 8080, enabled: True)
  let disabled_config = health.HealthConfig(port: 8080, enabled: False)

  enabled_config.enabled
  |> should.equal(True)

  disabled_config.enabled
  |> should.equal(False)
}

pub fn check_returns_healthy_status_test() {
  let status = health.check()

  case status {
    health.Healthy -> should.be_true(True)
    health.Unhealthy(_) -> should.be_true(False)
  }
}

pub fn unhealthy_status_contains_reason_test() {
  let status = health.Unhealthy("Connection failed")

  case status {
    health.Healthy -> should.be_true(False)
    health.Unhealthy(reason) -> {
      reason
      |> should.equal("Connection failed")
    }
  }
}

pub fn start_server_returns_error_for_missing_dependencies_test() {
  let config = health.default_config()

  case health.start_server(config) {
    Ok(_) -> should.be_true(False)
    Error(e) -> {
      string.contains(e, "external dependencies")
      |> should.equal(True)
    }
  }
}

pub fn health_check_is_idempotent_test() {
  let status1 = health.check()
  let status2 = health.check()

  case status1, status2 {
    health.Healthy, health.Healthy -> should.be_true(True)
    _, _ -> should.be_true(False)
  }
}

pub fn health_status_distinguishes_status_types_test() {
  let healthy_status = health.Healthy
  let unhealthy_status = health.Unhealthy("Error")

  let is_healthy = case healthy_status {
    health.Healthy -> True
    _ -> False
  }

  let is_unhealthy = case unhealthy_status {
    health.Unhealthy(_) -> True
    _ -> False
  }

  is_healthy
  |> should.equal(True)

  is_unhealthy
  |> should.equal(True)
}
