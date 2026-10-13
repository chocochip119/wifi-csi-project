import test from 'node:test'
import assert from 'node:assert/strict'
import {UNRESTRICTED_LEG_LIFT_DEG,OTHER_ZONE_LEG_LIFT_DEG,
  legLiftMaxDegForLocation,limitRaisedFootOffset} from './legLiftPolicy.js'

test('P05 and P10 are unrestricted, all other inferred locations use 10 degrees', () => {
  for (let i = 1; i <= 10; i++) {
    const pointId = 'p'+String(i).padStart(2,'0')
    const expected = [5,10].includes(i) ? UNRESTRICTED_LEG_LIFT_DEG : OTHER_ZONE_LEG_LIFT_DEG
    assert.equal(legLiftMaxDegForLocation({valid:true,pointId,empty:false}),expected)
  }
  assert.equal(legLiftMaxDegForLocation({valid:false,pointId:'p05'}),OTHER_ZONE_LEG_LIFT_DEG)
  assert.equal(legLiftMaxDegForLocation({valid:true,pointId:'p05',empty:true}),OTHER_ZONE_LEG_LIFT_DEG)
  assert.equal(legLiftMaxDegForLocation(null),OTHER_ZONE_LEG_LIFT_DEG)
})

test('other zones constrain high and lateral single-leg raising to low-angle offsets', () => {
  const args={forward:0.7,sideways:0.8,rise:0.75,downFromHip:0.8,reach:0.95,maxDeg:10}
  const out=limitRaisedFootOffset(args)
  assert.ok(out.rise>0 && out.rise<0.12)
  assert.ok(out.sideways>0 && out.sideways<0.11)
  assert.ok(out.forward<=0.14)
  assert.ok(out.rise<args.rise && out.sideways<args.sideways)
})

test('P05/P10 preserves original raised-foot targets without cap', () => {
  const args={forward:0.7,sideways:0.8,rise:0.75,downFromHip:0.8,reach:0.95,maxDeg:90}
  assert.deepEqual(limitRaisedFootOffset(args),
    {forward:args.forward,sideways:args.sideways,rise:args.rise})
})

test('disabled/invalid input uses neutral offset', () => {
  assert.deepEqual(limitRaisedFootOffset({sideways:0.5,forward:0.4,rise:0.6,reach:0.9,maxDeg:0}),
    {forward:0,sideways:0,rise:0})
  assert.deepEqual(limitRaisedFootOffset({reach:NaN,maxDeg:10}),{forward:0,sideways:0,rise:0})
})
