//// TLS Configuration Tests
////
//// Tests for TLS configuration propagation from Config through WorkerState to gRPC.

import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import hatchet/internal/config
import hatchet/internal/tls

pub fn main() {
  gleeunit.main()
}

// ============================================================================
// TLS Config Flow Tests
// ============================================================================

pub fn tls_config_insecure_test() {
  // Test that Insecure config is properly handled
  let tls_config = tls.Insecure
  tls_config |> should.equal(tls.Insecure)
}

pub fn tls_config_tls_test() {
  // Test that Tls config stores CA path
  let tls_config = tls.Tls(ca_path: "/path/to/ca.pem")
  case tls_config {
    tls.Tls(ca) -> ca |> should.equal("/path/to/ca.pem")
    _ -> should.be_false(True)
  }
}

pub fn tls_config_mtls_test() {
  // Test that Mtls config stores all paths
  let tls_config =
    tls.Mtls(
      ca_path: "/path/to/ca.pem",
      cert_path: "/path/to/client.pem",
      key_path: "/path/to/key.pem",
    )

  case tls_config {
    tls.Mtls(ca, cert, key) -> {
      ca |> should.equal("/path/to/ca.pem")
      cert |> should.equal("/path/to/client.pem")
      key |> should.equal("/path/to/key.pem")
    }
    _ -> should.be_false(True)
  }
}

pub fn tls_config_from_parts_none_test() {
  // Test that from_parts returns Insecure when no paths provided
  let result = tls.from_parts(None, None, None)

  case result {
    Ok(tls.Insecure) -> should.be_true(True)
    _ -> should.be_false(True)
  }
}

pub fn tls_config_from_parts_tls_test() {
  // Test that from_parts returns Tls when only CA provided
  let result = tls.from_parts(Some("/ca.pem"), None, None)

  case result {
    Ok(tls.Tls(ca)) -> ca |> should.equal("/ca.pem")
    _ -> should.be_false(True)
  }
}

pub fn tls_config_from_parts_mtls_test() {
  // Test that from_parts returns Mtls when all paths provided
  let result =
    tls.from_parts(Some("/ca.pem"), Some("/cert.pem"), Some("/key.pem"))

  case result {
    Ok(tls.Mtls(ca, cert, key)) -> {
      ca |> should.equal("/ca.pem")
      cert |> should.equal("/cert.pem")
      key |> should.equal("/key.pem")
    }
    _ -> should.be_false(True)
  }
}

pub fn tls_config_from_parts_invalid_test() {
  // Test that from_parts returns error for invalid combinations
  let result = tls.from_parts(None, Some("/cert.pem"), None)

  case result {
    Error(tls.MissingCA) -> should.be_true(True)
    _ -> should.be_false(True)
  }
}

pub fn config_has_tls_test() {
  // Test that config.has_tls detects TLS configuration
  let cfg =
    config.Config(
      host: "localhost",
      port: 7070,
      grpc_port: 7077,
      token: Some("token"),
      namespace: None,
      tls_ca: Some("/ca.pem"),
      tls_cert: None,
      tls_key: None,
    )

  config.has_tls(cfg) |> should.be_true()
}

pub fn config_no_tls_test() {
  // Test that config.has_tls returns False when no TLS config
  let cfg =
    config.Config(
      host: "localhost",
      port: 7070,
      grpc_port: 7077,
      token: Some("token"),
      namespace: None,
      tls_ca: None,
      tls_cert: None,
      tls_key: None,
    )

  config.has_tls(cfg) |> should.be_false()
}

pub fn tls_is_secure_test() {
  // Test that is_secure correctly identifies secure configs
  tls.is_secure(tls.Insecure) |> should.be_false()
  tls.is_secure(tls.Tls(ca_path: "ca")) |> should.be_true()
  tls.is_secure(tls.Mtls(ca_path: "ca", cert_path: "c", key_path: "k"))
  |> should.be_true()
}

pub fn tls_ca_path_test() {
  // Test that ca_path extracts CA path when present
  case tls.ca_path(tls.Insecure) {
    None -> should.be_true(True)
    Some(_) -> should.be_false(True)
  }

  case tls.ca_path(tls.Tls(ca_path: "/ca.pem")) {
    Some(path) -> path |> should.equal("/ca.pem")
    None -> should.be_false(True)
  }

  case
    tls.ca_path(tls.Mtls(ca_path: "/ca.pem", cert_path: "c", key_path: "k"))
  {
    Some(path) -> path |> should.equal("/ca.pem")
    None -> should.be_false(True)
  }
}

pub fn tls_client_certs_test() {
  // Test that client_certs extracts client cert paths when present
  case tls.client_certs(tls.Insecure) {
    None -> should.be_true(True)
    Some(_) -> should.be_false(True)
  }

  case tls.client_certs(tls.Tls(ca_path: "ca")) {
    None -> should.be_true(True)
    Some(_) -> should.be_false(True)
  }

  case
    tls.client_certs(tls.Mtls(
      ca_path: "ca",
      cert_path: "/cert.pem",
      key_path: "/key.pem",
    ))
  {
    Some(#(cert, key)) -> {
      cert |> should.equal("/cert.pem")
      key |> should.equal("/key.pem")
    }
    None -> should.be_false(True)
  }
}
