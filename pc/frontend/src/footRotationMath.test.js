import test from 'node:test'
import assert from 'node:assert/strict'
import {liftedShoePitch,liftedShoeYaw} from './footRotationMath.js'

test('raised foot turns modestly outward depending on side', () => {
  const p={reach:0.9,footX:0.3,kneeX:0.1}
  const left=liftedShoeYaw(p,'L',1)
  const right=liftedShoeYaw(p,'R',1)
  assert.ok(left<0 && right>0)
  assert.ok(Math.abs(left)<=0.21 && Math.abs(right)<=0.21)
  assert.ok(Math.abs(left+right)<1e-12)
  assert.equal(liftedShoeYaw(p,'L',0),0)
})

test('existing shoe pitch remains bounded', () => {
  const p={reach:0.9,footX:0.5}
  assert.ok(Math.abs(liftedShoePitch(p,1,1))<=0.26)
  assert.equal(liftedShoePitch(p,0,0),0)
})
