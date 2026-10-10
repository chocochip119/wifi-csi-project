// WiSensing — one 2D geometry source for both Pose Result and 3D bone directions.
// Coordinates are SCREEN coordinates: +x right, +y down. Depth is not observable.
export const JOINT_IDS_12 = Object.freeze([11,12,13,14,15,16,23,24,25,26,27,28])
export const LIMB_SEGMENTS = Object.freeze([
  { key:'upperArmL', bone:'UpperArm.L', child:'LowerArm.L', a:11,b:13, type:'arm' },
  { key:'forearmL',  bone:'LowerArm.L', child:'Wrist.L',    a:13,b:15, type:'arm' },
  { key:'upperArmR', bone:'UpperArm.R', child:'LowerArm.R', a:12,b:14, type:'arm' },
  { key:'forearmR',  bone:'LowerArm.R', child:'Wrist.R',    a:14,b:16, type:'arm' },
  { key:'thighL',    bone:'UpperLeg.L', child:'LowerLeg.L', a:23,b:25, type:'leg', side:'L', upper:true },
  { key:'shinL',     bone:'LowerLeg.L', child:'Foot.L',     a:25,b:27, type:'leg', side:'L', upper:false },
  { key:'thighR',    bone:'UpperLeg.R', child:'LowerLeg.R', a:24,b:26, type:'leg', side:'R', upper:true },
  { key:'shinR',     bone:'LowerLeg.R', child:'Foot.R',     a:26,b:28, type:'leg', side:'R', upper:false }
])
const clamp = (v, a, b) => Math.max(a, Math.min(b, v))
const signedDelta = (a,b) => Math.atan2(Math.sin(a-b),Math.cos(a-b))
// Limit the distance between the shoes to the avatar's pelvis width.
export const FOOT_STANCE_MIN = 0.55
export const FOOT_STANCE_MAX = 1.0

export function solvePoseAngles(pose, mirrored = false) {
  if (!pose?.valid || !Array.isArray(pose.joints)) return null
  const point = new Map()
  for (const joint of pose.joints) {
    const id = Number(joint?.id), x = Number(joint?.x), y = Number(joint?.y)
    if (!JOINT_IDS_12.includes(id) || point.has(id) || !Number.isFinite(x) || !Number.isFinite(y)) return null
    point.set(id, { x: mirrored ? -x : x, y })
  }
  if (point.size !== JOINT_IDS_12.length) return null
  const shY = (point.get(11).y + point.get(12).y) / 2
  const hipY = (point.get(23).y + point.get(24).y) / 2
  const torso = hipY - shY
  if (torso <= 1e-6 || !Number.isFinite(torso)) return null
  const spanL = (point.get(27).y-point.get(23).y)/torso
  const spanR = (point.get(28).y-point.get(24).y)/torso
  if (![spanL,spanR].every(Number.isFinite) || Math.max(spanL, spanR) > 8 || Math.min(spanL, spanR) < -0.35) return null

  const liftL = clamp((spanR-spanL-0.13)/0.37,0,1)
  const liftR = clamp((spanL-spanR-0.13)/0.37,0,1)
  const squat = clamp((1.10-Math.max(spanL,spanR))/0.27,0,1)*(1-Math.max(liftL,liftR))
  const pelvisSpan = Math.abs(point.get(24).x - point.get(23).x)
  const ankleSpan = Math.abs(point.get(28).x - point.get(27).x)
  // Reject almost edge-on pelvis coordinates; they cannot define shoe spacing.
  const footSpacingRatio = pelvisSpan >= torso*0.10 ?
    clamp(ankleSpan/pelvisSpan,FOOT_STANCE_MIN,FOOT_STANCE_MAX) : null
  const outL = Math.abs(point.get(25).x - point.get(23).x)/torso
  const outR = Math.abs(point.get(26).x - point.get(24).x)/torso
  const legActivity = Math.max(liftL,liftR,squat,clamp((Math.max(outL,outR)-0.23)/0.48,0,1))

  const directions = new Map()
  for (const seg of LIMB_SEGMENTS) {
    const a=point.get(seg.a),b=point.get(seg.b)
    const dx=b.x-a.x,dy=b.y-a.y
    const length=Math.hypot(dx,dy)
    if (length < torso*0.012) return null
    const max= seg.type === 'leg' ? (seg.upper ? 1.12 : 1.22) : 2.9
    directions.set(seg.key,{ angle:clamp(Math.atan2(dx,dy),-max,max), length })
  }
  // Elbow/knee must remain a connected hinge. Limit relative 2D joint angle
  // instead of independently rotating child bones to impossible orientations.
  for (const side of ['L','R']) {
    for (const [upper, lower, limit] of [[`upperArm${side}`,`forearm${side}`,2.35],
                                         [`thigh${side}`,`shin${side}`,1.45]]) {
      const a=directions.get(upper), b=directions.get(lower)
      b.angle=a.angle+clamp(signedDelta(b.angle,a.angle),-limit,limit)
      if (lower.startsWith('shin')) b.angle=clamp(b.angle,-1.30,1.30)
    }
  }
  return { directions, point, torso, activity:legActivity, squat, liftL, liftR, footSpacingRatio }
}
