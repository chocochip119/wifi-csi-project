import test from 'node:test'
import assert from 'node:assert/strict'
import {mirrorPoseSides} from './poseOrientation.js'
import {solvePoseAngles} from './poseAngles.js'

const pairs = [[11,12],[13,14],[15,16],[23,24],[25,26],[27,28]]

function samplePose() {
  const joints = [
    [11,0.7,0], [12,0.3,0], [13,0.85,0.75], [14,0.2,0.8],
    [15,0.95,1.65], [16,0.1,1.7], [23,0.69,2], [24,0.31,2],
    [25,0.73,3.1], [26,0.29,3.3], [27,0.76,4.0], [28,0.28,4.25]
  ]
  return {valid:true, source_timestamp_us:1234, joints:joints.map(([id,x,y])=>({id,x,y}))}
}

test('one shared mirror exchanges all six anatomical left/right joint pairs', () => {
  const original = samplePose()
  const transformed = mirrorPoseSides(original)
  const before = new Map(original.joints.map(j=>[j.id,j]))
  const after = new Map(transformed.joints.map(j=>[j.id,j]))
  for (const [left,right] of pairs) {
    assert.equal(after.get(left).x, -before.get(right).x)
    assert.equal(after.get(left).y, before.get(right).y)
    assert.equal(after.get(right).x, -before.get(left).x)
    assert.equal(after.get(right).y, before.get(left).y)
  }
  assert.equal(transformed.source_timestamp_us, original.source_timestamp_us)
  assert.equal(before.get(11).x, 0.7, 'never mutate source CNN data')
})

test('mirroring twice restores original joint coordinates', () => {
  const original = samplePose()
  assert.deepEqual(mirrorPoseSides(mirrorPoseSides(original)), original)
  assert.equal(mirrorPoseSides(original, false), original)
})

test('the shared reflection preserves foot-spacing ratio and switches leg sides', () => {
  const original = samplePose()
  const baseline = solvePoseAngles(original, false)
  const reflected = solvePoseAngles(mirrorPoseSides(original), false)
  assert.ok(baseline && reflected)
  assert.equal(reflected.footSpacingRatio, baseline.footSpacingRatio)
  assert.ok(Math.abs(reflected.liftL - baseline.liftR) < 1e-12)
  assert.ok(Math.abs(reflected.liftR - baseline.liftL) < 1e-12)
})

test('invalid poses are not fabricated', () => {
  assert.equal(mirrorPoseSides(null), null)
  const invalid = {valid:false}
  assert.equal(mirrorPoseSides(invalid), invalid)
})
