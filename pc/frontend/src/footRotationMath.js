// Optional foot-pitch prior for a raised leg.
// With 12 joints (no toes/heels), exact ankle orientation cannot be recovered.
// The pitch is deliberately small, body-relative and bounded.
const clamp = (n, lo, hi) => Math.max(lo, Math.min(hi, n))

export function liftedShoePitch(projection, kneeFlex, liftAmount) {
  if (!projection || !Number.isFinite(projection.reach) || projection.reach <= 0 ||
      !Number.isFinite(projection.footX)) return 0
  const amount = clamp(Number.isFinite(liftAmount) ? liftAmount : 0, 0, 1)
  const flex = clamp(Number.isFinite(kneeFlex) ? kneeFlex : 0, 0, 1)
  const sideways = clamp(Math.abs(projection.footX) / projection.reach, 0, 1)
  // Positive rotation about avatar-local +X tips toes slightly downward.
  // More knee flexion permits a relaxed toe-down, while a wide side lift stays level.
  const radians = 0.10 + 0.16 * flex - 0.18 * sideways
  return clamp(radians, -0.14, 0.26) * amount
}

// Turn ONLY the lifted shoe slightly outward. Toe orientation cannot be
// recovered from 12 joints; keep this pose prior subtle (3°..12°).
export function liftedShoeYaw(projection, side, liftAmount) {
  if (!projection || !Number.isFinite(projection.reach) || projection.reach <= 0 ||
      !Number.isFinite(projection.footX) || !Number.isFinite(projection.kneeX) ||
      !['L','R'].includes(side)) return 0
  const amount = clamp(Number.isFinite(liftAmount) ? liftAmount : 0,0,1)
  if(amount === 0) return 0
  const sideways = clamp(Math.abs(projection.footX-projection.kneeX)/projection.reach,0,1)
  const outward = side === 'L' ? -1 : 1
  return outward * (0.055 + 0.15 * sideways) * amount
}
