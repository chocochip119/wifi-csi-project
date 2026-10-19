import test from 'node:test'
import assert from 'node:assert/strict'
import {createTestPose} from './poseTests.js'
import {solvePoseAngles} from './poseAngles.js'
import {LocationPostureTracker,locationSeatEvidence} from './locationPosturePolicy.js'
const point=(id='p03')=>({valid:true,empty:false,pointId:id,zone:id==='p10'?5:Number(id.slice(1))})
const sample=(name,n)=>({...createTestPose(name),source_timestamp_us:n})
const angles=p=>solvePoseAngles(p,false)
test('P10 location switches to sitting in first accepted snapshot, even without pose',()=>{
  const t=new LocationPostureTracker()
  assert.deepEqual(t.update(point('p10'),null,null),{sit:true,source:'location-p10'})
  assert.deepEqual(t.update(point('p10'),sample('stand',1),null),{sit:true,source:'location-p10'})
})
test('all non P10 locations display only standing or bilateral sitting, never one-leg lift',()=>{
  const t=new LocationPostureTracker()
  for(const id of ['p01','p03','p05','p07','p09']) {
    const leg=sample('legLift',1)
    assert.equal(locationSeatEvidence(point(id),leg,angles(leg)).sitting,false)
    assert.equal(t.update(point(id),leg,angles(leg)).sit,false)
    const sit1=sample('squat',3),sit2=sample('squat',4)
    t.update(point(id),sit1,angles(sit1))
    assert.equal(t.update(point(id),sit2,angles(sit2)).sit,true)
    t.reset()
  }
})
test('repeated same frame cannot confirm location-mode squat',()=>{
  const t=new LocationPostureTracker()
  const p=sample('squat',1)
  for(let i=0;i<10;i++) assert.equal(t.update(point('p03'),p,angles(p)).sit,false)
  assert.equal(t.update(point('p03'),sample('squat',2),angles(p)).sit,true)
})
test('leaving P10 returns to neutral without waiting for standing pose confirmations',()=>{
  const t=new LocationPostureTracker()
  assert.equal(t.update(point('p10'),null,null).sit,true)
  assert.equal(t.update(point('p02'),null,null).sit,false)
  assert.equal(t.update({valid:false,pointId:null},null,null).sit,false)
})
