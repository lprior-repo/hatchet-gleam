//// Rate Limits Module Tests

import gleeunit
import gleeunit/should
import hatchet/rate_limits

pub fn main() {
  gleeunit.main()
}

pub fn duration_types_exist_test() {
  // Verify all duration types can be constructed
  let _s = rate_limits.Second
  let _m = rate_limits.Minute
  let _h = rate_limits.Hour
  let _d = rate_limits.Day
  let _w = rate_limits.Week
  let _mo = rate_limits.Month
  let _y = rate_limits.Year
  should.be_true(True)
}
