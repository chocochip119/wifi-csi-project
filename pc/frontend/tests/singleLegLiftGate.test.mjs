import test from 'node:test'
import assert from 'node:assert/strict'
import { SingleLegLiftGate, shouldHoldSeatedPose } from '../src/singleLegLiftGate.js'
const update = (guard, id, time, L = 0, R = 0, seated = false) =>
  guard.update({ frameKey: id, atMs: time, liftL: L, liftR: R, seated })

test('clear standing left-leg lift is recognized on the first NEW frame', () => {
  const g = new SingleLegLiftGate()
  assert.deepEqual(update(g, '1', 100, 0.8, 0), {liftL:0.8,liftR:0})
})
test('clear standing right-leg lift is recognized immediately', () => {
  const g = new SingleLegLiftGate()
  assert.deepEqual(update(g, '1', 100, 0, 0.75), {liftL:0,liftR:0.75})
})
test('weak standing lift requires two distinct frames, not one', () => {
  const g = new SingleLegLiftGate()
  assert.deepEqual(update(g,'1',100,0.31), {liftL:0,liftR:0})
  assert.ok(update(g,'2',200,0.31).liftL >= 0.30)
})
test('duplicate backend snapshots cannot supply the second weak vote', () => {
  const g = new SingleLegLiftGate()
  assert.equal(update(g,'1',100,0.31).liftL,0)
  assert.equal(update(g,'1',150,0.31).liftL,0)
  assert.equal(update(g,'1',180,0.31).liftL,0)
  assert.ok(update(g,'2',220,0.31).liftL>0.25)
})
test('flipping weak sides resets the two-frame confirmation', () => {
  const g = new SingleLegLiftGate()
  update(g,'1',100,0.31,0)
  assert.deepEqual(update(g,'2',200,0,0.31), {liftL:0,liftR:0})
  assert.deepEqual(update(g,'3',300,0.31,0), {liftL:0,liftR:0})
})
test('even extreme one-leg spike while seated never starts lift', () => {
  const g = new SingleLegLiftGate()
  update(g,'0',100,0.82,0)
  assert.deepEqual(update(g,'1',200,1,0,true), {liftL:0,liftR:0})
  assert.deepEqual(update(g,'2',300,0,1,true), {liftL:0,liftR:0})
})
test('post-seated stand temporarily suppresses even strong false leg spikes', () => {
  const g = new SingleLegLiftGate()
  update(g,'1',100,0,0,true)
  assert.deepEqual(update(g,'2',200,0.95), {liftL:0,liftR:0})
  assert.deepEqual(update(g,'3',410,0.99), {liftL:0,liftR:0})
  assert.ok(update(g,'4',430,0.85).liftL>0.8)
})
test('after sit cooldown a gentle intentional lift still needs two frames', () => {
  const g = new SingleLegLiftGate()
  update(g,'1',100,1,0,true)
  assert.equal(update(g,'2',300,0.34).liftL,0)
  assert.equal(update(g,'3',430,0.34).liftL,0)
  assert.ok(update(g,'4',530,0.34).liftL>0.25)
})
test('confirmed standing lift tolerates a single low-confidence dip', () => {
  const g = new SingleLegLiftGate()
  update(g,'1',100,0.8)
  assert.ok(update(g,'2',200,0.1).liftL>0)
  assert.deepEqual(update(g,'3',300,0.1), {liftL:0,liftR:0})
})
test('stale duplicate frames cannot keep leg raised forever', () => {
  const g = new SingleLegLiftGate()
  update(g,'1',100,0.8)
  assert.equal(update(g,'1',1200,0.8).liftL,0)
})
test('seated invalid-pose hold is short and never applies while standing', () => {
  assert.equal(shouldHoldSeatedPose({seated:true,active:true,ageMs:230}),true)
  assert.equal(shouldHoldSeatedPose({seated:true,active:true,ageMs:600}),false)
  assert.equal(shouldHoldSeatedPose({seated:false,active:true,ageMs:100}),false)
  assert.equal(shouldHoldSeatedPose({seated:true,active:false,ageMs:50}),false)
})
