import test from 'node:test'
import assert from 'node:assert/strict'
import {createTestPose} from './poseTests.js'
import {solvePoseAngles} from './poseAngles.js'
import {classifyLegPosture,StableLegPosture} from './stableLegPosture.js'
const frame=(pose,n)=>({...createTestPose(pose),source_timestamp_us:n})
const angles=pose=>solvePoseAngles(pose,false)
test('ankles AND knees distinguish one lifted leg from bilateral squat',()=>{
 const lift=frame('legLift',1),squat=frame('squat',2),stand=frame('stand',3)
 assert.equal(classifyLegPosture(lift,angles(lift),'p10').action,'lift')
 assert.equal(classifyLegPosture(squat,angles(squat),'p05').action,'squat')
 assert.equal(classifyLegPosture(stand,angles(stand),'p10').action,'stand',
   'location P10 alone does not make a seated avatar')
})
test('live squat needs distinct frames and minimum hold before stand',()=>{
 const g=new StableLegPosture({confirmFrames:3,minHoldMs:750})
 for(let i=1;i<=2;i++){
   const p=frame('squat',i);assert.equal(g.update(p,angles(p),'p05',i*100).action,'stand')
 }
 const p=frame('squat',3);assert.equal(g.update(p,angles(p),'p05',300).action,'squat')
 // Identical frame polling must not count toward stand votes.
 const q=frame('stand',4)
 g.update(q,angles(q),'p05',350)
 for(let i=0;i<8;i++)g.update(q,angles(q),'p05',400+i*20)
 assert.equal(g.state.action,'squat')
 for(let i=5;i<=6;i++){const x=frame('stand',i);g.update(x,angles(x),'p05',i*100)}
 assert.equal(g.state.action,'squat','minimum hold prevents abrupt release')
 for(let i=7;i<=10;i++){const x=frame('stand',i);g.update(x,angles(x),'p05',i*130)}
 assert.equal(g.state.action,'stand')
})
test('alternating squat and lift evidence never toggles frame-by-frame',()=>{
 const g=new StableLegPosture({confirmFrames:3,minHoldMs:750,crossSwitchFrames:5})
 for(let i=1;i<=3;i++){const p=frame('legLift',i);g.update(p,angles(p),'p05',i*250)}
 assert.equal(g.state.action,'lift')
 assert.equal(g.state.side,'L')
 for(let i=4;i<=18;i++){
   const type=i%2?'squat':'legLift',p=frame(type,i)
   g.update(p,angles(p),'p10',i*125)
 }
 assert.equal(g.state.action,'lift')
})
