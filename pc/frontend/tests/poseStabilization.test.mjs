import test from 'node:test'
import assert from 'node:assert/strict'
import { PoseViewportStabilizer, RigAngleStabilizer, RigJointStabilizer } from '../src/poseStabilization.js'

const skel = (scale = 1, shift = 0) => new Map([
  [11, {x: 0.2 * scale + shift, y: 0.1 * scale}],
  [12, {x: 0.8 * scale + shift, y: 0.1 * scale}],
  [23, {x: 0.3 * scale + shift, y: 0.5 * scale}],
  [24, {x: 0.7 * scale + shift, y: 0.5 * scale}],
  [27, {x: 0.2 * scale + shift, y: 1.1 * scale}],
  [28, {x: 0.8 * scale + shift, y: 1.1 * scale}]
])
const solution = (angle, squat = 0) => ({
  directions: new Map([['upperArmL',{ angle, length: 1 }],['forearmL',{ angle, length: 1 }]]),
  squat, liftL:0, liftR:0, footSpacingRatio:1.0,
  point: new Map(), torso:1, activity:0
})

test('2D viewport stays fixed for small jitter and smooths large changes', () => {
  const v = new PoseViewportStabilizer()
  const first = v.update(skel(1), 1000)
  const after = v.update(skel(1.03, 0.002), 1150)
  assert.ok(Math.abs(after.scale-first.scale) < 1e-7)
  assert.ok(Math.abs(after.centerX-first.centerX) < 1e-7)
  const moved = v.update(skel(1, 0.3), 1300)
  assert.ok(moved.centerX > first.centerX)
  assert.ok(moved.centerX < first.centerX + 0.3)
})
test('viewport can reset after missing pose or new replay', () => {
  const v = new PoseViewportStabilizer()
  v.update(skel(), 1000)
  v.reset()
  assert.equal(v.update(skel(1, 2), 1200).centerX, 2.5)
})
test('3D limb angle holds through small jitter, responds to real gesture', () => {
  const f = new RigAngleStabilizer()
  const start = f.push(solution(0.5), false, 1000)
  assert.equal(start.directions.get('forearmL').angle, 0.5)
  const small = f.push(solution(0.55), false, 1150)
  assert.equal(small.directions.get('forearmL').angle, 0.5)
  const large = f.push(solution(1.0), false, 1300)
  assert.ok(large.directions.get('forearmL').angle > 0.5)
  assert.ok(large.directions.get('forearmL').angle < 1.0)
  const changedMirror = f.push(solution(-0.7), true, 1450)
  assert.equal(changedMirror.directions.get('forearmL').angle, -0.7)
})
test('3D squat signal does not hunt around threshold but follows big change', () => {
  const f = new RigAngleStabilizer()
  f.push(solution(0, 0.4), false, 1000)
  assert.equal(f.push(solution(0, 0.43), false, 1150).squat, 0.4)
  const changed = f.push(solution(0, 0.95), false, 1300)
  assert.ok(changed.squat > 0.4 && changed.squat < 0.95)
})

const makePose = (wristOffset=0, version=1) => ({
  valid: true, coordinate_space:'model_output', end_trigger_seq:version,
  joints: [
    {id:11,x:0.4,y:0.2},{id:12,x:0.6,y:0.2},
    {id:13,x:0.38,y:0.32},{id:14,x:0.62,y:0.32},
    {id:15,x:0.36+wristOffset,y:0.42},{id:16,x:0.64,y:0.42},
    {id:23,x:0.45,y:0.5},{id:24,x:0.55,y:0.5},
    {id:25,x:0.45,y:0.7},{id:26,x:0.55,y:0.7},
    {id:27,x:0.45,y:0.9},{id:28,x:0.55,y:0.9} ]
})
test('3D IK input holds a small wrist tremble but follows a large gesture', () => {
  const f=new RigJointStabilizer()
  const raw0=makePose(0,1)
  const initial=f.push(raw0)
  const tiny=f.push(makePose(0.004,2))
  assert.equal(tiny.joints[4].x, initial.joints[4].x)
  const large=f.push(makePose(0.16,3))
  assert.ok(large.joints[4].x>initial.joints[4].x+0.1)
  assert.equal(raw0.joints[4].x, 0.36, 'do not edit raw model output')
})
test('3D IK input does not process same prediction twice', () => {
  const f=new RigJointStabilizer()
  f.push(makePose(0.0,1))
  const out=f.push(makePose(0.3,2))
  assert.strictEqual(f.push(makePose(-0.4,2)),out)
  const flipped=f.push(makePose(-0.4,2),true)
  assert.ok(Math.abs(flipped.joints[4].x + 0.04) < 1e-10)
})
