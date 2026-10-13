// Viewer-only leg raise limits: free movement at P05/P10, a low
// visual approximation of 10° elsewhere. The source CNN pose is unchanged.
export const OTHER_ZONE_LEG_LIFT_DEG = 10
export const UNRESTRICTED_LEG_LIFT_DEG = 90

export function legLiftMaxDegForLocation(location) {
  const point = String(location?.pointId ?? '').toLowerCase()
  return location?.valid === true && !location.empty &&
    (point === 'p05' || point === 'p10')
    ? UNRESTRICTED_LEG_LIFT_DEG
    : OTHER_ZONE_LEG_LIFT_DEG
}

// Constrain a lifted foot near neutral in zones other than P05/P10.
// CNN provides 2D joints only: this is a visual displacement cap, not a
// measured 3D hip flexion angle. At P05/P10, keep the original foot offset.
export function limitRaisedFootOffset({forward = 0, sideways = 0, rise = 0, downFromHip = 0, reach = 1, maxDeg = 0} = {}) {
  const finite = [forward, sideways, rise, downFromHip, reach, maxDeg].every(Number.isFinite)
  if (!finite || reach <= 0 || maxDeg <= 0) return {forward: 0, sideways: 0, rise: 0}
  if (maxDeg >= UNRESTRICTED_LEG_LIFT_DEG) return {forward, sideways, rise}
  const theta = Math.max(0, Math.min(60, maxDeg)) * Math.PI / 180
  const maxRise = Math.min(0.28, reach * Math.sin(theta) * 0.70)
  const maxSide = Math.min(0.22, reach * Math.sin(theta) * 0.60)
  const permittedRadius = Math.max(0.07, downFromHip - Math.max(0, rise)) * Math.tan(theta)
  return {
    sideways: Math.max(-Math.min(maxSide, permittedRadius), Math.min(maxSide, permittedRadius, sideways)),
    rise: Math.max(0, Math.min(maxRise, rise)),
    forward: Math.max(-0.08, Math.min(0.14, forward))
  }
}
