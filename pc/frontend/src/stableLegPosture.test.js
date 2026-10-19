import test from 'node:test'
import assert from 'node:assert/strict'
import {createTestPose} from './poseTests.js'
import {solvePoseAngles} from './poseAngles.js'
import {classifyLegPosture,StableLegPosture} from './stableLegPosture.js'
const frame=(name,n)=>({...createTestPose(name),source_timestamp_us:n})
const angles=pose=>solvePoseAngles(pose,false)
test('left lifted leg and squat are distinguished using ankles/knees',()=>{
  const lift=frame('legLift',1),squat=frame('squat',2),stand=frame('stand',3)
  assert.equal(classifyLegPosture(lift,angles(lift),'p10').action,'lift')
  assert.equal(classifyLegPosture(squat,angles(squat),'p05').action,'squat')
  assert.equal(classifyLegPosture(stand,angles(stand),'p10').action,'stand')
})
test('posture requires new frames, minimum hold, and no re-voting same frame',()=>{
  const s=new StableLegPosture({confirmFrames:3,minHoldMs:750})
  for(let i=1;i<=3;i++){const p=frame('squat',i);s.update(p,angles(p),'p05',i*100)}
  assert.equal(s.state.action,'squat')
  const p=frame('stand',4)
  for(let i=0;i<12;i++)s.update(p,angles(p),'p05',400+i*25)
  assert.equal(s.state.action,'squat')
  for(let i=5;i<=10;i++){const q=frame('stand',i);s.update(q,angles(q),'p05',i*130)}
  assert.equal(s.state.action,'stand')
})
test('P10 requires separate location windows and time before forced 3D seat',()=>{
  const g=new StableLegPosture()
  const q=frame('stand',1)
  assert.equal(g.update(q,angles(q),'p10',100,'100').action,'stand')
  assert.equal(g.update(q,angles(q),'p10',800,'100').action,'stand')
  const confirmed=g.update(q,angles(q),'p10',1100,'101')
  assert.equal(confirmed.action,'squat')
  assert.equal(confirmed.source,'stable-p10')
  // Same repeated standing pose must not shake 3D back to idle.
  for(let t=1200;t<=1700;t+=100)
    assert.equal(g.update(q,angles(q),'p10',t,'101').action,'squat')
  assert.equal(g.update(frame('stand',2),angles(frame('stand',2)),'p05',1900,'102').action,'squat')
  for(let i=3;i<=5;i++){
    const stand=frame('stand',i);g.update(stand,angles(stand),'p05',1900+i*100,'102')
  }
  // A seated avatar now requires five distinct standing frames to stand up.
  assert.equal(g.state.action,'squat')
  for(let i=6;i<=6;i++){
    const stand=frame('stand',i);g.update(stand,angles(stand),'p05',1900+i*100,'102')
  }
  assert.equal(g.state.action,'stand')
})
test('P10 does not convert a confirmed unilateral lift into false squat',()=>{
  const g=new StableLegPosture()
  for(let i=1;i<=3;i++){
    const lift=frame('legLift',i)
    g.update(lift,angles(lift),'p05',i*130,i)
  }
  assert.equal(g.state.action,'lift')
  for(let i=4;i<=18;i++){
    const lift=frame('legLift',i)
    assert.equal(g.update(lift,angles(lift),'p10',i*160,i).action,'lift')
  }
})
test('repeated PS snapshot does not prematurely cancel confirmed lift',()=>{
  const g=new StableLegPosture({staleMs:4200})
  for(let i=1;i<=3;i++){
    const pose=frame('legLift',i)
    g.update(pose,angles(pose),'p03',i*160,i)
  }
  assert.equal(g.state.action,'lift')
  const pose=frame('legLift',3)
  assert.equal(g.update(pose,angles(pose),'p03',3100,3).action,'lift')
  assert.equal(g.update(pose,angles(pose),'p03',5200,3).action,'stand')
})

test('moderate unilateral knee and ankle rise triggers motion-mode lift after two distinct frames',()=>{
  const g=new StableLegPosture()
  const moderate=n=>{
    const base=frame('stand',n)
    return {...base,joints:base.joints.map(j=>({
      ...j, y:j.y-(j.id===25?0.034:j.id===27?0.064:0)
    }))}
  }
  const first=moderate(71)
  const evidence=classifyLegPosture(first,angles(first),'p03')
  assert.equal(evidence.action,'lift')
  assert.equal(g.update(first,angles(first),'p03',100).action,'stand')
  const second=moderate(72)
  assert.equal(g.update(second,angles(second),'p03',250).action,'lift')
  assert.equal(g.state.side,'L')
  // Three disagreeing standing frames are insufficient to drop a held lift.
  for(let i=0;i<3;i++){
    const p=frame('stand',73+i)
    assert.equal(g.update(p,angles(p),'p03',600+i*120).action,'lift')
  }
  const p=frame('stand',76)
  assert.equal(g.update(p,angles(p),'p03',1060).action,'stand')
})

test('small isolated knee jitter is still standing',()=>{
  const p=frame('stand',99)
  const changed={...p,joints:p.joints.map(j=>({...j,y:j.y-(j.id===25?0.01:0)}))}
  assert.equal(classifyLegPosture(changed,angles(changed),'p05').action,'stand')
})

test('moderate right unilateral lift keeps correct right-side label',()=>{
  const g=new StableLegPosture()
  for (const i of [201,202]) {
    const base=frame('stand',i)
    const p={...base,joints:base.joints.map(j=>({
      ...j,y:j.y-(j.id===26?0.034:j.id===28?0.064:0)
    }))}
    const out=g.update(p,angles(p),'p06',i*100)
    if(i===201) assert.equal(out.action,'stand')
    else assert.equal(out.action,'lift')
  }
  assert.equal(g.state.side,'R')
})

// Normalized screenshot-style shapes: one ankle AND knee rise sharply while
// the supporting leg remains down. All 12 anatomical keypoints are present.
const screenshotPose=(variant,n)=>{
  const data=variant==='left' ? {
    11:[866,57],12:[948,69],13:[854,150],14:[949,181],
    15:[854,220],16:[937,269],23:[866,219],24:[911,233],
    25:[817,261],26:[905,352],27:[823,379],28:[899,452]
  } : {
    11:[727,90],12:[826,76],13:[705,166],14:[863,158],
    15:[705,241],16:[893,204],23:[765,263],24:[825,233],
    25:[765,362],26:[855,279],27:[773,489],28:[855,421]
  }
  return {valid:true,source_timestamp_us:n,coordinate_space:'model_output',
    joints:Object.entries(data).map(([id,[x,y]])=>({id:Number(id),x:x/1000,y:y/1000}))}
}

test('clear screenshot-like LEFT lift reacts to first distinct pose frame',()=>{
  const pose=screenshotPose('left',301)
  const evidence=classifyLegPosture(pose,angles(pose),'p05')
  assert.equal(evidence.action,'lift')
  assert.equal(evidence.geometry.raisedSide,'L')
  assert.equal(evidence.strong,true)
  const g=new StableLegPosture()
  assert.equal(g.update(pose,angles(pose),'p05',100).action,'lift')
  assert.equal(g.state.side,'L')
})

test('clear screenshot-like RIGHT lift overrides predicted P10 posture',()=>{
  const pose=screenshotPose('right',401)
  const evidence=classifyLegPosture(pose,angles(pose),'p10')
  assert.equal(evidence.action,'lift')
  assert.equal(evidence.geometry.raisedSide,'R')
  const g=new StableLegPosture()
  assert.equal(g.update(pose,angles(pose),'p05',100).action,'lift')
  assert.equal(g.state.side,'R')
  assert.equal(g.update(pose,angles(pose),'p05',1000).action,'lift')
})

test('mirror mode maps classified raised side to the same 3D anatomical side',async()=>{
  const {mirrorPoseSides}=await import('./poseOrientation.js')
  const p=screenshotPose('left',501)
  const unmirrored=classifyLegPosture(p,angles(p),'p05')
  const visual=mirrorPoseSides(p,true)
  const mirrored=classifyLegPosture(visual,angles(visual),'p05')
  assert.equal(unmirrored.geometry.raisedSide,'L')
  assert.equal(mirrored.geometry.raisedSide,'R')
  assert.equal(mirrored.action,'lift')
})
