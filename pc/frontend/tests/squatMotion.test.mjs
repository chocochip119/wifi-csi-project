import test from 'node:test'
import assert from 'node:assert/strict'
import { estimateSquatStrength } from '../src/squatMotion.js'

const pose = (left, right, kneeL = 0, kneeR = 0, liftL = 0, liftR = 0) =>
  estimateSquatStrength({spanL:left,spanR:right,kneeFlexL:kneeL,kneeFlexR:kneeR,liftL,liftR})

test('upright legs give zero squat intensity', () => {
  assert.equal(pose(1.20,1.18),0)
})
test('both compressed projected legs indicate a deep squat', () => {
  assert.ok(pose(.84,.88)>.7)
})
test('half crouch produces intermediate continuous intensity', () => {
  const half=pose(.98,1.00)
  assert.ok(half>.3 && half<.6)
})
test('raising only one leg is not a squat', () => {
  assert.equal(pose(.55,1.18),0)
})
test('both bending knees reinforces front-projection crouch', () => {
  const b=pose(1.14,1.14,.85,.9)
  assert.ok(b>.4 && b<.7)
})
test('leg-lift evidence suppresses squat detection', () => {
  assert.ok(pose(.85,.9,0,0,.8,0)<.25)
})
test('invalid numeric inputs are safe', () => {
  assert.equal(pose(NaN,1.1),0)
  assert.equal(pose(Infinity,1.1),0)
})
