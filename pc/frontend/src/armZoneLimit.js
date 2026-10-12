// 3D visual shoulder/forearm arm raising guard by inferred LOCATION zone.
// Does not alter the CNN prediction, 2D skeleton, backend, or position inference.
const RAD = Math.PI / 180

export function armMaxLiftDegForZone(zone) {
  // P05 and P10 share actual 5th location. An invalid/unknown location
  // cannot unlock full arm movement, so it remains capped at 40 degrees.
  return Number(zone) === 5 ? null : 40
}

export function clampArmHeading(angle, maxLiftDeg) {
  if (!Number.isFinite(angle)) return angle
  if (maxLiftDeg === null || maxLiftDeg === undefined) return angle
  const limit = Math.max(0, Math.min(90, Number(maxLiftDeg))) * RAD
  if (!Number.isFinite(limit)) return angle
  return Math.max(-limit, Math.min(limit, angle))
}
