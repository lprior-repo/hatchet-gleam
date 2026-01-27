//// Tests for new StepActionEventType variants

import gleeunit
import gleeunit/should
import hatchet/internal/ffi/protobuf

pub fn main() {
  gleeunit.main()
}

pub fn step_event_type_stream_test() {
  protobuf.step_event_type_to_int(protobuf.StepEventTypeStream)
  |> should.equal(5)
}

pub fn step_event_type_refresh_timeout_test() {
  protobuf.step_event_type_to_int(protobuf.StepEventTypeRefreshTimeout)
  |> should.equal(6)
}

pub fn step_event_type_cancelled_test() {
  protobuf.step_event_type_to_int(protobuf.StepEventTypeCancelled)
  |> should.equal(7)
}
