import test from 'node:test'
import assert from 'node:assert/strict'
import {DEFAULT_ANATOMY_CONFIG, calculateSeatDrop, visualSquatStrength,
  normalizeAnatomyConfig} from './anatomySolver.js'

test('visual-only boost keeps standing at zero and bounds intensity', () => {
  assert.equal(visualSquatStrength(0), 0)
  assert.equal(visualSquatStrength(-1), 0)
  assert.equal(visualSquatStrength(NaN), 0)
  assert.equal(visualSquatStrength(1.8), 1)
  assert.equal(visualSquatStrength(0.78), 1)
})

test('confirmed sitting lowers pelvis substantially more', () => {
  const upper=0.43, lower=0.43, neutral=0.82, rawStrength=0.78
  const before=calculateSeatDrop(upper,lower,neutral,rawStrength,
    {seatedKneeDeg:105,seatDepthGain:1.12,kneeForward:0.95,armClearance:0.11})
  const after=calculateSeatDrop(upper,lower,neutral,visualSquatStrength(rawStrength),
    DEFAULT_ANATOMY_CONFIG)
  assert.ok(after.drop>before.drop*1.8,
    `expected deeper squat: ${before.drop} -> ${after.drop}`)
  assert.ok(after.drop<=0.58)
  assert.ok(after.drop<=neutral-Math.abs(upper-lower)-0.03+1e-8)
  assert.ok(after.flexionDeg>=120 && after.flexionDeg<=130)
})

test('stronger defaults remain inside anatomical geometry limits', () => {
  const cfg=normalizeAnatomyConfig(DEFAULT_ANATOMY_CONFIG)
  assert.equal(cfg.seatedKneeDeg,127)
  assert.equal(cfg.seatDepthGain,1.38)
  for(const strength of [0,0.25,0.5,0.78,1]) {
    const seat=calculateSeatDrop(0.35,0.38,0.70,
      visualSquatStrength(strength),cfg)
    assert.ok(seat&&Number.isFinite(seat.drop))
    assert.ok(seat.drop>=0&&seat.drop<=0.58)
  }
})
