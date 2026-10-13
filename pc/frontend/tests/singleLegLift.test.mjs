import test from 'node:test'
import assert from 'node:assert/strict'
import { singleLegLiftStrength as strength } from '../src/singleLegLift.js'
import { projectLiftedLeg } from '../src/legLiftProjection.js'

const measure = (ankleL, ankleR, kneeL, kneeR) => ({
  left: strength({ankleSpan:ankleL, oppositeAnkleSpan:ankleR, kneeSpan:kneeL, oppositeKneeSpan:kneeR}),
  right: strength({ankleSpan:ankleR, oppositeAnkleSpan:ankleL, kneeSpan:kneeR, oppositeKneeSpan:kneeL})
})

test('symmetric upright legs stay neutral', () => {
  assert.deepEqual(measure(1.1,1.1,0.55,0.55), {left:0,right:0})
})
test('symmetric crouching knees are not mistaken for lifting one leg', () => {
  assert.deepEqual(measure(0.80,0.80,0.30,0.30), {left:0,right:0})
})
test('previous clear ankle raise still triggers leg lift', () => {
  const {left,right}=measure(0.66,1.14,0.37,0.56)
  assert.ok(left>.5);assert.equal(right,0)
})
test('a unilateral knee raise with only a small ankle raise triggers earlier', () => {
  const {left,right}=measure(1.05,1.13,0.32,0.56)
  assert.ok(left>.25);assert.equal(right,0)
})
test('small single-knee flex with no ankle evidence does not trigger', () => {
  assert.deepEqual(measure(1.12,1.12,0.41,0.55), {left:0,right:0})
})
test('very clear unilateral raised knee can trigger without visible ankle motion', () => {
  const {left,right}=measure(1.1,1.1,0.20,0.56)
  assert.ok(left>.65);assert.equal(right,0)
})
test('right-side lift mirrors left-side lift', () => {
  const left=measure(0.95,1.13,0.31,0.56).left
  const right=measure(1.13,0.95,0.56,0.31).right
  assert.ok(left>.25);assert.equal(left,right)
})
test('non-finite input must not trigger', () => {
  assert.equal(strength({ankleSpan:NaN,oppositeAnkleSpan:1,kneeSpan:0,oppositeKneeSpan:.5}),0)
})

function makePose(kneeY, ankleY, oppositeKneeY = .72) {
  return {torso:.35, point:new Map([
    [23,{x:.40,y:.5}],[25,{x:.39,y:kneeY}],[27,{x:.39,y:ankleY}],
    [24,{x:.60,y:.5}],[26,{x:.61,y:oppositeKneeY}],[28,{x:.61,y:.95}]
  ]), kneeL:{flex:.6}, kneeR:{flex:0}}
}
test('IK shoe target moves upward when knee rises but ankle is unchanged', () => {
  const neutral=projectLiftedLeg(makePose(.72,.95),'L',.45,.45)
  const raised=projectLiftedLeg(makePose(.54,.95),'L',.45,.45)
  assert.ok(neutral&&raised)
  assert.ok(raised.footY>neutral.footY+0.15, `neutral=${neutral.footY} raised=${raised.footY}`)
})
test('standing lift projection stays within a plausible avatar reach', () => {
  const projected=projectLiftedLeg(makePose(.63,.77),'L',.45,.45)
  assert.ok(projected)
  assert.ok(projected.footY>=-.9&&projected.footY<=.54)
})
