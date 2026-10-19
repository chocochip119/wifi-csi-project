import {legGeometryEvidence} from './legGeometryEvidence.js'

// Location mode is deliberately display-only: never forward live arm/lift
// angles to the avatar. P10 is an already confirmed location-class prediction.
// Seated posture at other locations needs bilateral joint geometry evidence.
export function locationSeatEvidence(location, pose, angles) {
  if (!location?.valid || location.empty) return {sitting:false,source:'invalid'}
  if (String(location.pointId).toLowerCase()==='p10')
    return {sitting:true,source:'p10'}
  const geometry=legGeometryEvidence(pose)
  return {sitting:Boolean(geometry?.bilateral && (angles?.squat??0)>=0.22),
    source:'bilateral-joints'}
}

export class LocationPostureTracker {
  constructor({confirmFrames=2}={}) {
    this.confirmFrames=Math.max(1,Math.floor(confirmFrames))
    this.reset()
  }
  reset() {
    this.sitting=false
    this.lastKey=null
    this.lastPointId=null
    this.candidate=null
    this.votes=0
  }
  update(location,pose,angles) {
    const evidence=locationSeatEvidence(location,pose,angles)
    const id=String(location?.pointId ?? '')
    if(id!==this.lastPointId) {
      this.lastPointId=id
      this.lastKey=null
      this.candidate=null
      this.votes=0
      this.sitting=false
    }
    if(evidence.source==='invalid') {this.reset();return {sit:false,source:'standing'}}
    // P10 has already passed the Backend location stabilizer; do not add
    // another 900ms location dwell or 3-frame pose confirmation.
    if(evidence.source==='p10') {
      this.sitting=true;this.candidate=null;this.votes=0
      return {sit:true,source:'location-p10'}
    }
    const stamp=pose?.source_timestamp_us ?? pose?.end_trigger_seq ?? pose?.window_id
    const key=pose?.valid && Array.isArray(pose.joints)
      ? stamp==null ? pose.joints.map(j=>`${j.id}:${j.x}:${j.y}`).join('|') : String(stamp)
      : null
    if(key===null) {
      // Never manufacture sitting outside P10 from missing data.
      this.sitting=false;this.candidate=null;this.votes=0;this.lastKey=null
      return {sit:false,source:'standing'}
    }
    if(key!==this.lastKey) {
      this.lastKey=key
      if(evidence.sitting!==this.sitting) {
        if(evidence.sitting===this.candidate) this.votes++
        else {this.candidate=evidence.sitting;this.votes=1}
        if(this.votes>=this.confirmFrames) {
          this.sitting=evidence.sitting;this.candidate=null;this.votes=0
        }
      } else {this.candidate=null;this.votes=0}
    }
    return {sit:this.sitting,source:this.sitting?'bilateral-joints':'standing'}
  }
}
