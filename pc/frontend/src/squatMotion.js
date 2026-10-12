// LIVE 12-joint stand / sit-squat geometry. This is NOT a trained classifier.
// 2D coordinates are screen-space (+y down). Use ratios, never pixel height.
const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v))

export function estimateSquatStrength({
  spanL, spanR, liftL = 0, liftR = 0,
  kneeFlexL = 0, kneeFlexR = 0
}) {
  if (![spanL, spanR, liftL, liftR, kneeFlexL, kneeFlexR]
      .every(Number.isFinite) || spanL < -0.35 || spanR < -0.35) return 0

  // As BOTH legs shorten relative to the torso, the hips are closer to the feet.
  // Taking max(spanL, spanR) ensures raising one leg is NOT counted as crouching.
  const bilateralCompression = clamp((1.14 - Math.max(spanL, spanR)) / 0.33, 0, 1)
  // In a front view some crouches retain similar ankle heights; two bent knees
  // supply secondary evidence, bounded so knee noise cannot force full squat.
  const bentKnees = clamp((Math.min(kneeFlexL, kneeFlexR) - 0.22) / 0.65, 0, 1)
  const score = Math.max(bilateralCompression, bentKnees * 0.65)
  const oneLegUp = clamp(Math.max(liftL, liftR), 0, 1)
  return clamp(score * (1 - oneLegUp), 0, 1)
}
