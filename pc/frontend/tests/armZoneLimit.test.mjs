import test from 'node:test'
import assert from 'node:assert/strict'
import { armMaxLiftDegForZone, clampArmHeading } from '../src/armZoneLimit.js'
const rad = deg => deg * Math.PI / 180

test('only position 5 permits unrestricted character arms (P10 maps to zone 5)', () => {
  assert.equal(armMaxLiftDegForZone(5),null)
  for (const zone of [1,2,3,4,6,7,8,9,null,undefined,0,NaN]) {
    assert.equal(armMaxLiftDegForZone(zone),40)
  }
})

test('both directions are capped to 40 degrees from straight down', () => {
  assert.equal(clampArmHeading(rad(120),40),rad(40))
  assert.equal(clampArmHeading(rad(-120),40),rad(-40))
  assert.equal(clampArmHeading(rad(20),40),rad(20))
  assert.equal(clampArmHeading(rad(-15),40),rad(-15))
  assert.equal(clampArmHeading(rad(120),null),rad(120))
})
