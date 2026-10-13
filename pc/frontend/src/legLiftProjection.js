// Convert a lifted 2D ankle and knee into avatar-scaled offsets from the 3D hip.
// The supporting leg is the scale reference. CSI joints have no depth values.
const clamp = (x, a, b) => Math.max(a, Math.min(b, x))

export function projectLiftedLeg(pose, side, upperLength, lowerLength) {
  if (!pose?.point || !['L', 'R'].includes(side) ||
      !Number.isFinite(pose.torso) || pose.torso <= 1e-6 ||
      ![upperLength, lowerLength].every(n => Number.isFinite(n) && n > 0.02)) return null

  const ids = side === 'L' ? [23, 25, 27, 24, 28, 26] : [24, 26, 28, 23, 27, 25]
  const [hip, knee, ankle, supportHip, supportAnkle, supportKnee] = ids.map(id => pose.point.get(id))
  if ([hip, knee, ankle, supportHip, supportAnkle].some(p =>
    !p || !Number.isFinite(p.x) || !Number.isFinite(p.y))) return null

  const reach = upperLength + lowerLength
  // Support leg's vertical length estimates 2D-to-model scale. It should be
  // more reliable than a fixed pixel/meter ratio across different body sizes.
  const supportSpan = supportAnkle.y - supportHip.y
  const reference = Math.max(pose.torso * 0.55, supportSpan)
  if (!(reference > 1e-6)) return null
  const metersPer2D = reach / reference
  const kneeFlex = clamp(side === 'L' ? (pose.kneeL?.flex ?? 0) : (pose.kneeR?.flex ?? 0), 0, 1)

  // Image +X points right, +Y points downward. No side-stance width clamp here:
  // FOOT_STANCE_MAX only applies when both shoes are planted on the floor.
  const footX = clamp((ankle.x - hip.x) * metersPer2D, -reach * 0.96, reach * 0.96)
  const observedFootY = clamp(-(ankle.y - hip.y) * metersPer2D, -reach, reach * 0.60)
  // When front-view knee height changes but ankle barely moves onscreen,
  // lift the virtual shoe just enough to show the single-leg action.
  const kneeRise = ((supportKnee.y - supportHip.y) - (knee.y - hip.y)) / pose.torso
  const kneeBoost = clamp((kneeRise - 0.08) / 0.30, 0, 1) * reach * 0.30
  const footY = Math.max(observedFootY, -reach + kneeBoost)
  // Depth is deliberately modest, because 12 2D keypoints cannot observe it.
  const footZ = (0.025 + 0.10 * kneeFlex) * reach
  const kneeX = clamp((knee.x - hip.x) * metersPer2D, -reach, reach)
  const kneeY = clamp(-(knee.y - hip.y) * metersPer2D, -reach, reach)
  const kneeZ = (0.12 + 0.16 * kneeFlex) * reach
  return {footX, footY, footZ, kneeX, kneeY, kneeZ, reach}
}
