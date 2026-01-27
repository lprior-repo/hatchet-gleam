/// Default configuration constants for the Hatchet client.
///
/// This module contains well-defined constants for timeouts, retries,
/// and other configuration values to avoid magic numbers throughout
/// the codebase.
pub const default_base_backoff_ms = 1000

pub const default_max_backoff_ms = 60_000

pub const default_linear_backoff_step_ms = 2000

pub const default_constant_backoff_ms = 5000

pub const default_retry_attempts = 3

pub const default_poll_interval_ms = 500

pub const default_max_poll_attempts = 10

pub const default_timeout_ms = 30_000

pub const min_safe_port = 1024

pub const max_port = 65_535

pub const default_http_port = 7070

pub const default_worker_slots = 10

pub const default_durable_slots = 1
