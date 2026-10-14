// Only use the 12 measured image-space joints; +y points down.
// Torso-normalized comparisons are invariant to image size/placement.
export function legGeometryEvidence(pose) {
  if (!pose?.valid || !Array.isArray(pose.joints)) return null
  const pts = new Map(pose.joints.map(j => [Number(j.id),j]))
  const ids=[11,12,23,24,25,26,27,28]
  if (!ids.every(id => pts.has(id) && ['x','y'].every(k =>
    Number.isFinite(Number(pts.get(id)[k]))))) return null
  const y=id=>Number(pts.get(id).y)
  const torso=(y(23)+y(24)-y(11)-y(12))/2
  if (!(torso>1e-6)) return null
  const aL=(y(27)-y(23))/torso, aR=(y(28)-y(24))/torso
  const kL=(y(25)-y(23))/torso, kR=(y(26)-y(24))/torso
  if (![aL,aR,kL,kR].every(v=>Number.isFinite(v) && v>-0.4 && v<5)) return null
  const ankleDiff=aR-aL, kneeDiff=kR-kL
  const raisedSide=ankleDiff>=0?'L':'R'
  const ankleAsym=Math.abs(ankleDiff), kneeAsym=Math.abs(kneeDiff)
  const supportingAnkle=Math.max(aL,aR)
  const supportingKnee=raisedSide==='L'?kR:kL
  const unilateral=ankleAsym>0.22 && (kneeAsym>0.12 || ankleAsym>0.42) &&
    supportingAnkle>0.82 && supportingKnee>0.31 &&
    (kneeAsym<0.09 || Math.sign(ankleDiff)===Math.sign(kneeDiff))
  const bothLegsBent=Math.max(aL,aR)<1.12 && Math.max(kL,kR)<0.55
  const bilateral=!unilateral && ankleAsym<0.24 && kneeAsym<0.22 && bothLegsBent
  const upright=Math.min(aL,aR)>1.08 && Math.min(kL,kR)>0.40
  return {unilateral, bilateral, upright, raisedSide,
    ankleAsym,kneeAsym, ankleL:aL,ankleR:aR,kneeL:kL,kneeR:kR}
}
