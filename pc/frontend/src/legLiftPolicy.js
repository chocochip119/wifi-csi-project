// Viewer-only permission and low-angle limit for single-leg lifting.
// Use the inferred physical location, NOT the P05-pinned motion scene.
export const MAX_LEG_LIFT_DEG = 25

export function legLiftMaxDegForLocation(location) {
  const point = String(location?.pointId ?? '').toLowerCase()
  return location?.valid === true && !location.empty &&
    (point === 'p05' || point === 'p10') ? MAX_LEG_LIFT_DEG : 0
}

// The 2D pose has no depth: keep the raised ankle close to the planted
// position with a bounded, approximate lift cone (not a measured hip angle).
export function limitRaisedFootOffset({forward = 0, sideways = 0, rise = 0, downFromHip = 0, reach = 1, maxDeg = 0} = {}) {
  const finite = [forward, sideways, rise, downFromHip, reach, maxDeg].every(Number.isFinite)
  if (!finite || reach <= 0 || maxDeg <= 0) return {forward: 0, sideways: 0, rise: 0}
  const theta = Math.max(0, Math.min(60, maxDeg)) * Math.PI / 180
  const maxRise = Math.min(0.28, reach * Math.sin(theta) * 0.70)
  const maxSide = Math.min(0.22, reach * Math.sin(theta) * 0.60)
  // A small forward movement supports natural knee bend; do not twist far sideways.
  const permittedRadius = Math.max(0.07, downFromHip - Math.max(0, rise)) * Math.tan(theta)
  return {
    sideways: Math.max(-Math.min(maxSide, permittedRadius), Math.min(maxSide, permittedRadius, sideways)),
    rise: Math.max(0, Math.min(maxRise, rise)),
    forward: Math.max(-0.08, Math.min(0.14, forward))
  }
}
