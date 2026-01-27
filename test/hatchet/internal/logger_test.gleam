//// Logger Module Tests

import gleam/dict
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import hatchet/internal/logger.{Debug, ErrorLevel, Info, Warning}

pub fn main() {
  gleeunit.main()
}

// ============================================================================
// Log Level Tests
// ============================================================================

pub fn level_to_string_debug_test() {
  logger.level_to_string(Debug) |> should.equal("DEBUG")
}

pub fn level_to_string_info_test() {
  logger.level_to_string(Info) |> should.equal("INFO")
}

pub fn level_to_string_warning_test() {
  logger.level_to_string(Warning) |> should.equal("WARN")
}

pub fn level_to_string_error_test() {
  logger.level_to_string(ErrorLevel) |> should.equal("ERROR")
}

pub fn level_from_string_debug_test() {
  logger.level_from_string("debug") |> should.equal(Ok(Debug))
  logger.level_from_string("DEBUG") |> should.equal(Ok(Debug))
}

pub fn level_from_string_info_test() {
  logger.level_from_string("info") |> should.equal(Ok(Info))
  logger.level_from_string("INFO") |> should.equal(Ok(Info))
}

pub fn level_from_string_warning_test() {
  logger.level_from_string("warning") |> should.equal(Ok(Warning))
  logger.level_from_string("warn") |> should.equal(Ok(Warning))
  logger.level_from_string("WARN") |> should.equal(Ok(Warning))
}

pub fn level_from_string_error_test() {
  logger.level_from_string("error") |> should.equal(Ok(ErrorLevel))
  logger.level_from_string("ERROR") |> should.equal(Ok(ErrorLevel))
}

pub fn level_from_string_invalid_test() {
  logger.level_from_string("invalid") |> should.equal(Error(Nil))
  logger.level_from_string("") |> should.equal(Error(Nil))
}

pub fn level_value_ordering_test() {
  // Debug < Info < Warning < ErrorLevel
  should.be_true(logger.level_value(Debug) < logger.level_value(Info))
  should.be_true(logger.level_value(Info) < logger.level_value(Warning))
  should.be_true(logger.level_value(Warning) < logger.level_value(ErrorLevel))
}

// ============================================================================
// Logger Configuration Tests
// ============================================================================

pub fn default_config_test() {
  let config = logger.default_config()
  config.min_level |> should.equal(Info)
  config.include_timestamp |> should.equal(True)
  config.prefix |> should.equal(None)
}

pub fn debug_config_test() {
  let config = logger.debug_config()
  config.min_level |> should.equal(Debug)
}

pub fn production_config_test() {
  let config = logger.production_config()
  config.min_level |> should.equal(Warning)
}

pub fn with_min_level_test() {
  let config =
    logger.default_config()
    |> logger.with_min_level(ErrorLevel)
  config.min_level |> should.equal(ErrorLevel)
}

pub fn with_timestamp_test() {
  let config =
    logger.default_config()
    |> logger.with_timestamp(False)
  config.include_timestamp |> should.equal(False)
}

pub fn with_prefix_test() {
  let config =
    logger.default_config()
    |> logger.with_prefix("hatchet")
  config.prefix |> should.equal(Some("hatchet"))
}

// ============================================================================
// Logger Instance Tests
// ============================================================================

pub fn new_logger_test() {
  let log = logger.new()
  // Should have default config and empty context
  log.config.min_level |> should.equal(Info)
  dict.size(log.context) |> should.equal(0)
}

pub fn new_with_config_test() {
  let config = logger.production_config()
  let log = logger.new_with_config(config)
  log.config.min_level |> should.equal(Warning)
}

pub fn with_context_test() {
  let log =
    logger.new()
    |> logger.with_context("worker_id", "worker-123")

  dict.get(log.context, "worker_id") |> should.equal(Ok("worker-123"))
}

pub fn with_contexts_test() {
  let log =
    logger.new()
    |> logger.with_contexts([
      #("worker_id", "worker-123"),
      #("workflow", "order-process"),
    ])

  dict.size(log.context) |> should.equal(2)
  dict.get(log.context, "worker_id") |> should.equal(Ok("worker-123"))
  dict.get(log.context, "workflow") |> should.equal(Ok("order-process"))
}

pub fn child_logger_test() {
  let parent =
    logger.new()
    |> logger.with_context("worker_id", "worker-123")

  let child =
    parent
    |> logger.child("task", "charge-payment")

  // Child should have both parent and own context
  dict.size(child.context) |> should.equal(2)
  dict.get(child.context, "worker_id") |> should.equal(Ok("worker-123"))
  dict.get(child.context, "task") |> should.equal(Ok("charge-payment"))
}

// ============================================================================
// Logging Function Tests (Output Tests)
// ============================================================================

pub fn log_functions_exist_test() {
  // Just verify the functions can be called without crashing
  let log = logger.new()

  // These should not crash
  logger.debug(log, "Debug message")
  logger.info(log, "Info message")
  logger.warning(log, "Warning message")
  logger.error(log, "ErrorLevel message")

  should.be_true(True)
}

pub fn log_with_extra_context_test() {
  let log = logger.new()
  let extra = dict.from_list([#("request_id", "req-456")])

  // These should not crash
  logger.info_with(log, "Request received", extra)
  logger.error_with(log, "Request failed", extra)

  should.be_true(True)
}

// ============================================================================
// Simple Logging Functions Tests
// ============================================================================

pub fn simple_log_functions_test() {
  // These should not crash
  logger.log_debug("Debug message")
  logger.log_info("Info message")
  logger.log_warning("Warning message")
  logger.log_error("ErrorLevel message")

  should.be_true(True)
}
