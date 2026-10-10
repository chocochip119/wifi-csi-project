import test from 'node:test'
import assert from 'node:assert/strict'
import {createEditorPreset} from '../src/poseEditor.js'
import {FOOT_STANCE_MIN,FOOT_STANCE_MAX,solvePoseAngles} from '../src/poseAngles.js'

function setFootSpan(ratio,preset='stand') {
  const pose=createEditorPreset(preset)
  const points=new Map(pose.joints.map(j=>[j.id,j]))
  const hipL=points.get(23),hipR=points.get(24)
  const center=(hipL.x+hipR.x)/2
  const half=(hipR.x-hipL.x)*ratio/2
  points.get(27).x=center-half
  points.get(28).x=center+half
  return pose
}

test('feet never spread beyond the pelvis and cannot overlap',()=>{
  const narrow=solvePoseAngles(setFootSpan(0.05))
  const wide=solvePoseAngles(setFootSpan(2))
  assert.equal(narrow.footSpacingRatio,FOOT_STANCE_MIN)
  assert.equal(wide.footSpacingRatio,FOOT_STANCE_MAX)
  assert.equal(FOOT_STANCE_MAX,1)
})

test('ankles within the range retain the expected ratio after mirroring',()=>{
  const pose=setFootSpan(0.8)
  assert.ok(Math.abs(solvePoseAngles(pose).footSpacingRatio-0.8)<1e-8)
  assert.ok(Math.abs(solvePoseAngles(pose,true).footSpacingRatio-0.8)<1e-8)
})

test('pelvis-width limit also applies to squat poses',()=>{
  assert.equal(solvePoseAngles(setFootSpan(3,'squat')).footSpacingRatio,FOOT_STANCE_MAX)
})

test('near-zero horizontal pelvis width does not produce an unstable stance',()=>{
  const pose=setFootSpan(0.8)
  const l=pose.joints.find(j=>j.id===23),r=pose.joints.find(j=>j.id===24)
  r.x=l.x
  assert.equal(solvePoseAngles(pose)?.footSpacingRatio,null)
})
