// 12-joint image-space evidence. +y points down; normalize against torso height.
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
  const unilateral=ankleAsym>0.14 && (kneeAsym>0.075 || ankleAsym>0.34) &&
    supportingAnkle>0.75 && supportingKnee>0.25 &&
    (kneeAsym<0.075 || Math.sign(ankleDiff)===Math.sign(kneeDiff))
  // A real seated/crouched person viewed from the front can still have fairly
  // low ankles. Allow moderate ankle span while checking BOTH knees, symmetry
  // and an independent upright rejection. This never uses the location label
  // to synthesize motion-mode sitting.
  const upright=Math.min(aL,aR)>1.08 && Math.min(kL,kR)>0.40
  const bothLegsBent=Math.max(aL,aR)<1.20 && Math.max(kL,kR)<0.67
  const bilateral=!unilateral && !upright && ankleAsym<0.24 &&
    kneeAsym<0.22 && bothLegsBent
  return {unilateral, bilateral, upright, raisedSide,
    ankleAsym,kneeAsym, ankleL:aL,ankleR:aR,kneeL:kL,kneeR:kR}
}
