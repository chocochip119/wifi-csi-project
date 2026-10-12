// Viewer-only presentation mode helpers. Never modify the backend inference.
// 'No person' must be explicit; missing/Unavailable location is NOT absence.
export function isNoPerson(snapshot) {
  const point = String(snapshot?.location?.point_id ?? '')
    .toLowerCase().replace(/[\s_-]/g, '')
  return snapshot?.person?.presence === false ||
    point === 'empty' || point === 'noperson'
}

export function motionPointId(sitDecision, noPerson = false) {
  if (noPerson) return null
  return sitDecision?.sit === true ? 'p10' : 'p05'
}

export function sitDetectorPoint(locationMode, location) {
  if (locationMode === 'center') return 'p05'
  return location?.valid && !location?.empty ? location.pointId : null
}

export function motionArmLiftLimit(locationMode, inferredZone, armLimitForZone) {
  return locationMode === 'center' ? null : armLimitForZone(inferredZone)
}
