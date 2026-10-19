// Viewer-only movement; do not mutate CNN or PS/Backend coordinates.
import { createTestPose } from './poseTests.js'
export function isCenterLocation(location) {
  return location?.valid === true && !location.empty &&
    (location.pointId === 'p05' || location.pointId === 'p10' || location.zone === 5)
}
// In motion mode the avatar remains at P05 by design. Do not let the
// independent location classifier gate its gesture tracking.
export function shouldTrackPose(locationMode, location, absent = false) {
  return !absent && locationMode === 'center'
}
export function walkingSkeletonPose(phase = 0) {
  const pose = createTestPose('stand')
  const t = Number.isFinite(phase) ? phase : 0
  const swing = Math.sin(t)
  const leftStep = Math.max(0, swing)
  const rightStep = Math.max(0, -swing)
  const adjustments = {
    13: [-0.03 * swing, 0.035 * swing], 15: [-0.055 * swing, 0.070 * swing],
    14: [-0.03 * swing, -0.035 * swing], 16: [-0.055 * swing, -0.070 * swing],
    25: [0.010 * swing, -0.065 * leftStep], 27: [0.018 * swing, -0.085 * leftStep],
    26: [0.010 * swing, -0.065 * rightStep], 28: [0.018 * swing, -0.085 * rightStep]
  }
  return {...pose, test_pose:'walking_display_only', joints:pose.joints.map(j => {
    const [dx,dy]=adjustments[j.id] || [0,0]
    return {...j,x:j.x+dx,y:j.y+dy}
  })}
}
