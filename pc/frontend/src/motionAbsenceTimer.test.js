import test from 'node:test'
import assert from 'node:assert/strict'
import {MotionAbsenceTimer} from './motionAbsenceTimer.js'

test('continuous No person hides only after five seconds', () => {
  const timer = new MotionAbsenceTimer()
  assert.equal(timer.observe(true, 1000), false)
  assert.equal(timer.observe(true, 5999), false)
  assert.equal(timer.shouldHide(5999), false)
  assert.equal(timer.observe(true, 6000), true)
  assert.equal(timer.shouldHide(6200), true)
})

test('person returning cancels the pending absence timer', () => {
  const timer = new MotionAbsenceTimer()
  assert.equal(timer.observe(true, 0), false)
  assert.equal(timer.observe(false, 4999), false)
  assert.equal(timer.shouldHide(10000), false)
  assert.equal(timer.observe(true, 10000), false)
  assert.equal(timer.shouldHide(14999), false)
  assert.equal(timer.shouldHide(15000), true)
})

test('manual reset on mode change prevents stale hiding', () => {
  const timer = new MotionAbsenceTimer()
  timer.observe(true, 0)
  timer.reset()
  assert.equal(timer.shouldHide(9999), false)
  assert.equal(timer.observe(true, 12000), false)
  assert.equal(timer.shouldHide(17000), true)
})

test('unknown/unavailable result does not count as confirmed absence', () => {
  const timer = new MotionAbsenceTimer()
  timer.observe(true, 0)
  timer.observe(false, 3000)
  assert.equal(timer.shouldHide(8000), false)
})
