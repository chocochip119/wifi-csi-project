import test from 'node:test'
import assert from 'node:assert/strict'
import { RecentFpsCounter, poseIdentity } from '../src/fpsMetrics.js'

test('new model output is identified by source_timestamp or window ID', () => {
  assert.equal(poseIdentity({valid:true,joints:Array(12).fill({}),source_timestamp_us:42,window_id:1}), '42')
  assert.equal(poseIdentity({valid:true,joints:Array(12).fill({}),window_id:8}), '8')
  assert.equal(poseIdentity({valid:false,joints:Array(12).fill({}),window_id:8}), null)
  assert.equal(poseIdentity({valid:true,joints:[],window_id:8}), null)
})

test('repeated snapshots do not inflate source FPS', () => {
  const s = new RecentFpsCounter(5000)
  assert.equal(s.observe('window1',0),true)
  assert.equal(s.observe('window1',200),false)
  assert.equal(s.observe('window2',1000),true)
  assert.equal(s.fps(1000),2)
})

test('idle source drops to zero without new windows', () => {
  const s = new RecentFpsCounter(3000)
  s.observe(1,0)
  s.observe(2,1000)
  assert.equal(s.fps(4500),0)
  s.observe(3,5000)
  assert.equal(s.fps(5000)>0,true)
})

test('counter clears on backend disconnect', () => {
  const s = new RecentFpsCounter()
  s.observe(5,0)
  s.reset()
  assert.equal(s.fps(100),0)
  assert.equal(s.observe(5,200),true)
})
