// Viewer-only 3D leg-lift gate. Do not alter 2D joints or CNN predictions.
// Sit wins over single-leg motion; standing strong lifts remain responsive.
const clamp = (value, lo, hi) => Math.max(lo, Math.min(hi, value))
const NONE = Object.freeze({ liftL: 0, liftR: 0 })

export function shouldHoldSeatedPose({ seated, active, ageMs }, maxAgeMs = 450) {
  return seated === true && active === true && Number.isFinite(ageMs) &&
    ageMs >= 0 && ageMs <= maxAgeMs
}

export class SingleLegLiftGate {
  constructor({ strong = 0.53, weak = 0.23, continueAt = 0.17,
    weakFrames = 2, releaseFrames = 2, afterSitMs = 320,
    maxFrameGapMs = 900 } = {}) {
    this.strong = strong
    this.weak = weak
    this.continueAt = continueAt
    this.weakFrames = weakFrames
    this.releaseFrames = releaseFrames
    this.afterSitMs = afterSitMs
    this.maxFrameGapMs = maxFrameGapMs
    this.reset()
  }

  reset() {
    this.lastSeatedAt = null
    this.frameKey = null
    this.lastFreshAt = null
    this.candidateSide = null
    this.candidateVotes = 0
    this.activeSide = null
    this.releaseVotes = 0
    this.output = NONE
  }

  _neutral() {
    this.candidateSide = null
    this.candidateVotes = 0
    this.activeSide = null
    this.releaseVotes = 0
    this.output = NONE
    return NONE
  }

  update({ liftL = 0, liftR = 0, seated = false, atMs = 0, frameKey = null } = {}) {
    if (!Number.isFinite(atMs) || !Number.isFinite(liftL) || !Number.isFinite(liftR))
      return this._neutral()
    if (seated === true) {
      this.lastSeatedAt = atMs
      this.frameKey = frameKey
      this.lastFreshAt = atMs
      return this._neutral()
    }
    // After sit release, two valid stand frames have already been checked by
    // LiveSitDetector. Briefly suppress residual one-leg CSI spikes.
    if (this.lastSeatedAt !== null &&
      (atMs < this.lastSeatedAt || atMs - this.lastSeatedAt < this.afterSitMs)) {
      this.frameKey = frameKey
      this.lastFreshAt = atMs
      return this._neutral()
    }
    // A repeated backend snapshot must not count as a second confirmation.
    if (frameKey !== null && frameKey === this.frameKey) {
      if (this.lastFreshAt !== null && atMs - this.lastFreshAt > this.maxFrameGapMs)
        return this._neutral()
      return this.output
    }
    if (this.lastFreshAt !== null &&
      (atMs < this.lastFreshAt || atMs - this.lastFreshAt > this.maxFrameGapMs)) {
      this._neutral()
    }
    this.frameKey = frameKey
    this.lastFreshAt = atMs

    const left = clamp(liftL, 0, 1)
    const right = clamp(liftR, 0, 1)
    const side = left >= right ? 'L' : 'R'
    const strength = Math.max(left, right)

    // Keep a confirmed lift across a single brief weak-value dropout, but
    // never preserve it during sitting or the post-sit cooldown.
    if (this.activeSide !== null && strength < this.continueAt) {
      this.releaseVotes++
      if (this.releaseVotes >= this.releaseFrames) return this._neutral()
      const held = this.activeSide === 'L' ? this.output.liftL : this.output.liftR
      const reduced = held * 0.65
      this.output = this.activeSide === 'L' ? { liftL: reduced, liftR: 0 } : { liftL: 0, liftR: reduced }
      return this.output
    }
    if (strength < this.weak) return this._neutral()
    if (this.activeSide !== null && side !== this.activeSide && strength < this.strong) {
      // Don't flip the avatar's raised leg on a small ambiguous noise frame.
      return this._neutral()
    }
    this.releaseVotes = 0
    if (side !== this.candidateSide) {
      this.candidateSide = side
      this.candidateVotes = 1
    } else this.candidateVotes++
    const confirmed = strength >= this.strong ||
      (this.activeSide === side && strength >= this.continueAt) ||
      this.candidateVotes >= this.weakFrames
    if (!confirmed) { this.output = NONE; return NONE }
    this.activeSide = side
    // The 3D IK's trigger is > 0.25: lift a confirmed weak sample just above
    // that threshold without amplifying the underlying 2D prediction.
    const applied = Math.max(strength, 0.27)
    this.output = side === 'L' ? { liftL: applied, liftR: 0 } : { liftL: 0, liftR: applied }
    return this.output
  }
}
