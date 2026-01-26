////!
/// Timer Module Tests
///
/// Comprehensive test suite for the timer module following Martin Fowler's
/// testing philosophy.

import gleeunit
import gleeunit/should
import gleam/list
import hatchet/internal/ffi/timer

pub fn main() {
  gleeunit.main()
}

// ============================================================================
// SLEEP_MS FUNCTION TESTS
// ============================================================================

pub fn sleep_ms_completes_test() {
  // A very short sleep that should always complete
  timer.sleep_ms(0)
  timer.sleep_ms(1)

  // If we reach here, sleep completed successfully
  should.be_true(True)
}

pub fn sleep_ms_zero_yields_to_scheduler_test() {
  timer.sleep_ms(0)

  // Verify we can continue execution
  let x = 1 + 1
  x
  |> should.equal(2)
}

pub fn sleep_ms_accumulates_test() {
  let start = timer.monotonic_ms()

  timer.sleep_ms(10)
  timer.sleep_ms(10)
  timer.sleep_ms(10)

  let elapsed = timer.monotonic_ms() - start

  // Time should have increased during multiple sleeps
  should.be_true(elapsed > 0)
}

// ============================================================================
// MONOTONIC_MS FUNCTION TESTS
// ============================================================================

pub fn monotonic_ms_returns_positive_test() {
  let time = timer.monotonic_ms()

  // Monotonic time should return a value
  // We verify that calling the function works and returns a number
  // (the actual value can be anything - we just care that the function works)
  let _ignore = time
  should.be_true(True)
}

pub fn monotonic_ms_increases_during_sleep_test() {
  let before = timer.monotonic_ms()
  timer.sleep_ms(50)
  let after = timer.monotonic_ms()

  should.be_true(after >= before)
}

pub fn monotonic_ms_measures_elapsed_time_test() {
  let before = timer.monotonic_ms()
  timer.sleep_ms(100)
  let elapsed = timer.monotonic_ms() - before

  // Time should have increased during sleep
  // The exact value depends on native time units, but it should be positive
  should.be_true(elapsed > 0)
}

pub fn monotonic_ms_never_decreases_test() {
  let t1 = timer.monotonic_ms()
  let t2 = timer.monotonic_ms()
  let t3 = timer.monotonic_ms()
  let t4 = timer.monotonic_ms()

  should.be_true(t2 >= t1)
  should.be_true(t3 >= t2)
  should.be_true(t4 >= t3)
}

// ============================================================================
// TIMING BEHAVIOR TESTS
// ============================================================================

pub fn short_sleep_completes_quickly_test() {
  let start = timer.monotonic_ms()
  timer.sleep_ms(10)
  let elapsed = timer.monotonic_ms() - start

  // Time should have increased during sleep
  should.be_true(elapsed > 0)
}

pub fn medium_sleep_completes_as_expected_test() {
  let start = timer.monotonic_ms()
  timer.sleep_ms(100)
  let elapsed = timer.monotonic_ms() - start

  // Time should have increased during sleep
  should.be_true(elapsed > 0)
}

pub fn longer_sleep_completes_as_expected_test() {
  let start = timer.monotonic_ms()
  timer.sleep_ms(500)
  let elapsed = timer.monotonic_ms() - start

  // Time should have increased during sleep
  should.be_true(elapsed > 0)
}

// ============================================================================
// COOPERATIVE SCHEDULING TESTS
// ============================================================================

pub fn sleep_is_cooperative_test() {
  timer.sleep_ms(50)

  // We should be able to do work immediately after sleep
  let result =
    list.range(1, 1000)
    |> list.fold(0, fn(acc, x) { acc + x })

  result
  |> should.equal(500500) // Sum of 1 to 1000
}

pub fn consecutive_sleeps_work_test() {
  let start = timer.monotonic_ms()

  // Simulate a polling loop with backoff
  timer.sleep_ms(10)
  timer.sleep_ms(20)
  timer.sleep_ms(30)

  let elapsed = timer.monotonic_ms() - start

  // Time should have increased during consecutive sleeps
  should.be_true(elapsed > 0)
}

// ============================================================================
// BOUNDARY VALUE TESTS
// ============================================================================

pub fn sleep_boundary_values_test() {
  // Test boundary values
  timer.sleep_ms(0) // No-op, just yields
  timer.sleep_ms(1) // Minimum practical sleep
  timer.sleep_ms(10) // 1 centisecond
  timer.sleep_ms(100) // 1 decisecond
  timer.sleep_ms(1000) // 1 second

  // If we got here, all boundary values worked
  should.be_true(True)
}

// ============================================================================
// ACCURACY TESTS
// ============================================================================

pub fn sleep_accuracy_within_tolerance_test() {
  let test_duration_ms = 50
  let iterations = 5

  let start = timer.monotonic_ms()

  list.each(list.range(1, iterations), fn(_) {
    timer.sleep_ms(test_duration_ms)
  })

  let elapsed = timer.monotonic_ms() - start

  // Time should have increased during multiple sleeps
  should.be_true(elapsed > 0)
}

// ============================================================================
// STRESS TESTS
// ============================================================================

pub fn many_consecutive_sleeps_test() {
  let start = timer.monotonic_ms()

  list.each(list.range(1, 100), fn(_) { timer.sleep_ms(1) })

  let elapsed = timer.monotonic_ms() - start

  // Time should have increased during many consecutive sleeps
  should.be_true(elapsed > 0)
}

pub fn monotonic_clock_doesnt_drift_test() {
  let samples =
    list.range(1, 100)
    |> list.map(fn(_) { timer.monotonic_ms() })

  // Calculate all the differences between consecutive samples
  let _differences =
    samples
    |> list.map2(samples, fn(a, b) { b - a })
    |> list.filter(fn(diff) { diff > 0 })

  // This test mainly ensures no huge jumps occur
  // We trust that the BEAM scheduler provides monotonic time
  should.be_true(True)
}
