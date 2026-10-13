// Front-view 12-joint, single-leg lift estimate. No depth inference.
// Compare both legs in torso-height units; bilateral knee bending cancels out.
const clamp = (value, lo, hi) => Math.max(lo, Math.min(hi, value))

export function singleLegLiftStrength({ ankleSpan, oppositeAnkleSpan, kneeSpan, oppositeKneeSpan }) {
  if (![ankleSpan, oppositeAnkleSpan, kneeSpan, oppositeKneeSpan].every(Number.isFinite)) return 0
  const ankleRise = oppositeAnkleSpan - ankleSpan
  const kneeRise = oppositeKneeSpan - kneeSpan
  // Preserve the previous ankle-only response for clear foot lifts.
  const ankleScore = clamp((ankleRise - 0.13) / 0.37, 0, 1)
  // Knee rise catches a raised thigh even if the ankle barely moves onscreen.
  // Require modest ankle evidence OR a clearly raised knee to reject minor flexion.
  const kneeIsLift = ankleRise >= 0.045 || kneeRise >= 0.28
  const kneeScore = kneeIsLift ? clamp((kneeRise - 0.075) / 0.30, 0, 1) : 0
  return Math.max(ankleScore, kneeScore)
}
