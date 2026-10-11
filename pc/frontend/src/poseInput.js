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
  // 3-frame median removes isolated coordinate spikes; adaptive EMA reduces jitter.
  // Keep all twelve joints coherent and use the same filtered data for 2D and 3D.
  constructor(timeConstantMs = 220) {
    this.timeConstantMs = timeConstantMs
    this.reset()
  }
  reset() {
    this.previous = null
    this.previousAt = 0
    this.lastFrameKey = null
    this.rawHistory = []
  }
  push(pose, at = now()) {
    if (!pose) { this.reset(); return null }
    const keySource = pose.source_timestamp_us ?? pose.end_trigger_seq ?? pose.window_id
    const frameKey = keySource == null ? null : String(keySource)
    // Backend sends snapshots every 100 ms; an unchanged pose must NOT be
    // repeatedly counted as a fresh sample.
    if (this.previous && frameKey !== null && frameKey === this.lastFrameKey)
      return this.previous
    if (this.previous && frameKey === null &&
        pose.joints.every((j, i) => j.x === this.lastRaw?.joints[i]?.x && j.y === this.lastRaw?.joints[i]?.y))
      return this.previous
    const expired = !this.previous || this.previous.coordinate_space !== pose.coordinate_space ||
      at - this.previousAt > 1200 || at < this.previousAt
    if (expired) this.reset()
    this.lastFrameKey = frameKey
    this.lastRaw = pose
    this.rawHistory.push(pose.joints)
    if (this.rawHistory.length > 3) this.rawHistory.shift()
    if (expired) {
      this.previous = pose
      this.previousAt = at
      return pose
    }
    const dt = Math.max(1, at - this.previousAt)
    const alpha = 1 - Math.exp(-dt / this.timeConstantMs)
    const prevById = new Map(this.previous.joints.map(j => [j.id, j]))
    const byId = new Map(pose.joints.map(j => [j.id, j]))
    const torso = Math.abs(((byId.get(23)?.y ?? 0) + (byId.get(24)?.y ?? 0)
      - (byId.get(11)?.y ?? 0) - (byId.get(12)?.y ?? 0))/2)
    const spikeThreshold = Math.max(torso * 0.60, 1e-5)
    const median = (values) => {
      const ordered = values.slice().sort((a,b) => a-b)
      const half = Math.floor(ordered.length / 2)
      return ordered.length % 2 ? ordered[half] : (ordered[half-1]+ordered[half])/2
    }
    // Actual joint movement still passes; just suppress individual-frame spikes.
    const joints = pose.joints.map((j, i) => {
      const p = prevById.get(j.id)
      // With only two frames, don't let one implausibly large jump leak
      // through the average before the third-frame median can reject it.
      const first = this.rawHistory[0][i]
      const initialSpike = this.rawHistory.length === 2 &&
        Math.hypot(j.x-first.x, j.y-first.y) > spikeThreshold
      const x = initialSpike ? p.x : median(this.rawHistory.map(frame => frame[i].x))
      const y = initialSpike ? p.y : median(this.rawHistory.map(frame => frame[i].y))
      // Per-joint dead zone scaled to torso size: remove small CNN tremble,
      // keep deliberate large movements. The source prediction is not mutated.
      const normalizedZone = [11,12,23,24].includes(j.id) ? 0.018 :
        [13,14,25,26].includes(j.id) ? 0.032 : 0.042
      const deadZone = Math.max(Math.abs(torso) * normalizedZone, 1e-5)
      const dx = x - p.x, dy = y - p.y
      const distance = Math.hypot(dx, dy)
      if (distance <= deadZone) return { ...j, x:p.x, y:p.y }
      const gain = 1 - deadZone * 0.55 / distance
      const adaptiveAlpha = distance > Math.max(Math.abs(torso) * 0.24, 1e-5) ? Math.max(alpha, 0.70) : alpha
      return { ...j,
        x: p.x + dx * adaptiveAlpha * gain,
        y: p.y + dy * adaptiveAlpha * gain }
    })
    this.previous = { ...pose, joints }
    this.previousAt = at
    return this.previous
  }
}
