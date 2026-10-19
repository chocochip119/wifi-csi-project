import test from 'node:test'
import assert from 'node:assert/strict'
import {isCenterLocation,walkingSkeletonPose} from './viewerMotionPolicy.js'
import {legGeometryEvidence} from './legGeometryEvidence.js'
import {createTestPose} from './poseTests.js'
test('only center P05/P10 allows tracked pose',()=>{
  for(let i=1;i<=9;i++)assert.equal(isCenterLocation({valid:true,pointId:'p'+String(i).padStart(2,'0'),zone:i,empty:false}),i===5)
  assert.equal(isCenterLocation({valid:true,pointId:'p10',zone:5,empty:false}),true)
  assert.equal(isCenterLocation({valid:false,pointId:'p05',zone:5}),false)
})
test('walking visualization alternates left and right legs',()=>{
  const a=walkingSkeletonPose(Math.PI/2),b=walkingSkeletonPose(3*Math.PI/2)
  const y=(p,id)=>p.joints.find(j=>j.id===id).y
  assert.ok(y(a,27)<y(b,27));assert.ok(y(b,28)<y(a,28))
})
test('sample poses distinguish raised ankle and squat',()=>{
  assert.equal(legGeometryEvidence(createTestPose('legLift')).unilateral,true)
  assert.equal(legGeometryEvidence(createTestPose('squat')).bilateral,true)
})
import {shouldTrackPose} from './viewerMotionPolicy.js'
test('motion mode tracks limbs even when live location is outside center or unavailable',()=>{
  for(const location of [
    {valid:true,pointId:'p02',zone:2,empty:false},
    {valid:true,pointId:'p10',zone:5,empty:false},
    {valid:false,pointId:null,zone:null,empty:false},
    {valid:true,pointId:'empty',empty:true}]) {
    assert.equal(shouldTrackPose('center',location,false),true)
    assert.equal(shouldTrackPose('center',location,true),false)
  }
  assert.equal(shouldTrackPose('live',{valid:true,pointId:'p03',zone:3},false),false)
  assert.equal(shouldTrackPose('live',{valid:true,pointId:'p05',zone:5},false),false)
  assert.equal(shouldTrackPose('manual',{valid:true,pointId:'p07',zone:7},false),false)
  assert.equal(shouldTrackPose('manual',{valid:true,pointId:'p10',zone:5},false),false)
})
