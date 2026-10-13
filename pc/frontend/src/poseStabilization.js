// Presentation-only stabilization. Does not change CSI, CNN or the 12-joint model output.
const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v))
const smooth = (dt, tau) => 1 - Math.exp(-clamp(dt, 1, 500) / tau)
const angularDelta = (next, prev) => Math.atan2(Math.sin(next - prev), Math.cos(next - prev))

// Holds the 2D viewport steady while retaining space for large arm/leg motions.
export class PoseViewportStabilizer {
  constructor({centerFastMs=200, centerSlowMs=800, scaleShrinkMs=250, scaleGrowMs=850}={}) {
    this.centerFastMs = centerFastMs
    this.centerSlowMs = centerSlowMs
    this.scaleShrinkMs = scaleShrinkMs
    this.scaleGrowMs = scaleGrowMs
    this.reset()
  }
  reset() { this.centerX = null; this.centerY = null; this.scale = null; this.lastAt = null }
  update(points, at = performance.now()) {
    const data = points instanceof Map ? [...points.values()] : [...points]
    if (data.length === 0) { this.reset(); return null }
    const xs = data.map(j => Number(j.x)), ys = data.map(j => Number(j.y))
    if (![...xs, ...ys].every(Number.isFinite)) { this.reset(); return null }
    const minX = Math.min(...xs), maxX = Math.max(...xs)
    const minY = Math.min(...ys), maxY = Math.max(...ys)
    const spanX = maxX - minX, spanY = maxY - minY
    if (spanX < 1e-8 && spanY < 1e-8) { this.reset(); return null }
    const targetX = (minX + maxX) / 2
    const targetY = (minY + maxY) / 2
    const targetScale = Math.min(208 / Math.max(spanX, 1e-8), 302 / Math.max(spanY, 1e-8))
    if (this.scale === null || this.lastAt === null || at < this.lastAt || at - this.lastAt > 1600) {
      this.centerX = targetX; this.centerY = targetY; this.scale = targetScale
      this.lastAt = at
      return { centerX: this.centerX, centerY: this.centerY, scale: this.scale }
    }
    const dt = Math.max(1, at - this.lastAt)
    this.lastAt = at
    const bodySize = Math.max(spanY, spanX * 0.8, 1e-8)
    const centerDistance = Math.hypot(targetX-this.centerX, targetY-this.centerY)
    const centerDeadzone = bodySize * 0.035
    if (centerDistance > centerDeadzone) {
      const alpha = smooth(dt, centerDistance > bodySize * 0.16 ? this.centerFastMs : this.centerSlowMs)
      const factor = (centerDistance - centerDeadzone * 0.6) / centerDistance * alpha
      this.centerX += (targetX - this.centerX) * factor
      this.centerY += (targetY - this.centerY) * factor
    }
    const ratio = targetScale / Math.max(this.scale, 1e-8)
    // Small body-width fluctuations cannot make the entire skeleton zoom in/out.
    if (ratio < 0.92 || ratio > 1.09) {
      const alpha = smooth(dt, ratio < 0.92 ? this.scaleShrinkMs : this.scaleGrowMs)
      this.scale += (targetScale - this.scale) * alpha
    }
    // Avoid prolonged clipping on genuine large movements without following tiny spikes.
    const extentX = Math.max(...xs.map(x => Math.abs(x - this.centerX)))
    const extentY = Math.max(...ys.map(y => Math.abs(y - this.centerY)))
    const fit = Math.min(235 / Math.max(2 * extentX, 1e-8), 325 / Math.max(2 * extentY, 1e-8))
    if (this.scale > fit) this.scale = fit
    return { centerX: this.centerX, centerY: this.centerY, scale: this.scale }
  }
}

// Independent small-motion suppression before the 3D IK solver.
// This is deliberately not applied to the 2D panel or to network model output.
export class RigJointStabilizer {
  constructor() { this.reset() }
  reset() { this.previous = null; this.previousMirror = null; this.lastFrameKey = null }
  push(pose, mirrored = false) {
    if (!pose?.valid || !Array.isArray(pose.joints)) { this.reset(); return pose }
    const key = pose.source_timestamp_us ?? pose.end_trigger_seq ?? pose.window_id
    const frameKey = key == null ? null : String(key)
    if (!this.previous || this.previousMirror !== mirrored ||
        this.previous.coordinate_space !== pose.coordinate_space ||
        this.previous.joints.length !== pose.joints.length) {
      this.previous=pose; this.previousMirror=mirrored; this.lastFrameKey=frameKey
      return pose
    }
    if (frameKey !== null && frameKey === this.lastFrameKey) return this.previous
    const byId=new Map(pose.joints.map(p=>[p.id,p]))
    const s1=byId.get(11),s2=byId.get(12),h1=byId.get(23),h2=byId.get(24)
    const torso=(s1&&s2&&h1&&h2) ?
      Math.abs((h1.y+h2.y-s1.y-s2.y)/2) : 0
    const prevById=new Map(this.previous.joints.map(p=>[p.id,p]))
    const joints=pose.joints.map(j=>{
      const old=prevById.get(j.id)
      if (!old || !Number.isFinite(old.x) || !Number.isFinite(old.y)) return j
      const dx=j.x-old.x, dy=j.y-old.y, distance=Math.hypot(dx,dy)
      const fraction=[11,12,23,24].includes(j.id)?0.016:
        [13,14,25,26].includes(j.id)?0.03:0.045
      const deadzone=Math.max(torso*fraction,1e-5)
      if (distance<=deadzone) return {...j,x:old.x,y:old.y}
      const factor=1-Math.min(0.5,deadzone*0.45/distance)
      return {...j,x:old.x+dx*factor,y:old.y+dy*factor}
    })
    this.previous={...pose,joints}
    this.previousMirror=mirrored;this.lastFrameKey=frameKey
    return this.previous
  }
}

// An additional filter AFTER the 2D skeleton is solved into limb angles.
// Angle-level dead zones stop visible bone tremble; fast gestures pass quickly.
export class RigAngleStabilizer {
  constructor() { this.reset() }
  reset() { this.previous = null; this.previousAt = null; this.previousMirror = null }
  push(solution, mirrored = false, at = performance.now()) {
    if (!solution?.directions || !(solution.directions instanceof Map)) {
      this.reset(); return solution
    }
    if (!this.previous || this.previousMirror !== mirrored || this.previousAt === null ||
        at < this.previousAt || at - this.previousAt > 1600) {
      this.previous = solution
      this.previousAt = at
      this.previousMirror = mirrored
      return solution
    }
    const dt = Math.max(1, at - this.previousAt)
    this.previousAt = at
    const directions = new Map()
    for (const [key, v] of solution.directions) {
      const old = this.previous.directions.get(key)
      if (!old || !Number.isFinite(v.angle) || !Number.isFinite(old.angle)) {
        directions.set(key, v); continue
      }
      const delta = angularDelta(v.angle, old.angle)
      const distance = Math.abs(delta)
      const deadzone = key.startsWith('forearm') ? 0.10 :
        key.startsWith('upperArm') ? 0.075 : 0.085 // radians: 4–6 degrees
      if (distance <= deadzone) {
        directions.set(key, { ...v, angle: old.angle })
        continue
      }
      const tau = distance > 0.44 ? 105 : distance > 0.22 ? 190 : 460
      const alpha = smooth(dt, tau)
      const step = Math.sign(delta) * (distance - deadzone * 0.65) * alpha
      directions.set(key, { ...v, angle: old.angle + step })
    }
    const stabilizeScalar = (key, threshold, tau=260) => {
      const target = solution[key], prev = this.previous[key]
      if (!Number.isFinite(target) || !Number.isFinite(prev)) return target
      const delta = target - prev
      if (Math.abs(delta) <= threshold) return prev
      return prev + Math.sign(delta) * (Math.abs(delta) - threshold * 0.5) * smooth(dt, tau)
    }
    const filtered = {
      ...solution, directions,
      squat: stabilizeScalar('squat', 0.038),
      liftL: stabilizeScalar('liftL', 0.018, 110),
      liftR: stabilizeScalar('liftR', 0.018, 110),
      footSpacingRatio: stabilizeScalar('footSpacingRatio', 0.022)
    }
    this.previous = filtered
    return filtered
  }
}
