// FPS estimates from distinct Backend snapshot IDs and Pose frame IDs.
// Never count repeated polls or repeated window IDs as new predictions.
export function poseIdentity(pose) {
  if (!pose?.valid || !Array.isArray(pose.joints) || pose.joints.length !== 12) return null
  const value = pose.source_timestamp_us ?? pose.end_trigger_seq ?? pose.window_id
  return value == null ? null : String(value)
}

export class RecentFpsCounter {
  constructor(windowMs = 5000) {
    this.windowMs = windowMs
    this.lastId = null
    this.startedAt = null
    this.samples = []
  }
  observe(id, at) {
    if (id === null || id === undefined) return false
    const key = String(id)
    if (key === this.lastId) return false
    this.lastId = key
    if (this.startedAt === null) this.startedAt = at
    this.samples.push(at)
    this.prune(at)
    return true
  }
  prune(at) {
    while (this.samples.length && this.samples[0] < at - this.windowMs) this.samples.shift()
  }
  fps(at) {
    this.prune(at)
    if (!this.samples.length) return 0
    const elapsedMs = Math.min(this.windowMs, Math.max(1000, at - this.startedAt))
    return this.samples.length * 1000 / elapsedMs
  }
  reset() {
    this.lastId = null
    this.startedAt = null
    this.samples = []
  }
}
