// Viewer-only sit state: P10 forces sitting, P05 listens to unfiltered new
// 12-joint frames; other positions never sit. No backend/CNN/2D changes.
const clamp = (x, lo, hi) => Math.min(hi, Math.max(lo, x))
const idle = () => ({ sit: false, strength: 0, source: 'standing', hipKnee: null })

// When only ONE leg is clearly lifted, do not let an accidental P10 class
// or an asymmetric knee frame turn the avatar into a seated pose.
export function isClearlySingleLegLift({liftL = 0, liftR = 0} = {}) {
  const left = Number(liftL), right = Number(liftR)
  return Number.isFinite(left) && Number.isFinite(right) &&
    Math.max(left,right) >= 0.48 && Math.abs(left-right) >= 0.30
}

export function normalizedHipKneeGap(pose) {
  if (!pose?.valid || !Array.isArray(pose.joints)) return null
  const pts = new Map(pose.joints.map(j => [Number(j.id), j]))
  const ids = [11, 12, 23, 24, 25, 26]
  if (!ids.every(id => pts.has(id) && Number.isFinite(Number(pts.get(id).y)))) return null
  const shY = (Number(pts.get(11).y) + Number(pts.get(12).y)) * 0.5
  const hipY = (Number(pts.get(23).y) + Number(pts.get(24).y)) * 0.5
  const torso = hipY - shY
  if (!Number.isFinite(torso) || torso <= 1e-6) return null
  const left = (Number(pts.get(25).y) - Number(pts.get(23).y)) / torso
  const right = (Number(pts.get(26).y) - Number(pts.get(24).y)) / torso
  if (![left, right].every(x => x >= -0.35 && x <= 4)) return null
  return { left, right, mean: (left + right) / 2 }
}

const frameKey = pose => {
  const token = pose?.source_timestamp_us ?? pose?.end_trigger_seq ?? pose?.window_id
  return token == null ? pose.joints.map(j => `${j.id}:${j.x}:${j.y}`).join('|') : String(token)
}

export class LiveSitDetector {
  constructor({releaseFrames = 2, maxFrameGapMs = 1500} = {}) {
    this.releaseFrames = Math.max(1, Math.floor(releaseFrames))
    this.maxFrameGapMs = maxFrameGapMs
    this.reset()
  }
  reset() {
    this.baseline = null
    this.recent = []
    this.seated = false
    this.releaseVotes = 0
    this.lastFrameKey = null
    this.lastFrameAt = 0
    this.lastResult = idle()
  }
  observe(pointId, pose, existingSquat = 0, atMs = 0, legEvidence = null) {
    const point = String(pointId ?? '').toLowerCase()
    const unilateralLift = isClearlySingleLegLift(legEvidence ?? {})
    if (point === 'p10' && unilateralLift) {
      this.seated = false
      this.releaseVotes = 0
      this.lastResult = idle()
      return this.lastResult
    }
    if (point === 'p10') {
      this.seated = true
      this.releaseVotes = 0
      this.lastResult = { sit: true, strength: 1, source: 'P10', hipKnee: null }
      return this.lastResult
    }
    if (point !== 'p05') { this.reset(); return this.lastResult }

    const gap = normalizedHipKneeGap(pose)
    if (!gap) {
      // P05 without a trustworthy new frame cannot force a squat indefinitely.
      if (!this.lastFrameAt || atMs - this.lastFrameAt > this.maxFrameGapMs) {
        this.seated = false
        this.lastResult = idle()
      }
      return this.lastResult
    }
    const key = frameKey(pose)
    if (key === this.lastFrameKey) {
      if (atMs - this.lastFrameAt > this.maxFrameGapMs) {
        this.seated = false
        this.lastResult = idle()
      }
      return this.lastResult
    }
    if (this.lastFrameAt && atMs - this.lastFrameAt > this.maxFrameGapMs) {
      this.seated = false
      this.releaseVotes = 0
      this.recent = []
    }
    this.lastFrameAt = atMs
    this.lastFrameKey = key
    if (!this.baseline) this.baseline = { left: Math.max(gap.left, .12), right: Math.max(gap.right, .12) }
    const dropL = clamp(1 - gap.left / Math.max(.12, this.baseline.left), -1, 2)
    const dropR = clamp(1 - gap.right / Math.max(.12, this.baseline.right), -1, 2)
    const bothDrop = Math.min(dropL, dropR)
    const meanDrop = (dropL + dropR) * .5
    const formerMax = this.recent.length ? Math.max(...this.recent) : gap.mean
    const movingDown = (formerMax - gap.mean) / Math.max(.12, formerMax)
    const kneeSignal = clamp(Number(existingSquat) || 0, 0, 1)
    if (unilateralLift) {
      this.seated = false
      this.releaseVotes = 0
      this.recent = []
      this.lastResult = idle()
      return this.lastResult
    }

    // Detect the early transition or the seated geometry on the very next
    // unique Pose frame; both sides must participate to reject single-leg lifts.
    const onset = (bothDrop >= .10 && meanDrop >= .18) ||
      (bothDrop >= .07 && meanDrop >= .12 && movingDown >= .10) ||
      kneeSignal >= .52
    const held = (bothDrop >= .035 && meanDrop >= .085) || kneeSignal >= .27
    if (!this.seated && onset) {
      this.seated = true
      this.releaseVotes = 0
    } else if (this.seated) {
      this.releaseVotes = held ? 0 : this.releaseVotes + 1
      if (this.releaseVotes >= this.releaseFrames) {
        this.seated = false
        this.releaseVotes = 0
      }
    }

    // Learn the standing reference only while upright; do not "learn" a squat.
    if (!this.seated && meanDrop < .08 && kneeSignal < .20) {
      for (const side of ['left', 'right']) {
        const alpha = gap[side] > this.baseline[side] ? .16 : .002
        this.baseline[side] += (gap[side] - this.baseline[side]) * alpha
      }
    }
    this.recent.push(gap.mean)
    if (this.recent.length > 4) this.recent.shift()
    const strength = this.seated
      ? Math.max(.65, clamp((meanDrop - .08) / .32, 0, 1), kneeSignal)
      : 0
    this.lastResult = {
      sit: this.seated, strength,
      source: this.seated ? (onset && kneeSignal >= .52 && meanDrop < .12 ? 'joints-knee' : 'joints-hip-knee') : 'standing',
      hipKnee: { left: gap.left, right: gap.right, meanDrop, bothDrop, movingDown }
    }
    return this.lastResult
  }
}
