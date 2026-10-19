import test from 'node:test'
import assert from 'node:assert/strict'
import {solvePoseAngles} from './poseAngles.js'
import {classifyLegPosture,StableLegPosture} from './stableLegPosture.js'
import {createTestPose} from './poseTests.js'

// Manually approximated pixels from the user's 2026-10-15 seated screenshot:
// shoulders 11/12, hips 23/24, knees 25/26, ankles 27/28.
// Coordinates are used as a rough geometry REGRESSION fixture, not recovered
// CNN values or a claim to know the actual hardware classification.
const seatedPixels={
  11:[739,45],12:[855,37],13:[715,152],14:[897,128],
  15:[706,190],16:[921,179],23:[780,220],24:[839,203],
  25:[748,263],26:[863,229],27:[764,405],28:[863,378]
}
const frame=(source,n)=>({...source,valid:true,source_timestamp_us:n,
  joints:source.joints.map(j=>({...j}))})
const poseFrom=(pixels,n)=>({valid:true,source_timestamp_us:n,
  coordinate_space:'model_output',
  joints:Object.entries(pixels).map(([id,[x,y]])=>({id:Number(id),x:x/1000,y:y/1000}))})
const classify=pose=>classifyLegPosture(pose,solvePoseAngles(pose,false),'p05')

test('front-view user seated example classifies as squat in motion P05',()=>{
  const p=poseFrom(seatedPixels,900)
  const out=classify(p)
  assert.equal(out.action,'squat')
  assert.equal(out.geometry.bilateral,true)
  assert.ok(out.strength>=0.78)
})

test('mild seat projection changes do not prevent two-frame confirmation',()=>{
  const tracker=new StableLegPosture()
  const variants=[
    seatedPixels,
    {...seatedPixels,25:[750,264],26:[861,230],27:[765,408],28:[861,380]}
  ]
  const one=poseFrom(variants[0],901)
  const two=poseFrom(variants[1],902)
  assert.equal(tracker.update(one,solvePoseAngles(one,false),'p05',100).action,'stand')
  assert.equal(tracker.update(two,solvePoseAngles(two,false),'p05',250).action,'squat')
  assert.equal(tracker.state.source,'joints')
})

test('seated pose stays stable through four noisy standing frames then releases',()=>{
  const tracker=new StableLegPosture()
  for(const [n,time] of [[1,100],[2,200]]){
    const p=poseFrom(seatedPixels,n)
    tracker.update(p,solvePoseAngles(p,false),'p05',time)
  }
  assert.equal(tracker.state.action,'squat')
  for(let i=3;i<=6;i++){
    const p=frame(createTestPose('stand'),i)
    assert.equal(tracker.update(p,solvePoseAngles(p,false),'p05',1000+i*100).action,'squat')
  }
  const p=frame(createTestPose('stand'),7)
  assert.equal(tracker.update(p,solvePoseAngles(p,false),'p05',1700).action,'stand')
})

test('single-leg raise and normal standing never become sitting',()=>{
  const stand=frame(createTestPose('stand'),20)
  const lift=frame(createTestPose('legLift'),21)
  assert.equal(classify(stand).action,'stand')
  assert.equal(classify(lift).action,'lift')
  // A distorted single knee should not be interpreted as bilateral sitting.
  const oneKnee={...stand,joints:stand.joints.map(j=>({
    ...j,y:j.id===25?j.y-0.07:j.y
  }))}
  assert.notEqual(classify(oneKnee).action,'squat')
})

test('P10 position does not force the fixed-motion tracker to sit',()=>{
  const t=new StableLegPosture()
  const stand=frame(createTestPose('stand'),30)
  assert.equal(t.update(stand,solvePoseAngles(stand,false),'p05',100).action,'stand')
  assert.equal(t.update(stand,solvePoseAngles(stand,false),'p05',2000).action,'stand')
})
