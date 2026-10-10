import test from 'node:test'
import assert from 'node:assert/strict'
import {POSE_PRESETS,createEditorPreset,asEditorPose,updateEditorJoint,blendEditorPose,normalizeBackendPose} from '../src/poseEditor.js'
import {solvePoseAngles} from '../src/poseAngles.js'
test('all named coordinate presets form valid twelve-joint skeletons',()=>{
  for(const entry of POSE_PRESETS){
    const pose=createEditorPreset(entry.id)
    assert.equal(pose.joints.length,12,entry.id)
    assert.equal(asEditorPose(pose)?.valid,true,entry.id)
    assert.notEqual(solvePoseAngles(pose),null,entry.id)
  }
})
test('edited coordinate is preserved and never mutates input',()=>{
  const a=createEditorPreset('stand')
  const b=updateEditorJoint(a,15,.14,.13)
  assert.equal(b.joints.find(j=>j.id===15).y,.13)
  assert.equal(a.joints.find(j=>j.id===15).y,.56)
})
test('rejects missing, nonfinite, duplicate and out-of-range joints',()=>{
  const a=createEditorPreset('stand')
  assert.equal(asEditorPose(a.joints.slice(0,11)),null)
  assert.equal(asEditorPose([...a.joints.slice(0,11),a.joints[0]]),null)
  assert.equal(updateEditorJoint(a,15,NaN,0),null)
  assert.equal(updateEditorJoint(a,15,11,0),null)
})
test('interpolated motion stays connected and first/last values match',()=>{
  const a=createEditorPreset('stand'),b=createEditorPreset('legLift')
  assert.deepEqual(blendEditorPose(a,b,0).joints,a.joints)
  assert.deepEqual(blendEditorPose(a,b,1).joints,b.joints)
  assert.equal(blendEditorPose(a,b,.5).joints.length,12)
})
test('backend arbitrary float scale is normalized for editing',()=>{
  const a=createEditorPreset('stand')
  const raw={joints:a.joints.map(j=>({...j,x:j.x*250,y:j.y*250}))}
  const edited=normalizeBackendPose(raw)
  assert.equal(edited.valid,true)
  assert.ok(edited.joints.every(j=>j.x>=.1 && j.x<=.9 && j.y>=.1 && j.y<=.9))
})
