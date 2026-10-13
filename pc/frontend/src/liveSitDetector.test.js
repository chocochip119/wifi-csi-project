import test from 'node:test'
import assert from 'node:assert/strict'
import {LiveSitDetector,isClearlySingleLegLift} from './liveSitDetector.js'

const pose = {
  valid:true, source_timestamp_us:123,
  joints:[
    {id:11,y:0},{id:12,y:0},{id:23,y:2},{id:24,y:2},
    {id:25,y:3},{id:26,y:3}
  ]
}

test('one raised leg vetoes false P10 seated classification', () => {
  const sit = new LiveSitDetector()
  const result = sit.observe('p10',pose,0.6,100,{liftL:0.85,liftR:0.10})
  assert.equal(result.sit,false)
  assert.equal(result.source,'standing')
})

test('P10 without unilateral lift still permits squat', () => {
  const sit = new LiveSitDetector()
  assert.equal(sit.observe('p10',pose,0.6,100,{liftL:0.1,liftR:0.1}).sit,true)
})

test('P05 veto beats a misleading squat-score spike', () => {
  const sit = new LiveSitDetector()
  const result = sit.observe('p05',pose,0.85,100,{liftL:0.84,liftR:0.04})
  assert.equal(result.sit,false)
})

test('bilateral symmetric lifts do not count as single-leg evidence', () => {
  assert.equal(isClearlySingleLegLift({liftL:0.85,liftR:0.1}),true)
  assert.equal(isClearlySingleLegLift({liftL:0.6,liftR:0.55}),false)
  assert.equal(isClearlySingleLegLift({liftL:0.2,liftR:0.05}),false)
})
