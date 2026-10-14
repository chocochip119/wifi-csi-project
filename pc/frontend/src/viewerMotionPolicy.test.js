import test from 'node:test'
import assert from 'node:assert/strict'
import {isCenterLocation,walkingSkeletonPose} from './viewerMotionPolicy.js'
import {legGeometryEvidence} from './legGeometryEvidence.js'
import {createTestPose} from './poseTests.js'
test('only P05 and P10 are tracking zones; unknown must be neutral',()=>{
 for(let i=1;i<=9;i++){
   const p='p'+String(i).padStart(2,'0')
   assert.equal(isCenterLocation({valid:true,pointId:p,zone:i,empty:false}),i===5)
 }
 assert.equal(isCenterLocation({valid:true,pointId:'p10',zone:5,empty:false}),true)
 assert.equal(isCenterLocation({valid:false,pointId:'p05',zone:5}),false)
 assert.equal(isCenterLocation({valid:true,pointId:'empty',empty:true,zone:5}),false)
})
test('walking skeleton swing is anti-phase and never mutates the standing preset',()=>{
 const p=walkingSkeletonPose(Math.PI/2)
 const q=walkingSkeletonPose(3*Math.PI/2)
 const byId=(pose,id)=>pose.joints.find(j=>j.id===id)
 assert.ok(byId(p,27).y<byId(q,27).y)
 assert.ok(byId(q,28).y<byId(p,28).y)
 assert.equal(createTestPose('stand').joints.find(j=>j.id===27).y,0.94)
})
test('geometry identifies legs with valid bilateral knee and ankle positions',()=>{
 const lift=legGeometryEvidence(createTestPose('legLift'))
 const squat=legGeometryEvidence(createTestPose('squat'))
 assert.equal(lift.unilateral,true)
 assert.equal(lift.bilateral,false)
 assert.equal(squat.bilateral,true)
})
