import {legGeometryEvidence} from './legGeometryEvidence.js'

// Joints provide primary evidence; P10 can provide separate, temporally stable
// location evidence if the CSI pose is poorly observed. Never classify a single
// raised leg as sitting solely because the position model returns P10.
export function classifyLegPosture(pose, angles, pointId = '') {
  const geometry=legGeometryEvidence(pose)
  if (!geometry || !angles) return {action:'stand',strength:0,geometry}
  const lift=Math.max(angles.liftL??0,angles.liftR??0)
  if (geometry.unilateral && lift>=0.14) {
    // Distinctly asymmetric knee+ankle evidence can activate on one frame.
    // Moderate evidence still requires two different CNN frames.
    const strong=lift>=0.55 &&
      ((geometry.ankleAsym>=0.26 && geometry.kneeAsym>=0.15) ||
       (geometry.ankleAsym>=0.17 && geometry.kneeAsym>=0.25))
    return {action:'lift',strength:Math.max(0.35,Math.min(1,lift)),geometry,strong}
  }
  const squat=Math.max(0,Number(angles.squat)||0)
  // A front-view seated pose can have knees near the hips but ankles still
  // close to the floor. The old 0.21 score boundary missed this common shape.
  // Require BILATERAL knee compression or a milder squat score; unilateral
  // ankle/knee rise is already handled above and must never become a squat.
  const kneesNearHips=Math.max(geometry.kneeL,geometry.kneeR)<0.38 &&
    Math.max(geometry.ankleL,geometry.ankleR)<1.19
  if (geometry.bilateral && (squat>=0.14 || kneesNearHips ||
      (String(pointId).toLowerCase()==='p10' && squat>=0.10)))
    return {action:'squat',strength:Math.max(0.78,squat),geometry}
  return {action:'stand',strength:0,geometry}
}

function poseKey(pose) {
  if (!pose?.valid || !Array.isArray(pose.joints)) return null
  const metadata=pose.source_timestamp_us ?? pose.end_trigger_seq ?? pose.window_id
  return metadata!=null ? String(metadata) :
    pose.joints.map(j=>`${j.id}:${j.x}:${j.y}`).join('|')
}

export class StableLegPosture {
  constructor({confirmFrames=3,squatConfirmFrames=2,releaseSquatFrames=5,
    liftConfirmFrames=2,releaseLiftFrames=4,minHoldMs=650,crossSwitchFrames=4,
    staleMs=4200,p10MinMs=900}={}) {
    this.confirmFrames=Math.max(1,Math.floor(confirmFrames))
    this.squatConfirmFrames=Math.max(1,Math.floor(squatConfirmFrames))
    this.releaseSquatFrames=Math.max(this.squatConfirmFrames,Math.floor(releaseSquatFrames))
    this.liftConfirmFrames=Math.max(1,Math.floor(liftConfirmFrames))
    this.releaseLiftFrames=Math.max(this.confirmFrames,Math.floor(releaseLiftFrames))
    this.crossSwitchFrames=Math.max(this.confirmFrames,Math.floor(crossSwitchFrames))
    this.minHoldMs=Math.max(0,minHoldMs)
    this.staleMs=Math.max(0,staleMs)
    this.p10MinMs=Math.max(0,p10MinMs)
    this.reset()
  }
  reset() {
    this.action='stand';this.strength=0;this.side=null;this.source='joints'
    this.candidate=null;this.votes=0
    this.switchedAt=-Infinity;this.lastFrameAt=null;this.lastKey=null
    this.p10Since=null;this.p10WindowKeys=new Set()
  }
  get state() {
    return {action:this.action,strength:this.action==='stand'?0:this.strength,
      side:this.side,source:this.source}
  }
  _switch(action,strength,side,atMs,source='joints') {
    this.action=action;this.strength=strength;this.side=side
    this.source=source;this.switchedAt=atMs;this.candidate=null;this.votes=0
  }
  update(pose,angles,pointId='',atMs=0,locationWindowKey=null) {
    if (!Number.isFinite(atMs)) return this.state
    if (this.lastFrameAt!==null && (atMs<this.lastFrameAt || atMs-this.lastFrameAt>this.staleMs)) {
      // Do not re-activate a strong one-frame gesture from the SAME stale
      // snapshot immediately after clearing the old held action.
      const staleKey=poseKey(pose)
      const wasDuplicate=staleKey!==null && staleKey===this.lastKey
      this.reset()
      if (wasDuplicate) return this.state
    }
    const observed=classifyLegPosture(pose,angles,pointId)
    const geom=observed.geometry
    const raised=observed.action==='lift' || Boolean(geom?.unilateral)
    const p10=String(pointId).toLowerCase()==='p10' && !raised
    if (p10) {
      if (this.p10Since===null || atMs<this.p10Since) {
        this.p10Since=atMs;this.p10WindowKeys.clear()
      }
      if (locationWindowKey!==null && locationWindowKey!==undefined)
        this.p10WindowKeys.add(String(locationWindowKey))
    } else {
      this.p10Since=null;this.p10WindowKeys.clear()
    }
    const locationElapsed=p10 ? atMs-this.p10Since : 0
    // Require two different PS location windows; without window IDs a longer
    // stable dwell is needed. A previous confirmed lift needs extra evidence.
    const locationEvidence=p10 && locationElapsed>=this.p10MinMs &&
      (this.p10WindowKeys.size>=2 || (locationWindowKey==null && locationElapsed>=1700))
    const fromLift=this.action==='lift'
    const liftToSitReady=!fromLift ||
      (locationElapsed>=1500 &&
       (this.p10WindowKeys.size>=3 || (locationWindowKey==null && locationElapsed>=2500)))
    if (locationEvidence && liftToSitReady && atMs-this.switchedAt>=this.minHoldMs &&
        this.action!=='squat') {
      this._switch('squat',0.85,null,atMs,'stable-p10')
    }
    const key=poseKey(pose)
    if (key===null || key===this.lastKey) return this.state
    this.lastKey=key;this.lastFrameAt=atMs
    // When P10 is stable but 12-joint data appear upright, do not repeatedly
    // undo the seated avatar on every CNN frame. A lifted leg always vetoes.
    if (this.action==='squat' && this.source==='stable-p10' && p10 &&
        observed.action==='stand') return this.state
    if (observed.action===this.action) {
      this.candidate=null;this.votes=0
      if (this.action!=='stand')
        this.strength+=Math.max(-0.10,Math.min(0.10,(observed.strength-this.strength)*0.22))
      return this.state
    }
    if (observed.action!==this.candidate) {
      this.candidate=observed.action;this.votes=1
    } else this.votes++
    const cross=this.action!=='stand' && observed.action!=='stand'
    // Sitting starts on two distinct CNN frames, rather than the old three.
    // Exiting an established seated pose requires five consecutive standing
    // observations; a noisy frame must not make the avatar pop upright.
    const needed=cross?this.crossSwitchFrames:
      this.action==='lift' ? this.releaseLiftFrames :
      this.action==='squat' ? this.releaseSquatFrames :
      observed.action==='lift' && observed.strong ? 1 :
      observed.action==='lift' ? this.liftConfirmFrames :
      observed.action==='squat' ? this.squatConfirmFrames : this.confirmFrames
    if (this.votes>=needed && atMs-this.switchedAt>=this.minHoldMs) {
      this._switch(observed.action,observed.strength,
        observed.action==='lift'?geom?.raisedSide:null,atMs)
    }
    return this.state
  }
}
