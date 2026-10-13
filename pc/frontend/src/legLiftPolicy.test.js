import test from 'node:test'
import assert from 'node:assert/strict'
import {MAX_LEG_LIFT_DEG,legLiftMaxDegForLocation,limitRaisedFootOffset} from './legLiftPolicy.js'

test('only real P05 and P10 permit modest leg lift', () => {
  for (let i = 1; i <= 10; i++) {
    const pointId = 'p'+String(i).padStart(2,'0')
    const expected = [5,10].includes(i) ? MAX_LEG_LIFT_DEG : 0
    assert.equal(legLiftMaxDegForLocation({valid:true,pointId,empty:false}),expected)
  }
  assert.equal(legLiftMaxDegForLocation({valid:false,pointId:'p05'}),0)
  assert.equal(legLiftMaxDegForLocation({valid:true,pointId:'p05',empty:true}),0)
  assert.equal(legLiftMaxDegForLocation(null),0)
})

test('raised-foot bound reduces high/lateral foot targets to a low pose', () => {
  const args={forward:0.7,sideways:0.8,rise:0.75,downFromHip:0.8,reach:0.95,maxDeg:25}
  const out=limitRaisedFootOffset(args)
  assert.ok(out.rise>0 && out.rise<=0.28)
  assert.ok(out.sideways>0 && out.sideways<=0.22)
  assert.ok(out.forward<=0.14)
  assert.ok(out.rise<args.rise && out.sideways<args.sideways)
})

test('no zone permission forces neutral foot displacement', () => {
  assert.deepEqual(limitRaisedFootOffset({
    sideways:0.5,forward:0.4,rise:0.6,downFromHip:0.5,reach:0.9,maxDeg:0
  }),{forward:0,sideways:0,rise:0})
})

test('negative/invalid input is handled without non-finite geometry', () => {
  assert.deepEqual(limitRaisedFootOffset({reach:NaN,maxDeg:25}),{forward:0,sideways:0,rise:0})
})
