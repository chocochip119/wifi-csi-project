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
