//// Structured logging for the Hatchet SDK.
////
//// This module provides a consistent logging interface with:
//// - Log levels (debug, info, warning, error)
//// - Structured context (key-value pairs)
//// - Formatted output suitable for production use

import gleam/dict.{type Dict}
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

// ============================================================================
// Log Levels
// ============================================================================

/// Log level enumeration, ordered from most to least verbose.
pub type LogLevel {
  Debug
  Info
  Warning
  ErrorLevel
}

/// Convert a log level to its string representation.
pub fn level_to_string(level: LogLevel) -> String {
  case level {
    Debug -> "DEBUG"
    Info -> "INFO"
    Warning -> "WARN"
    ErrorLevel -> "ERROR"
  }
}

/// Parse a log level from a string.
pub fn level_from_string(s: String) -> Result(LogLevel, Nil) {
  case string.lowercase(s) {
    "debug" -> Ok(Debug)
    "info" -> Ok(Info)
    "warn" | "warning" -> Ok(Warning)
    "error" -> Ok(ErrorLevel)
    _ -> Error(Nil)
  }
}

/// Compare log levels for filtering.
pub fn level_value(level: LogLevel) -> Int {
  case level {
    Debug -> 0
    Info -> 1
    Warning -> 2
    ErrorLevel -> 3
  }
}

// ============================================================================
// Logger Configuration
// ============================================================================

/// Logger configuration.
pub type LoggerConfig {
  LoggerConfig(
    /// Minimum log level to output
    min_level: LogLevel,
    /// Whether to include timestamps
    include_timestamp: Bool,
    /// Custom prefix for all log messages
    prefix: Option(String),
  )
}

/// Default logger configuration (Info level, with timestamps).
pub fn default_config() -> LoggerConfig {
  LoggerConfig(min_level: Info, include_timestamp: True, prefix: None)
}

/// Create a debug-level config (shows all messages).
pub fn debug_config() -> LoggerConfig {
  LoggerConfig(min_level: Debug, include_timestamp: True, prefix: None)
}

/// Create a production config (warnings and errors only).
pub fn production_config() -> LoggerConfig {
  LoggerConfig(min_level: Warning, include_timestamp: True, prefix: None)
}

/// Set the minimum log level.
pub fn with_min_level(config: LoggerConfig, level: LogLevel) -> LoggerConfig {
  LoggerConfig(..config, min_level: level)
}

/// Set whether to include timestamps.
pub fn with_timestamp(config: LoggerConfig, include: Bool) -> LoggerConfig {
  LoggerConfig(..config, include_timestamp: include)
}

/// Set a custom prefix.
pub fn with_prefix(config: LoggerConfig, prefix: String) -> LoggerConfig {
  LoggerConfig(..config, prefix: Some(prefix))
}

// ============================================================================
// Logger Type
// ============================================================================

/// A configured logger instance.
pub type Logger {
  Logger(config: LoggerConfig, context: Dict(String, String))
}

/// Create a new logger with default configuration.
pub fn new() -> Logger {
  Logger(config: default_config(), context: dict.new())
}

/// Create a new logger with custom configuration.
pub fn new_with_config(config: LoggerConfig) -> Logger {
  Logger(config: config, context: dict.new())
}

/// Add context to the logger (returns a new logger).
pub fn with_context(logger: Logger, key: String, value: String) -> Logger {
  Logger(..logger, context: dict.insert(logger.context, key, value))
}

/// Add multiple context pairs at once.
pub fn with_contexts(
  logger: Logger,
  contexts: List(#(String, String)),
) -> Logger {
  let new_context =
    list.fold(contexts, logger.context, fn(ctx, pair) {
      dict.insert(ctx, pair.0, pair.1)
    })
  Logger(..logger, context: new_context)
}

/// Create a child logger with additional context.
pub fn child(logger: Logger, key: String, value: String) -> Logger {
  with_context(logger, key, value)
}

// ============================================================================
// Logging Functions
// ============================================================================

/// Log a debug message.
pub fn debug(logger: Logger, message: String) -> Nil {
  log(logger, Debug, message, dict.new())
}

/// Log a debug message with additional context.
pub fn debug_with(
  logger: Logger,
  message: String,
  extra: Dict(String, String),
) -> Nil {
  log(logger, Debug, message, extra)
}

/// Log an info message.
pub fn info(logger: Logger, message: String) -> Nil {
  log(logger, Info, message, dict.new())
}

/// Log an info message with additional context.
pub fn info_with(
  logger: Logger,
  message: String,
  extra: Dict(String, String),
) -> Nil {
  log(logger, Info, message, extra)
}

/// Log a warning message.
pub fn warning(logger: Logger, message: String) -> Nil {
  log(logger, Warning, message, dict.new())
}

/// Log a warning message with additional context.
pub fn warning_with(
  logger: Logger,
  message: String,
  extra: Dict(String, String),
) -> Nil {
  log(logger, Warning, message, extra)
}

/// Log an error message.
pub fn error(logger: Logger, message: String) -> Nil {
  log(logger, ErrorLevel, message, dict.new())
}

/// Log an error message with additional context.
pub fn error_with(
  logger: Logger,
  message: String,
  extra: Dict(String, String),
) -> Nil {
  log(logger, ErrorLevel, message, extra)
}

/// Core logging function.
fn log(
  logger: Logger,
  level: LogLevel,
  message: String,
  extra: Dict(String, String),
) -> Nil {
  // Check if we should log at this level
  case level_value(level) >= level_value(logger.config.min_level) {
    False -> Nil
    True -> {
      // Build the log line
      let line = build_log_line(logger, level, message, extra)
      io.println(line)
    }
  }
}

/// Build a formatted log line.
fn build_log_line(
  logger: Logger,
  level: LogLevel,
  message: String,
  extra: Dict(String, String),
) -> String {
  let parts = []

  // Add timestamp if configured
  let parts = case logger.config.include_timestamp {
    True -> [get_timestamp(), ..parts]
    False -> parts
  }

  // Add prefix if configured
  let parts = case logger.config.prefix {
    Some(prefix) -> ["[" <> prefix <> "]", ..parts]
    None -> parts
  }

  // Add level
  let parts = ["[" <> level_to_string(level) <> "]", ..parts]

  // Add message
  let parts = [message, ..parts]

  // Add context if any
  let all_context = dict.merge(logger.context, extra)
  let parts = case dict.size(all_context) > 0 {
    True -> [format_context(all_context), ..parts]
    False -> parts
  }

  // Reverse and join
  list.reverse(parts)
  |> string.join(" ")
}

/// Format context as key=value pairs.
fn format_context(context: Dict(String, String)) -> String {
  dict.fold(context, [], fn(acc, key, value) { [key <> "=" <> value, ..acc] })
  |> list.reverse
  |> string.join(" ")
}

/// Get the current timestamp as a string.
fn get_timestamp() -> String {
  // Simple timestamp - in production would use proper datetime formatting
  let ts = get_unix_timestamp()
  int_to_string(ts)
}

@external(erlang, "erlang", "system_time")
fn do_system_time(unit: a) -> Int

fn get_unix_timestamp() -> Int {
  do_system_time(Second)
}

type TimeUnit {
  Second
}

@external(erlang, "erlang", "integer_to_binary")
fn int_to_string(n: Int) -> String

// ============================================================================
// Convenience Functions for Simple Logging
// ============================================================================

/// Simple info log (uses default logger).
pub fn log_info(message: String) -> Nil {
  io.println("[INFO] " <> message)
}

/// Simple warning log (uses default logger).
pub fn log_warning(message: String) -> Nil {
  io.println("[WARN] " <> message)
}

/// Simple error log (uses default logger).
pub fn log_error(message: String) -> Nil {
  io.println("[ERROR] " <> message)
}

/// Simple debug log (uses default logger).
pub fn log_debug(message: String) -> Nil {
  io.println("[DEBUG] " <> message)
}
