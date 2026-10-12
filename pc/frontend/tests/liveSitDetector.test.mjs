import test from 'node:test'
import assert from 'node:assert/strict'
import { LiveSitDetector, normalizedHipKneeGap } from '../src/liveSitDetector.js'

function pose(l = .62, r = l, key = 1) {
  const xy = {
    11:[.4,.2],12:[.6,.2],23:[.43,.55],24:[.57,.55],
    25:[.43,.55 + .35*l],26:[.57,.55 + .35*r],
    13:[.35,.35],14:[.65,.35],15:[.3,.5],16:[.7,.5],27:[.42,.96],28:[.58,.96]
  }
  return {valid:true,source_timestamp_us:key,joints:Object.entries(xy).map(([id,[x,y]])=>({id:Number(id),x,y}))}
}
test('hip-knee gap is invariant under translation and uniform scale', () => {
  const p=pose(.7,.8)
  const base=normalizedHipKneeGap(p)
  const translated={...p,joints:p.joints.map(j=>({...j,x:j.x*2+.1,y:j.y*2+.3}))}
  const actual=normalizedHipKneeGap(translated)
  assert.ok(Math.abs(actual.left-base.left)<1e-10)
  assert.ok(Math.abs(actual.right-base.right)<1e-10)
})
test('P05 detects a bilateral compressed hip-knee gap on the first changed frame', () => {
  const d=new LiveSitDetector()
  assert.equal(d.observe('p05',pose(.67,.68,1),0,100).sit,false)
  const r=d.observe('p05',pose(.48,.50,2),0,290)
  assert.equal(r.sit,true);assert.equal(r.source,'joints-hip-knee')
})
test('no single leg raise can trigger a hip-knee sit', () => {
  const d=new LiveSitDetector()
  d.observe('p05',pose(.7,.7,1),0,100)
  assert.equal(d.observe('p05',pose(.35,.70,2),0,300).sit,false)
})
test('P10 forces sit even without Pose; other zones forbid it', () => {
  const d=new LiveSitDetector()
  assert.equal(d.observe('p10',null,0,100).sit,true)
  assert.equal(d.observe('p04',pose(.3,.3),1,200).sit,false)
  assert.equal(d.observe(null,pose(.3,.3),1,300).sit,false)
})
test('P05 catches a strong original squat score without prior standing reference', () => {
  const d=new LiveSitDetector()
  assert.equal(d.observe('p05',pose(.50,.50,1),.8,100).sit,true)
})
test('P05 seated state remains for small noise; standing requires two distinct frames', () => {
  const d=new LiveSitDetector()
  d.observe('p05',pose(.7,.7,1),0,100)
  d.observe('p05',pose(.45,.46,2),0,300)
  assert.equal(d.observe('p05',pose(.70,.70,3),0,500).sit,true)
  assert.equal(d.observe('p05',pose(.70,.70,3),0,510).sit,true)
  assert.equal(d.observe('p05',pose(.70,.70,4),0,700).sit,false)
})
test('duplicate backend snapshots do not shift baseline or count exit votes', () => {
  const d=new LiveSitDetector()
  d.observe('p05',pose(.7,.7,1),0,100)
  d.observe('p05',pose(.45,.45,2),0,250)
  const first=d.observe('p05',pose(.7,.7,3),0,430)
  assert.equal(first.sit,true)
  for(let i=0;i<9;i++) assert.equal(d.observe('p05',pose(.7,.7,3),0,440+i*5).sit,true)
  assert.equal(d.observe('p05',pose(.7,.7,4),0,630).sit,false)
})
test('stale P05 frame stops forcing seated pose; P10 still forces it', () => {
  const d=new LiveSitDetector()
  d.observe('p05',pose(.7,.7,1),0,100)
  d.observe('p05',pose(.45,.45,2),0,300)
  assert.equal(d.observe('p05',pose(.45,.45,2),0,2100).sit,false)
  assert.equal(d.observe('p10',null,0,2200).sit,true)
})
