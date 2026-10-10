import test from 'node:test'
import assert from 'node:assert/strict'
import {createEditorPreset} from '../src/poseEditor.js'
import {FOOT_STANCE_MIN,FOOT_STANCE_MAX,solvePoseAngles,hasMeaningfulArmPose} from '../src/poseAngles.js'

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

test('foot spacing stays within 55 to 150 percent of pelvis width',()=>{
  const narrow=solvePoseAngles(setFootSpan(0.05))
  const wide=solvePoseAngles(setFootSpan(2))
  assert.equal(narrow.footSpacingRatio,FOOT_STANCE_MIN)
  assert.equal(wide.footSpacingRatio,FOOT_STANCE_MAX)
  assert.equal(FOOT_STANCE_MAX,1.5)
})

test('ankles within the range retain the expected ratio after mirroring',()=>{
  const pose=setFootSpan(0.8)
  assert.ok(Math.abs(solvePoseAngles(pose).footSpacingRatio-0.8)<1e-8)
  assert.ok(Math.abs(solvePoseAngles(pose,true).footSpacingRatio-0.8)<1e-8)
})

test('150-percent pelvis stance limit also applies to squat poses',()=>{
  assert.equal(solvePoseAngles(setFootSpan(3,'squat')).footSpacingRatio,FOOT_STANCE_MAX)
})

test('near-zero horizontal pelvis width does not produce an unstable stance',()=>{
  const pose=setFootSpan(0.8)
  const l=pose.joints.find(j=>j.id===23),r=pose.joints.find(j=>j.id===24)
  r.x=l.x
  assert.equal(solvePoseAngles(pose)?.footSpacingRatio,null)
})

test('knee direction is derived from knee coordinate, not just ankle height',()=>{
  const a=createEditorPreset('legLift')
  const b=createEditorPreset('legLift')
  b.joints.find(j=>j.id===25).x-=0.15
  const first=solvePoseAngles(a)
  const second=solvePoseAngles(b)
  assert.ok(first?.kneeL && second?.kneeL)
  assert.ok(Math.abs(first.kneeL.lateral-second.kneeL.lateral)>0.05)
  assert.ok(Math.abs(first.kneeL.flex-second.kneeL.flex)>0.05)
})

test('mirroring flips the knee sideways direction but preserves its flex',()=>{
  const pose=createEditorPreset('legLift')
  const front=solvePoseAngles(pose)
  const mirrored=solvePoseAngles(pose,true)
  assert.ok(Math.abs(front.kneeL.lateral+mirrored.kneeL.lateral)<1e-8)
  assert.ok(Math.abs(front.kneeL.flex-mirrored.kneeL.flex)<1e-8)
})

test('natural idle arms stay neutral while deliberate arm movements enable IK',()=>{
  for(const name of ['stand','squat','legLift','wideLegs'])
    assert.equal(hasMeaningfulArmPose(createEditorPreset(name)),false,name)
  for(const name of ['armUp','armsWide','bothArmsUp','handsForward','leftElbowBent'])
    assert.equal(hasMeaningfulArmPose(createEditorPreset(name)),true,name)
})

test('elbow spreading activates arms even if both wrists stay by the hips',()=>{
  const standing=createEditorPreset('stand')
  assert.equal(hasMeaningfulArmPose(standing),false)
  const left=createEditorPreset('stand')
  left.joints.find(j=>j.id===13).x=0.10
  assert.equal(hasMeaningfulArmPose(left),true)
  assert.deepEqual(left.joints.filter(j=>[15,16].includes(j.id)),
                   standing.joints.filter(j=>[15,16].includes(j.id)))
  const right=createEditorPreset('stand')
  right.joints.find(j=>j.id===14).x=0.90
  assert.equal(hasMeaningfulArmPose(right),true)
})

test('a raised elbow with a low wrist activates arms, but small elbow jitter does not',()=>{
  const raised=createEditorPreset('stand')
  raised.joints.find(j=>j.id===13).y=0.24
  assert.equal(hasMeaningfulArmPose(raised),true)
  const subtle=createEditorPreset('stand')
  subtle.joints.find(j=>j.id===13).x-=0.03
  assert.equal(hasMeaningfulArmPose(subtle),false)
})
