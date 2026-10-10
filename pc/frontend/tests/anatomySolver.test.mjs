import test from 'node:test'
import assert from 'node:assert/strict'
import {DEFAULT_ANATOMY_CONFIG,normalizeAnatomyConfig,calculateSeatDrop,
  twoBoneTriangle,resolveTorsoHandClearance} from '../src/anatomySolver.js'
test('seated depth grows with bend score and avatar-specific limb lengths',()=>{
  const a=calculateSeatDrop(.45,.45,.87,.25)
  const b=calculateSeatDrop(.45,.45,.87,.9)
  const c=calculateSeatDrop(.55,.55,1.06,.9)
  assert.ok(a.drop>=0&&b.drop>a.drop)
  assert.ok(b.drop>.15,'deep seated pose must exceed former 18cm-ish limit for this rig')
  assert.ok(c.drop>b.drop,'longer legs yield larger metres drop')
})
test('kinematic reach and knee angle remain bounded',()=>{
  const cfg=normalizeAnatomyConfig({seatedKneeDeg:500,seatDepthGain:40})
  assert.equal(cfg.seatedKneeDeg,130)
  assert.equal(cfg.seatDepthGain,1.5)
  const r=calculateSeatDrop(.38,.42,.79,1,cfg)
  assert.ok(r.drop<=.58)
  assert.ok(r.targetReach>=.0)
  assert.equal(twoBoneTriangle(.45,.45,.7).clamped,false)
  assert.equal(twoBoneTriangle(.45,.45,100).clamped,true)
})
test('hand inside chest receives front clearance without changing XY',()=>{
  const inside=resolveTorsoHandClearance({x:0,y:0,z:0,halfWidth:.2,halfHeight:.35,clearance:.11})
  assert.ok(inside.corrected&&inside.z>=inside.frontRequired)
  assert.equal(inside.x,0)
  const outside=resolveTorsoHandClearance({x:.8,y:0,z:0,halfWidth:.2,halfHeight:.35,clearance:.11})
  assert.equal(outside.corrected,false)
  assert.equal(resolveTorsoHandClearance({x:0,y:.9,z:0,halfWidth:.2,halfHeight:.35,clearance:.11}).corrected,false)
})
test('invalid or malformed values cannot become NaN transforms',()=>{
  assert.equal(calculateSeatDrop(.45,.45,NaN,.9),null)
  assert.equal(twoBoneTriangle(.45,.0,.7),null)
  assert.equal(resolveTorsoHandClearance({x:NaN,y:0,z:0,halfWidth:.2,halfHeight:.3,clearance:.1}),null)
  assert.deepEqual(normalizeAnatomyConfig({seatedKneeDeg:NaN,armClearance:'oops'}),DEFAULT_ANATOMY_CONFIG)
})
