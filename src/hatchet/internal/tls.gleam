////!
//// TLS configuration options for Hatchet connections.
////
//// This type defines the three levels of TLS security available:
////
//// - `Insecure` - Plain HTTP/gRPC without encryption (development only)
//// - `Tls` - Encrypted connection with server verification
//// - `Mtls` - Encrypted connection with mutual authentication
////
//// ## Examples
////
//// ```gleam
//// // No TLS (localhost development)
//// let insecure = tls.Insecure
////
//// // TLS with server verification
//// let tls_config = tls.Tls(ca_path: "/path/to/ca.pem")
////
//// // Mutual TLS with client certificates
//// let mtls_config = tls.Mtls(
////   ca_path: "/path/to/ca.pem",
////   cert_path: "/path/to/client.pem",
////   key_path: "/path/to/client-key.pem",
//// )
//// ```
//// Check if this configuration uses TLS (either Tls or Mtls).
////
//// **Returns:** `True` if TLS is enabled, `False` for Insecure
////
//// ## Examples
////
//// ```gleam
//// tls.is_secure(tls.Insecure) // False
//// tls.is_secure(tls.Tls(ca_path: "ca.pem")) // True
//// tls.is_secure(tls.Mtls(ca_path: "ca", cert_path: "c", key_path: "k")) // True
//// ```
//// Get the CA certificate path if configured.
////
//// **Returns:** `Some(path)` if CA path is configured, `None` otherwise
////
//// ## Examples
////
//// ```gleam
//// tls.ca_path(tls.Insecure) // None
//// tls.ca_path(tls.Tls(ca_path: "/etc/ssl/ca.pem")) // Some("/etc/ssl/ca.pem")
//// ```
//// Get the client certificate paths if using mTLS.
////
//// **Returns:** `Some((cert_path, key_path))` if mTLS is configured, `None` otherwise
////
//// ## Examples
////
//// ```gleam
//// tls.client_certs(tls.Insecure) // None
//// tls.client_certs(tls.Tls(ca_path: "ca")) // None
//// tls.client_certs(tls.Mtls(ca_path: "ca", cert_path: "c", key_path: "k"))
//// // Some(("c", "k"))
//// ```
//// Convert this TLS config to the format expected by the gRPC client.
////
//// This returns a tuple representation suitable for passing to Erlang functions.
////
//// **Returns:** A tuple representing the TLS configuration
//// Internal representation for gRPC options.
////
//// This type mirrors the structure expected by grpcbox channel options.
//// Create a TLS config from individual components.
////
//// This is a convenience function for building TLS configs programmatically.
////
//// **Parameters:**
////   - `ca_path` - Optional CA certificate path
////   - `cert_path` - Optional client certificate path
////   - `key_path` - Optional client private key path
////
//// **Returns:** Appropriate TLSConfig based on provided values
////
//// ## Logic
////
//// - If no paths provided: `Insecure`
//// - If only CA provided: `Tls`
//// - If all paths provided: `Mtls`
//// - If cert/key but no CA: Returns `Error` (invalid configuration)
//// Errors that can occur when building TLS configuration.

//! This module provides types and functions for configuring TLS/mTLS
//! connections for both REST API and gRPC communications with Hatchet.
//!
//! ## Configuration Options
//!
//! - `Insecure` - No TLS encryption (development only)
//! - `Tls` - TLS with server certificate verification
//! - `Mtls` - Mutual TLS with client certificate authentication
//!
//! ## Usage
//!
//! ```gleam
//! import hatchet/internal/tls
//!
//! // Development - no TLS
//! let config = tls.Insecure
//!
//! // Production - TLS with CA certificate
//! let config = tls.Tls(ca_path: "/etc/ssl/certs/ca.pem")
//!
//! // Production with mTLS - client certificate required
//! let config = tls.Mtls(
//!   ca_path: "/etc/ssl/certs/ca.pem",
//!   cert_path: "/etc/hatchet/client.pem",
//!   key_path: "/etc/hatchet/client-key.pem",
//! )
//! ```

/// TLS Configuration Module
///
import gleam/option.{type Option, None, Some}

pub type TLSConfig {
  /// No TLS encryption. Only use for local development!
  Insecure

  /// TLS with server certificate verification.
  ///
  /// **Parameters:**
  ///   - `ca_path` - Path to the CA certificate file for server verification
  Tls(ca_path: String)

  /// Mutual TLS with both server and client certificate verification.
  ///
  /// **Parameters:**
  ///   - `ca_path` - Path to the CA certificate file
  ///   - `cert_path` - Path to the client certificate file
  ///   - `key_path` - Path to the client private key file
  Mtls(ca_path: String, cert_path: String, key_path: String)
}

pub fn is_secure(config: TLSConfig) -> Bool {
  case config {
    Insecure -> False
    _ -> True
  }
}

pub fn ca_path(config: TLSConfig) -> Option(String) {
  case config {
    Tls(ca) | Mtls(ca, _, _) -> Some(ca)
    Insecure -> None
  }
}

pub fn client_certs(config: TLSConfig) -> Option(#(String, String)) {
  case config {
    Mtls(_, cert, key) -> Some(#(cert, key))
    _ -> None
  }
}

pub fn to_grpc_opts(config: TLSConfig) -> GrpcOpts {
  case config {
    Insecure -> GrpcOptsInsecure
    Tls(ca_path) -> GrpcOptsTls(ca_path)
    Mtls(ca_path, cert_path, key_path) ->
      GrpcOptsMtls(ca_path: ca_path, cert_path: cert_path, key_path: key_path)
  }
}

pub type GrpcOpts {
  GrpcOptsInsecure
  GrpcOptsTls(String)
  GrpcOptsMtls(ca_path: String, cert_path: String, key_path: String)
}

pub fn from_parts(
  ca_path: Option(String),
  cert_path: Option(String),
  key_path: Option(String),
) -> Result(TLSConfig, TLSConfigError) {
  case ca_path, cert_path, key_path {
    None, None, None -> Ok(Insecure)
    Some(ca), None, None -> Ok(Tls(ca))
    Some(ca), Some(cert), Some(key) -> Ok(Mtls(ca, cert, key))
    None, Some(_), _ -> Error(MissingCA)
    _, Some(_), None -> Error(MissingKey)
    Some(_), None, Some(_) -> Error(MissingCert)
    None, None, Some(_) -> Error(MissingCA)
  }
}

pub type TLSConfigError {
  MissingCA
  MissingCert
  MissingKey
}
