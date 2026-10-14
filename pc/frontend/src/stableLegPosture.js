import {legGeometryEvidence} from './legGeometryEvidence.js'

// Debounce visual 3D actions using DISTINCT CNN frames. P10 is a location
// prior, never proof of a seated pose on its own.
export function classifyLegPosture(pose, angles, pointId = '') {
  const geometry=legGeometryEvidence(pose)
  if (!geometry || !angles) return {action:'stand',strength:0,geometry}
  const lift=Math.max(angles.liftL??0,angles.liftR??0)
  if (geometry.unilateral && lift>=0.23)
    return {action:'lift',strength:Math.min(1,lift),geometry}
  const squat=Math.max(0,Number(angles.squat)||0)
  if (geometry.bilateral && (squat>=0.26 ||
      (String(pointId).toLowerCase()==='p10' && squat>=0.12)))
    return {action:'squat',strength:Math.max(0.63,squat),geometry}
  return {action:'stand',strength:0,geometry}
}

function poseKey(pose) {
  if (!pose?.valid || !Array.isArray(pose.joints)) return null
  const metadata=pose.source_timestamp_us ?? pose.end_trigger_seq ?? pose.window_id
  return metadata!=null ? String(metadata) :
    pose.joints.map(j=>`${j.id}:${j.x}:${j.y}`).join('|')
}

export class StableLegPosture {
  constructor({confirmFrames=3, minHoldMs=750, crossSwitchFrames=5,
    staleMs=1500}={}) {
    this.confirmFrames=Math.max(1,Math.floor(confirmFrames))
    this.crossSwitchFrames=Math.max(this.confirmFrames,Math.floor(crossSwitchFrames))
    this.minHoldMs=Math.max(0,minHoldMs)
    this.staleMs=Math.max(0,staleMs)
    this.reset()
  }
  reset() {
    this.action='stand'
    this.strength=0
    this.side=null
    this.candidate=null
    this.votes=0
    this.switchedAt=-Infinity
    this.lastFrameAt=0
    this.lastKey=null
  }
  get state() {
    return {action:this.action,strength:this.action==='stand'?0:this.strength,side:this.side}
  }
  update(pose,angles,pointId='',atMs=0) {
    const key=poseKey(pose)
    if (key===null) {
      if (!this.lastFrameAt || atMs-this.lastFrameAt>this.staleMs) this.reset()
      return this.state
    }
    if (key===this.lastKey) {
      if (atMs-this.lastFrameAt>this.staleMs) this.reset()
      return this.state
    }
    if (this.lastFrameAt && atMs-this.lastFrameAt>this.staleMs) this.reset()
    this.lastKey=key
    this.lastFrameAt=atMs
    const observed=classifyLegPosture(pose,angles,pointId)
    if (observed.action===this.action) {
      this.candidate=null
      this.votes=0
      if (this.action!=='stand')
        this.strength+=Math.max(-0.10,Math.min(0.10,(observed.strength-this.strength)*0.22))
      return this.state
    }
    if (observed.action!==this.candidate) {
      this.candidate=observed.action
      this.votes=1
    } else this.votes++
    const cross=this.action!=='stand' && observed.action!=='stand'
    const required=cross?this.crossSwitchFrames:this.confirmFrames
    const age=atMs-this.switchedAt
    if (this.votes>=required && age>=this.minHoldMs) {
      this.action=observed.action
      this.strength=observed.strength
      this.side=observed.action==='lift'?observed.geometry?.raisedSide:null
      this.switchedAt=atMs
      this.candidate=null
      this.votes=0
    }
    return this.state
  }
}
