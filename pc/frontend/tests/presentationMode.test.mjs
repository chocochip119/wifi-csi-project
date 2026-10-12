import test from 'node:test'
import assert from 'node:assert/strict'
import {isNoPerson, motionPointId, sitDetectorPoint, motionArmLiftLimit} from '../src/presentationMode.js'

const loc = (pointId, zone = 5) => ({valid:true,empty:false,pointId,zone})

test('motion mode uses P05 to detect sitting even if inference says P08 or P10', () => {
  for(const pointId of ['p08','p10',null]) {
    const location = pointId ? loc(pointId) : {valid:false,empty:false,pointId:null}
    assert.equal(sitDetectorPoint('center',location),'p05')
  }
})
test('location mode retains original classifier point P08/P10, does not invent missing P05', () => {
  assert.equal(sitDetectorPoint('live',loc('p08')),'p08')
  assert.equal(sitDetectorPoint('live',loc('p10')),'p10')
  assert.equal(sitDetectorPoint('live',{valid:false,empty:false}),null)
})
test('no person respects explicit presence false and empty location', () => {
  assert.equal(isNoPerson({person:{presence:false},pose:{valid:true}}),true)
  assert.equal(isNoPerson({location:{point_id:'empty'}}),true)
  assert.equal(isNoPerson({location:{point_id:'No Person'}}),true)
  assert.equal(isNoPerson({location:{valid:false},person:{presence:null}}),false)
  assert.equal(isNoPerson({location:{point_id:'p08'},person:{presence:true}}),false)
})
test('motion location result follows actual sit state, not inferred P10', () => {
  assert.equal(motionPointId({sit:false}), 'p05')
  assert.equal(motionPointId({sit:true,source:'joints-hip-knee'}), 'p10')
  assert.equal(motionPointId({sit:false,source:'standing'}), 'p05')
  assert.equal(motionPointId({sit:true},true), null)
})
test('motion mode removes zone-based arm limit, location mode keeps it', () => {
  const cap = zone => zone === 5 ? null : 40
  assert.equal(motionArmLiftLimit('center',8,cap),null)
  assert.equal(motionArmLiftLimit('center',null,cap),null)
  assert.equal(motionArmLiftLimit('live',8,cap),40)
  assert.equal(motionArmLiftLimit('live',5,cap),null)
})
