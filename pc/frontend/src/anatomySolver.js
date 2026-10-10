// Model-independent body constraints. Units: metres and degrees.
// 2D CSI joint estimates are not a depth measurement: these parameters express
// explicit forward-depth priors that operators can tune while inspecting the rig.
export const DEFAULT_ANATOMY_CONFIG = Object.freeze({
  seatedKneeDeg: 105,
  seatDepthGain: 1.12,
  kneeForward: 0.95,
  armClearance: 0.11
})
export const ANATOMY_LIMITS = Object.freeze({
  seatedKneeDeg: [75, 130],
  seatDepthGain: [0.65, 1.5],
  kneeForward: [0.35, 1],
  armClearance: [0.04, 0.25]
})
const clamp = (v,a,b) => Math.max(a,Math.min(b,v))
export function normalizeAnatomyConfig(input = {}) {
  const out={}
  for(const [key,[lo,hi]] of Object.entries(ANATOMY_LIMITS)){
    const candidate=input?.[key]
    const value=(typeof candidate==='number'&&Number.isFinite(candidate))
      ? candidate : DEFAULT_ANATOMY_CONFIG[key]
    out[key]=clamp(value,lo,hi)
  }
  return out
}
// The included knee angle is 180° at straight extension; flexion is 0° there.
export function twoBoneTriangle(upperLen,lowerLen,distance){
  if(![upperLen,lowerLen,distance].every(Number.isFinite) ||
     upperLen<=0.02||lowerLen<=0.02||distance<=0)return null
  const lowerBound=Math.abs(upperLen-lowerLen)+0.005
  const upperBound=upperLen+lowerLen-0.005
  if(lowerBound>=upperBound)return null
  const d=clamp(distance,lowerBound,upperBound)
  const along=(upperLen*upperLen-lowerLen*lowerLen+d*d)/(2*d)
  const height=Math.sqrt(Math.max(0,upperLen*upperLen-along*along))
  return {distance:d,along,height,clamped:Math.abs(d-distance)>1e-5}
}
// The pelvis drop comes from the avatar's measured thigh/shin lengths, not
// a hardcoded 0.18-m translation. Never request unreachable foot placement.
export function calculateSeatDrop(upperLen,lowerLen,neutralHipFoot,score,config = DEFAULT_ANATOMY_CONFIG){
  if(![upperLen,lowerLen,neutralHipFoot,score].every(Number.isFinite) ||
     upperLen<=0.02||lowerLen<=0.02||neutralHipFoot<=0)return null
  const c=normalizeAnatomyConfig(config)
  const amount=clamp(score,0,1)
  const kneeDeg=c.seatedKneeDeg*amount
  const cos=Math.cos(kneeDeg*Math.PI/180)
  const targetReach=Math.sqrt(Math.max(0,upperLen*upperLen+lowerLen*lowerLen+2*upperLen*lowerLen*cos))
  // Limit distance reduction to what the planted two-bone chain can reach.
  const minReach=Math.abs(upperLen-lowerLen)+0.03
  const geometricDrop=Math.max(0,neutralHipFoot-Math.max(targetReach,minReach))
  const maxSafeDrop=Math.max(0,neutralHipFoot-minReach)
  return {drop:clamp(geometricDrop*c.seatDepthGain,0,Math.min(maxSafeDrop,0.58)),
    flexionDeg:kneeDeg,targetReach,amount}
}
// Used to decide whether a hand target is inside the chest/tummy column.
// Coordinates are *body-local* metres, +y up and +z toward avatar's front.
export function resolveTorsoHandClearance({x,y,z,halfWidth,halfHeight,clearance}){
  if(![x,y,z,halfWidth,halfHeight,clearance].every(Number.isFinite) ||
     halfWidth<=0||halfHeight<=0)return null
  const margin=Math.max(0,clearance)
  // Don't alter hands far outside the upper/lower torso, even if they cross
  // the body's image projection (e.g. a hand above the head).
  const nearTorso=Math.abs(x)<=halfWidth+margin &&
    y>=-halfHeight-margin && y<=halfHeight+margin
  const frontRequired=Math.max(0.08,halfWidth*0.65)+margin
  const delta=nearTorso ? Math.max(0,frontRequired-z):0
  return {x,y,z:z+delta,corrected:delta>1e-6,delta,frontRequired}
}
