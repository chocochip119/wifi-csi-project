// 실제 12관절 MediaPipe 번호(11=본인의 왼쪽 어깨, 12=오른쪽 어깨)를
// 카메라를 향한 캐릭터의 화면 좌우 기준으로 정렬한다.
// 입력이 셀피 미러처럼 좌우 반전되어 있으면 두 어깨의 X 순서도 반대다.
export const MIRROR_MODES = ['auto', 'mirrored', 'normal']

export function resolvePoseMirror(pose, mode = 'auto', previous = false) {
  if (mode === 'mirrored') return true
  if (mode === 'normal') return false

  if (!pose?.valid || !Array.isArray(pose.joints)) return previous
  const left = pose.joints.find((item) => Number(item.id) === 11)
  const right = pose.joints.find((item) => Number(item.id) === 12)
  const lx = Number(left?.x)
  const rx = Number(right?.x)
  if (!left || !right || !Number.isFinite(lx) || !Number.isFinite(rx)) return previous
  // 어깨가 거의 겹치면 이전 설정을 유지해 순간적인 좌우 뒤집힘을 막는다.
  if (Math.abs(lx - rx) < 1e-3) return previous
  return lx < rx
}

export function toDisplayX(x, mirrored) {
  return mirrored ? -x : x
}

// Reflect the VIEWER pose for both SVG and GLTF IK without modifying CNN output.
// Mirror the X coordinate AND exchange anatomical L/R joint pairs. Exchanging
// only X would make the visible skeleton and the avatar use opposite limbs.
const OPPOSITE_JOINT_ID = new Map([
  [11,12],[12,11],[13,14],[14,13],[15,16],[16,15],
  [23,24],[24,23],[25,26],[26,25],[27,28],[28,27]
])

export function mirrorPoseSides(pose, enabled = true) {
  if (!enabled || !pose?.valid || !Array.isArray(pose.joints)) return pose
  const jointsById = new Map(pose.joints.map(joint => [Number(joint.id), joint]))
  if (jointsById.size !== OPPOSITE_JOINT_ID.size ||
      [...OPPOSITE_JOINT_ID.keys()].some(id => !jointsById.has(id))) return pose

  const joints = pose.joints.map(joint => {
    const source = jointsById.get(OPPOSITE_JOINT_ID.get(Number(joint.id)))
    return {...joint, x: -Number(source.x), y: Number(source.y)}
  })
  return {...pose, joints}
}
