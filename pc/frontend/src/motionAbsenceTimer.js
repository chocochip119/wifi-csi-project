// Presentation-only grace period for explicit "No person" results.
// A missing/stale location by itself is not confirmation of an empty room.
export const MOTION_ABSENCE_DELAY_MS = 5000

export class MotionAbsenceTimer {
  constructor(delayMs = MOTION_ABSENCE_DELAY_MS) {
    this.delayMs = delayMs
    this.absentSince = null
  }

  observe(noPerson, now) {
    if (!noPerson) {
      this.reset()
      return false
    }
    if (this.absentSince === null) this.absentSince = now
    return this.shouldHide(now)
  }

  shouldHide(now) {
    return this.absentSince !== null && now - this.absentSince >= this.delayMs
  }

  reset() {
    this.absentSince = null
  }
}
