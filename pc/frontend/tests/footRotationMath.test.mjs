import test from 'node:test'
import assert from 'node:assert/strict'
import { liftedShoePitch } from '../src/footRotationMath.js'

const projection = (lateral, reach=1) => ({footX:lateral, reach})

test('neutral feet have no correction', () => {
  assert.equal(liftedShoePitch(projection(.3), .8, 0), 0)
})
test('pitch stays within safe small angles', () => {
  for (const flex of [0,.5,1]) for(const lateral of [-20,-1,0,1,20]) {
    const a=liftedShoePitch(projection(lateral),flex,1)
    assert.ok(a>=-0.14-1e-12 && a<=0.26+1e-12)
  }
})
test('more knee flexion relaxes toes downward', () => {
  assert.ok(liftedShoePitch(projection(.2),1,1) > liftedShoePitch(projection(.2),0,1))
})
test('large side extension reduces toe-down rotation', () => {
  assert.ok(liftedShoePitch(projection(.85),.5,1) < liftedShoePitch(projection(.15),.5,1))
})
test('pitch decreases smoothly as leg comes down', () => {
  const full=liftedShoePitch(projection(.2),.8,1)
  const half=liftedShoePitch(projection(.2),.8,.5)
  assert.ok(Math.abs(half-full/2)<1e-12)
})
test('bad input fails safely', () => {
  assert.equal(liftedShoePitch(null,1,1),0)
  assert.equal(liftedShoePitch(projection(NaN),1,1),0)
  assert.equal(liftedShoePitch(projection(.2,0),1,1),0)
})
