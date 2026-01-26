////!
//// Sleep for the specified number of milliseconds.
////
//// This function yields control to the BEAM scheduler, allowing other processes
//// to execute during the sleep period. It is cooperative and does not block
//// the entire VM.
////
//// **Parameters:**
////   - `milliseconds`: The number of milliseconds to sleep. Must be non-negative.
////
//// **Returns:** Nil
////
//// **Examples:**
//// ```gleam
//// // Sleep for 500 milliseconds
//// timer.sleep_ms(500)
////
//// // Sleep for 1 second
//// timer.sleep_ms(1000)
////
//// // Zero-length sleep (yields to scheduler)
//// timer.sleep_ms(0)
//// ```
////
//// **Performance Note:** This has a minimum resolution of approximately 1ms.
//// For sub-millisecond precision, consider using `erlang:send_after/3` directly.
////
//// **Thread Safety:** This is process-safe on the BEAM VM. Each calling process
//// sleeps independently without affecting others.
//// Get the current monotonic time in milliseconds.
////
//// This uses Erlang's `erlang:monotonic_time/1` which returns the monotonic time
//// in the specified time unit. Monotonic time always increases and is not affected
//// by system clock changes.
////
//// **Returns:** The current monotonic time in milliseconds.
////
//// **Examples:**
//// ```gleam
//// let start = timer.monotonic_ms()
//// timer.sleep_ms(100)
//// let elapsed = timer.monotonic_ms() - start
//// // elapsed >= 100
//// ```
////
//// **Use Case:** Use this for measuring elapsed time, timeouts, and intervals.
//// Do not use for wall-clock time (dates/timestamps).

//! This module provides cross-platform timer functionality using Gleam's
//! built-in time and process modules.
//!
//! ## Usage
//!
//! ```gleam
//! import hatchet/internal/ffi/timer
//!
//! // Sleep for 100 milliseconds
//! timer.sleep_ms(100)
//! ```
//!
//! ## Implementation Notes
//!
//! - Uses Gleam's `process.sleep/1` which yields to the BEAM scheduler
//! - The sleep is cooperative - other processes in the VM continue executing
//! - Minimum resolution is approximately 1ms
//! - Safe to use in actor loops and supervision trees
//! - Does not block the entire VM, only the current process

/// Timer FFI Module
///
import gleam/erlang/process

pub fn sleep_ms(milliseconds: Int) -> Nil {
  process.sleep(milliseconds)
}

pub fn monotonic_ms() -> Int {
  // Use erlang:monotonic_time(millisecond) directly via FFI
  // This returns the monotonic time in milliseconds as an integer
  do_erlang_monotonic_time()
}

// Direct FFI to erlang:monotonic_time(millisecond)
// The atom 'millisecond' is hardcoded in the Erlang wrapper
@external(erlang, "erlang", "monotonic_time")
fn do_erlang_monotonic_time() -> Int
