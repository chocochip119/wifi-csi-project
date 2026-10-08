// Backend v1 snapshot.pose 검사 및 실시간 좌표 필터.
// 실제 model_output 좌표는 이미 Backend에서 INT8 * output_scale 처리된 값이다.
export const JOINT_IDS = Object.freeze([11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28])
const FINITE_LIMIT = 1e7
const now = () => typeof performance !== 'undefined' ? performance.now() : Date.now()

export function sanitizePose(pose) {
  if (!pose || pose.valid !== true || !Array.isArray(pose.joints)) return null
  const jointById = new Map()
  for (const joint of pose.joints) {
    if (!joint || typeof joint !== 'object') continue
    const id = Number(joint.id)
    if (!JOINT_IDS.includes(id) || jointById.has(id)) return null
    if (joint.x === null || joint.y === null || joint.x === '' || joint.y === '') return null
    const x = Number(joint.x), y = Number(joint.y)
    if (![x, y].every(Number.isFinite) || Math.abs(x) > FINITE_LIMIT || Math.abs(y) > FINITE_LIMIT) return null
    jointById.set(id, { id, name: joint.name, x, y })
  }
  if (jointById.size !== JOINT_IDS.length) return null
  const joints = JOINT_IDS.map(id => jointById.get(id))
  const xs = joints.map(j => j.x), ys = joints.map(j => j.y)
  if (Math.max(...xs) - Math.min(...xs) < 1e-8 && Math.max(...ys) - Math.min(...ys) < 1e-8) return null
  if (pose.age_ms != null && (!Number.isFinite(Number(pose.age_ms)) || Number(pose.age_ms) < 0)) return null
  return { ...pose, valid: true, coordinate_space: pose.coordinate_space || 'unknown', joints }
}

export class PoseFilter {
  constructor(timeConstantMs = 100) {
    this.timeConstantMs = timeConstantMs
    this.reset()
  }
  reset() { this.previous = null; this.previousAt = 0 }
  push(pose, at = now()) {
    if (!pose) { this.reset(); return null }
    // 파일 재생 및 backend의 frame 간격이 길면 이전 프레임 값을 끌어오지 않는다.
    if (!this.previous || this.previous.coordinate_space !== pose.coordinate_space ||
        at - this.previousAt > 1200 || at < this.previousAt) {
      this.previous = pose
      this.previousAt = at
      return pose
    }
    const dt = Math.max(1, at - this.previousAt)
    const alpha = 1 - Math.exp(-dt / this.timeConstantMs)
    const prevById = new Map(this.previous.joints.map(j => [j.id, j]))
    const joints = pose.joints.map(j => {
      const p = prevById.get(j.id)
      return { ...j, x: p.x + (j.x - p.x) * alpha, y: p.y + (j.y - p.y) * alpha }
    })
    this.previous = { ...pose, joints }
    this.previousAt = at
    return this.previous
  }
}
