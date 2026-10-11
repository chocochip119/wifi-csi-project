import test from 'node:test'
import assert from 'node:assert/strict'
import {projectLiftedLeg} from '../src/legLiftProjection.js'

function pose(ankleX=0.60, ankleY=0.80, kneeX=0.55, kneeY=0.69, mirrored=false) {
  const points=new Map([
    [23,{x:0.45,y:0.50}], [24,{x:0.55,y:0.50}],
    [25,{x:kneeX,y:kneeY}], [26,{x:0.55,y:0.69}],
    [27,{x:ankleX,y:ankleY}], [28,{x:0.55,y:0.90}]
  ])
  if(mirrored) for(const p of points.values())p.x=-p.x
  return {point:points,torso:0.30,kneeL:{flex:.65},kneeR:{flex:.1}}
}
const project=(p,side='L')=>projectLiftedLeg(p,side,.48,.48)
test('lifted shoe travels laterally with measured 2D ankle',()=>{
  const near=project(pose(.55))
  const far=project(pose(.80))
  assert.ok(far.footX>near.footX+0.3)
  assert.ok(far.footX>0.40,'sideways movement is far greater than old 0.039 m')
})
test('mirrored pose reverses lateral displacement',()=>{
  const front=project(pose(.70))
  const back=project(pose(.70,.80,.55,.69,true))
  assert.ok(Math.abs(front.footX+back.footX)<1e-10)
  assert.ok(Math.abs(front.footY-back.footY)<1e-10)
})
test('lifting ankle on screen increases 3D ankle height',()=>{
  assert.ok(project(pose(.55,.64)).footY>project(pose(.55,.84)).footY)
})
test('2D knee location changes the knee bend pole',()=>{
  const near=project(pose(.70,.76,.54,.68))
  const far=project(pose(.70,.76,.75,.59))
  assert.ok(Math.abs(near.kneeX-far.kneeX)>0.3)
  assert.ok(Math.abs(near.kneeY-far.kneeY)>0.1)
})
test('ankle projection is bounded by avatar leg length',()=>{
  const huge=project(pose(3.0,-5.0))
  assert.ok(Math.abs(huge.footX)<=.96*.96+1e-9)
  assert.ok(huge.footY<=.96*.60+1e-9)
})
test('rejects incomplete/invalid pose',()=>{
  assert.equal(projectLiftedLeg(null,'L',.4,.4),null)
  assert.equal(projectLiftedLeg({point:new Map(),torso:1},'L',.4,.4),null)
})
