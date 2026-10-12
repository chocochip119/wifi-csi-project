import test from 'node:test'
import assert from 'node:assert/strict'
import { FastPose2DFilter } from '../src/fastPose2D.js'

const ids = [11,12,13,14,15,16,23,24,25,26,27,28]
const original = (frame, wristY = .55) => ({
  valid:true, coordinate_space:'model_output', window_id:frame,
  source_timestamp_us:frame*100000,
  joints: ids.map(id => ({id,
    x: id === 11 ? .4 : id === 12 ? .6 : id === 23 ? .43 : id === 24 ? .57 : .5,
    y: id === 11 || id === 12 ? .2 : id === 23 || id === 24 ? .55 :
       id === 15 ? wristY : .73}))
})
const wrist = pose => pose.joints.find(j => j.id === 15).y

test('first valid 2D pose is shown immediately', () => {
  const filter = new FastPose2DFilter()
  const pose = original(1)
  assert.equal(filter.push(pose, 0), pose)
})
test('large live wrist gesture is immediate, with no 3-frame median hold', () => {
  const filter = new FastPose2DFilter(80)
  filter.push(original(1, .55), 0)
  const next = filter.push(original(2, .05), 100)
  assert.equal(wrist(next), .05)
})
test('small movement is EMA filtered with ~80ms time constant', () => {
  const filter = new FastPose2DFilter(80)
  filter.push(original(1, .55), 0)
  const next = filter.push(original(2, .54), 80)
  assert.ok(wrist(next) < .55 && wrist(next) > .54)
})
test('repeat window is not treated as new pose', () => {
  const filter = new FastPose2DFilter()
  filter.push(original(1), 0)
  const output = filter.push(original(2, .54), 100)
  assert.equal(filter.push(original(2, .04), 110), output)
})
test('invalid/missing pose clears stale pose', () => {
  const filter = new FastPose2DFilter()
  filter.push(original(1), 0)
  assert.equal(filter.push(null, 100), null)
  assert.equal(wrist(filter.push(original(2, .3), 200)), .3)
})
test('long gap clears stale filtered history', () => {
  const filter = new FastPose2DFilter()
  filter.push(original(1), 0)
  assert.equal(wrist(filter.push(original(2, .54), 1500)), .54)
})
test('never mutates CNN joint coordinates', () => {
  const filter = new FastPose2DFilter()
  filter.push(original(1), 0)
  const next = original(2, .54)
  const before = JSON.stringify(next)
  filter.push(next, 100)
  assert.equal(JSON.stringify(next), before)
})
