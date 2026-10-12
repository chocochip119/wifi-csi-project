// 2D-only low-latency filter. Never changes FPGA, backend, or 3D PoseRig data.
// No 3-frame median: a moving wrist should not lag one inference frame behind.
const now = () => typeof performance !== 'undefined' ? performance.now() : Date.now()

export class FastPose2DFilter {
  constructor(timeConstantMs = 80) {
    this.timeConstantMs = Math.max(1, timeConstantMs)
    this.reset()
  }
  reset() {
    this.previous = null
    this.lastRaw = null
    this.previousAt = 0
    this.lastFrameKey = null
  }
  push(pose, at = now()) {
    if (!pose?.valid || !Array.isArray(pose.joints)) {
      this.reset()
      return null
    }
    const identifier = pose.source_timestamp_us ?? pose.end_trigger_seq ?? pose.window_id
    const key = identifier == null ? null : String(identifier)
    if (this.previous && key !== null && key === this.lastFrameKey) return this.previous
    if (this.previous && key === null && this.lastRaw &&
        pose.joints.length === this.lastRaw.joints.length &&
        pose.joints.every((joint, i) => joint.id === this.lastRaw.joints[i].id &&
          joint.x === this.lastRaw.joints[i].x && joint.y === this.lastRaw.joints[i].y)) {
      return this.previous
    }
    const reset = !this.previous || at < this.previousAt ||
      at - this.previousAt > 1200 ||
      pose.coordinate_space !== this.previous.coordinate_space ||
      pose.joints.length !== this.previous.joints.length
    if (reset) this.reset()
    const old = this.previous
    const dt = Math.max(1, at - this.previousAt)
    const alpha = 1 - Math.exp(-dt / this.timeConstantMs)
    this.lastFrameKey = key
    this.lastRaw = pose
    this.previousAt = at
    if (!old) {
      this.previous = pose
      return pose
    }
    const lookup = new Map(old.joints.map(j => [Number(j.id), j]))
    const shoulderL = pose.joints.find(j => j.id === 11)
    const shoulderR = pose.joints.find(j => j.id === 12)
    const hipL = pose.joints.find(j => j.id === 23)
    const hipR = pose.joints.find(j => j.id === 24)
    const torso = shoulderL && shoulderR && hipL && hipR
      ? Math.abs((hipL.y + hipR.y - shoulderL.y - shoulderR.y) / 2) : 0
    const fastThreshold = Math.max(torso * 0.18, 1e-5)
    const joints = pose.joints.map(j => {
      const p = lookup.get(Number(j.id))
      if (!p || !Number.isFinite(p.x) || !Number.isFinite(p.y)) return { ...j }
      const dx = j.x - p.x, dy = j.y - p.y
      // Large intentional gestures pass immediately; fine motion uses 80 ms EMA.
      const gain = Math.hypot(dx, dy) > fastThreshold ? 1 : alpha
      return gain === 1 ? { ...j } : { ...j, x: p.x + dx * gain, y: p.y + dy * gain }
    })
    this.previous = { ...pose, joints }
    return this.previous
  }
}
