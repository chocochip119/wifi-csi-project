import test from 'node:test'
import assert from 'node:assert/strict'
import { createEditorPreset } from '../src/poseEditor.js'
import { createTestPose } from '../src/poseTests.js'
import { classifyLiveThreeAction, LiveThreeActionLimiter } from '../src/liveThreeActions.js'

const frame=(name, n) => ({...createEditorPreset(name), window_id:n, source_timestamp_us:n*1000})

test('LIVE three-action mode detects standing, squat, and both-arm raise', () => {
  assert.equal(classifyLiveThreeAction(frame('stand',1)), 'stand')
  assert.equal(classifyLiveThreeAction(frame('squat',2)), 'squat')
  assert.equal(classifyLiveThreeAction(frame('bothArmsUp',3)), 'bothArmsUp')
})
test('other actions are not exposed as extra motion states', () => {
  assert.equal(classifyLiveThreeAction(createTestPose('armsWide')), 'stand')
  assert.equal(classifyLiveThreeAction(createTestPose('legLift')), 'stand')
  assert.equal(classifyLiveThreeAction(createTestPose('armUp')), 'stand')
})
test('invalid CNN input never creates a fake valid person', () => {
  const f = new LiveThreeActionLimiter()
  assert.equal(f.push(null), null)
  assert.equal(f.push({valid:false,joints:[]}), null)
  assert.equal(f.push({valid:true,joints:[]}), null)
})
test('three independent predictions are required before a posture switch', () => {
  const f=new LiveThreeActionLimiter({confirmFrames:3,minHoldMs:500})
  assert.equal(f.push(frame('stand',1),0).live_three_action,'stand')
  assert.equal(f.push(frame('bothArmsUp',2),700).live_three_action,'stand')
  assert.equal(f.push(frame('bothArmsUp',3),800).live_three_action,'stand')
  assert.equal(f.push(frame('bothArmsUp',4),900).live_three_action,'bothArmsUp')
  assert.equal(f.push(frame('stand',5),950).live_three_action,'bothArmsUp')
})
test('repeated snapshot is not counted as multiple distinct predictions', () => {
  const f=new LiveThreeActionLimiter({confirmFrames:2,minHoldMs:0})
  f.push(frame('stand',1),0)
  const a=f.push(frame('squat',2),100)
  const b=f.push(frame('squat',2),150)
  assert.equal(b, a)
  assert.equal(b.live_three_action,'stand')
  assert.equal(f.push(frame('squat',3),200).live_three_action,'squat')
})
test('canonical output is independent of the caller-owned CNN joints', () => {
  const input=frame('bothArmsUp',1)
  const before=JSON.stringify(input)
  const output=new LiveThreeActionLimiter().push(input,0)
  assert.equal(output.live_three_visualization,true)
  assert.equal(output.joints.length,12)
  assert.equal(output.source_timestamp_us,input.source_timestamp_us)
  assert.equal(output.coordinate_space,'fake_normalized')
  assert.equal(JSON.stringify(input), before)
  output.joints[0].x=999
  assert.notEqual(input.joints[0].x, 999)
})
test('invalid pose resets old action so missing person is never held indefinitely', () => {
  const f=new LiveThreeActionLimiter()
  f.push(frame('squat',1),0)
  f.push(null,100)
  assert.equal(f.push(frame('stand',2),200).live_three_action,'stand')
})
