import * as THREE from 'three'
import { FOOT_STANCE_MIN, FOOT_STANCE_MAX, LIMB_SEGMENTS, solvePoseAngles } from './poseAngles.js'
import {DEFAULT_ANATOMY_CONFIG, normalizeAnatomyConfig, calculateSeatDrop, 
  twoBoneTriangle, resolveTorsoHandClearance} from './anatomySolver.js'

const vec = () => new THREE.Vector3()
const quat = () => new THREE.Quaternion()
const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v))
const normalized = (name) => name.toLowerCase().replace(/[^a-z0-9]/g, '')

function findBones(root) {
  const map = new Map()
  root.traverse(node => { if (node.isBone) map.set(normalized(node.name),node) })
  return name => map.get(normalized(name)) || null
}

function aim(bone, axisLocal, worldDirection) {
  if (!bone?.parent || !axisLocal || worldDirection.lengthSq() < 1e-10) return
  const oldWorld=bone.getWorldQuaternion(quat())
  const current=axisLocal.clone().applyQuaternion(oldWorld).normalize()
  const worldDelta=quat().setFromUnitVectors(current,worldDirection.clone().normalize())
  const parentInverse=bone.parent.getWorldQuaternion(quat()).invert()
  const targetLocal=parentInverse.multiply(worldDelta).multiply(oldWorld).normalize()
  bone.quaternion.copy(targetLocal)
  bone.updateWorldMatrix(false,true)
}

// Plant both independent Foot bones. Bend each knee slightly toward the front
// when 2D indicates a squat; 2D has no depth, so this is a bounded assumption.
function plantedKnee(hip,ankle,upperLen,lowerLen,bendWorld) {
  const delta=ankle.clone().sub(hip)
  const raw=delta.length()
  if(!Number.isFinite(raw) || raw<0.03 || upperLen<0.03 || lowerLen<0.03) return null
  const triangle=twoBoneTriangle(upperLen,lowerLen,raw)
  if(!triangle)return null
  const axis=delta.normalize()
  const {along,height:outward}=triangle
  const bend=bendWorld.clone().addScaledVector(axis,-bendWorld.dot(axis))
  if(bend.lengthSq()<1e-8) return null
  return hip.clone().addScaledVector(axis,along).addScaledVector(bend.normalize(),outward)
}

export class PoseRigController {
  constructor(character) {
    this.character=character
    const bone=findBones(character)
    this.body=bone('Body')
    this.hips=bone('Hips')
    this.baseHipsRotation=this.hips?.quaternion.clone() || null
    this.segments=LIMB_SEGMENTS.map(s=>({...s,node:bone(s.bone),child:bone(s.child),axis:null,length:0,filtered:null}))
    this.legs=['L','R'].map(side=>({
      side, upper:bone(`UpperLeg.${side}`),lower:bone(`LowerLeg.${side}`),
      foot:bone(`Foot.${side}`),length:0,shinAxis:null, lastFootTarget:null,
      // Post-mixer rotations from the previous frame, for damping the SAME R pose.
      smoothedUpper:null, smoothedLower:null
    }))
    this.ready=Boolean(this.body&&this.hips&&this.segments.every(s=>s.node&&s.child) &&
      this.legs.every(l=>l.foot?.parent && l.upper && l.lower))
    this.calibrated=false
    this.active=false
    this.armEnabled=false
    this.legEnabled=false
    this.solution=null
    this.inputAt=0
    this.warnAt=0
    this.config=normalizeAnatomyConfig(DEFAULT_ANATOMY_CONFIG)
    this.lastBodyBase=null
    this.squatAmount=0
    this.lastSeatedDrop=0
    this.lastSeatedFlex=0
    this.lastArmCorrected=0
    this.armIK={L:{upper:null,lower:null},R:{upper:null,lower:null}}
    this.armNeutral=null
    // Applied lift amount is rate-limited, independent of WebSocket/animation FPS.
    // Keep the last lift pose briefly during release so R -> S does not snap.
    this.liftAmount=0
    this.liftSource=null
    this.liftSide=null
    // Fixed starting shoe location for a single R hold (character local space).
    // Never recompute R target relative to the shoe modified by last frame's IK.
    this.liftAnchorLocal=null
    this.footStanceRatio=null
    if (!this.ready) console.warn('[PoseRig anatomical] Missing required model bones — using Idle/Walk only')
    else console.log('[PoseRig anatomical] 12 joints / 8 segments ready (planted seat IK + chest clearance)')
  }
  setConfig(next) {
    this.config=normalizeAnatomyConfig(next)
  }
  // Undo the previous post-mixer pelvis offset before the next animation update.
  // Without this, rigs where Body.position has no animation track sink every frame.
  prepareFrame() {
    if(this.lastBodyBase && this.body) this.body.position.copy(this.lastBodyBase)
    this.lastBodyBase=null
  }
  diagnostics() {
    return {seatDropM:Number(this.lastSeatedDrop.toFixed(3)),
      targetKneeFlexDeg:Number(this.lastSeatedFlex.toFixed(1)),
      armCollisionCorrections:this.lastArmCorrected, 
      calibrated:this.calibrated,ready:this.ready, config:{...this.config}}
  }
  calibrate() {
    if (!this.ready) return false
    this.character.updateMatrixWorld(true)
    for (const s of this.segments) {
      const start=s.node.getWorldPosition(vec())
      const end=s.child.getWorldPosition(vec())
      const delta=end.sub(start)
      s.length=delta.length()
      if (s.length<0.02) return false
      s.axis=delta.normalize().applyQuaternion(s.node.getWorldQuaternion(quat()).invert()).normalize()
    }
    for (const leg of this.legs) {
      // Foot is a separate Root child, not a child of LowerLeg in these GLTFs.
      const knee=leg.lower.getWorldPosition(vec())
      const foot=leg.foot.getWorldPosition(vec())
      const delta=foot.sub(knee)
      leg.length=delta.length()
      if (leg.length<0.02) return false
      leg.shinAxis=delta.normalize().applyQuaternion(leg.lower.getWorldQuaternion(quat()).invert()).normalize()
    }
    // Neutral local rotations make repeated direction-only IK deterministic.
    // Wrists have no orientation measurement in the 12-point CSI output.
    const arms=this.segments.filter(s=>s.type==='arm')
    const wrists=arms.filter(s=>s.key.startsWith('forearm')).map(s=>s.child)
    this.armNeutral=[...arms.map(s=>s.node),...wrists]
      .map(node=>({node,rotation:node.quaternion.clone()}))
    this.calibrated=true
    return true
  }
  // Scale shoe-center distance from 55% to 150% of the measured 3D pelvis width.
  // AnimationMixer restores the original independent Foot bones every frame.
  applyFootStance(state,dt,xWorld) {
    if(!Number.isFinite(state?.footSpacingRatio)) return false
    this.character.updateMatrixWorld(true)
    const left=this.legs.find(leg=>leg.side==='L')
    const right=this.legs.find(leg=>leg.side==='R')
    const hipL=left.upper.getWorldPosition(vec())
    const hipR=right.upper.getWorldPosition(vec())
    const pelvisWidth=Math.abs(hipR.clone().sub(hipL).dot(xWorld))
    if(pelvisWidth<1e-5) return false
    const footL=left.foot.getWorldPosition(vec())
    const footR=right.foot.getWorldPosition(vec())
    const neutralWidth=Math.abs(footR.clone().sub(footL).dot(xWorld))
    if(this.footStanceRatio===null)
      this.footStanceRatio=clamp(neutralWidth/pelvisWidth,FOOT_STANCE_MIN,FOOT_STANCE_MAX)
    const targetRatio=clamp(state.footSpacingRatio,FOOT_STANCE_MIN,FOOT_STANCE_MAX)
    const alpha=clamp(1-Math.exp(-Math.max(0,dt)*9),0,0.45)
    if(Math.abs(targetRatio-this.footStanceRatio)>0.015)
      this.footStanceRatio+=(targetRatio-this.footStanceRatio)*alpha
    this.footStanceRatio=clamp(this.footStanceRatio,FOOT_STANCE_MIN,FOOT_STANCE_MAX)

    const center=hipL.clone().add(hipR).multiplyScalar(0.5).dot(xWorld)
    const leftSign=Math.sign(hipL.clone().sub(hipR).dot(xWorld)) || -1
    const width=pelvisWidth*this.footStanceRatio
    const proposals=[
      {leg:left,hip:hipL,original:footL,target:center+leftSign*width*0.5},
      {leg:right,hip:hipR,original:footR,target:center-leftSign*width*0.5}
    ]
    // Reject unreachable targets for BOTH legs before writing either shoe.
    for(const item of proposals) {
      item.goal=item.original.clone().addScaledVector(xWorld,item.target-item.original.dot(xWorld))
      const upper=this.segments.find(seg=>seg.key===`thigh${item.leg.side}`)?.length
      const lower=item.leg.length
      const dist=item.hip.distanceTo(item.goal)
      if(!Number.isFinite(dist)||!upper||!lower ||
         dist > (upper+lower)*1.03 || dist < Math.abs(upper-lower)*0.97) return false
    }
    for(const {leg,goal} of proposals) {
      leg.foot.parent.updateWorldMatrix(true,false)
      leg.foot.position.copy(leg.foot.parent.worldToLocal(goal.clone()))
    }
    this.character.updateMatrixWorld(true)
    return true
  }
  setPose(pose,mirrored=false,options={}) {
    const solution=solvePoseAngles(pose,mirrored)
    if (!this.ready || !solution) { this.clear();return }
    const arms=options.arms===true
    const legs=options.legs===true &&
      (solution.activity>0.14 || Number.isFinite(solution.footSpacingRatio))
    if (!arms && !legs) { this.clear();return }
    this.solution=solution
    this.armEnabled=arms
    this.legEnabled=legs
    this.active=true
    this.inputAt=performance.now()
  }
  clear() {
    // The last lift target is intentionally retained while liftAmount eases out.
    this.active=false
    this.solution=null
    this.armEnabled=false
    this.legEnabled=false
    this.squatAmount=0
    this.lastSeatedDrop=0
    this.lastSeatedFlex=0
    this.lastArmCorrected=0
    this.footStanceRatio=null
    for(const entry of Object.values(this.armIK)){entry.upper=null;entry.lower=null}
    if (this.hips&&this.baseHipsRotation) this.hips.quaternion.copy(this.baseHipsRotation)
    for(const s of this.segments) s.filtered=null
    for(const leg of this.legs) leg.lastFootTarget=null
    // Next mixer.update will restore all animation-controlled bones.
  }
  update(dt,enabled=true) {
    if(!this.ready || !enabled) {
      if(!enabled) {
        this.liftAmount=0;this.liftSource=null;this.liftSide=null;this.liftAnchorLocal=null
        for(const leg of this.legs) {leg.smoothedUpper=null;leg.smoothedLower=null}
      }
      return
    }
    if(this.active && performance.now()-this.inputAt>1500) this.clear()
    const liveState=this.active?this.solution:null
    // A valid leg lift must use the same 2D pose as the right-hand Pose panel.
    const requestedLift=Boolean(liveState && this.legEnabled && liveState.squat<=0.22 &&
      Math.max(liveState.liftL,liveState.liftR)>0.25)
    if(requestedLift) {
      this.liftSource=liveState
      const requestedSide=liveState.liftL>=liveState.liftR?'L':'R'
      // Avoid switching left/right on a tiny change while the same pose is held.
      if(!this.liftSide || (this.liftAmount<0.05 && this.liftSide!==requestedSide)) {
        this.liftSide=requestedSide
        this.liftAnchorLocal=null
        for(const leg of this.legs) {leg.smoothedUpper=null;leg.smoothedLower=null}
      }
    }
    const desired=requestedLift?clamp(Math.max(liveState.liftL,liveState.liftR),0,1):0
    // At 60 fps, the foot changes by at most ~0.005m per frame (before IK).
    // Slower rise than fall; even S/T test-mode exits release smoothly.
    const speed=desired>this.liftAmount?1.05:1.35
    const step=Math.max(0,Math.min(dt,0.05))*speed
    this.liftAmount+=clamp(desired-this.liftAmount,-step,step)
    if(this.liftAmount<0.0001 && desired===0) {
      this.liftAmount=0
      this.liftSource=null
      this.liftSide=null
      this.liftAnchorLocal=null
      for(const leg of this.legs) {leg.smoothedUpper=null;leg.smoothedLower=null}
    }
    if(!liveState && this.liftAmount===0) return
    if(!this.calibrated&&!this.calibrate()) return
    const smooth=clamp(1-Math.exp(-Math.max(0,dt)*13),0,0.55)
    const rootQuaternion=this.character.getWorldQuaternion(quat())
    const xWorld=new THREE.Vector3(1,0,0).applyQuaternion(rootQuaternion)
    const yWorld=new THREE.Vector3(0,1,0).applyQuaternion(rootQuaternion)
    const zWorld=new THREE.Vector3(0,0,1).applyQuaternion(rootQuaternion)
    const state=liveState || this.liftSource
    // Squat and leg lift are exclusive; prevent two IK solvers fighting.
    const plantedSquat=Boolean(liveState && this.legEnabled && liveState.squat>0.075 &&
      liveState.liftL<0.2 && liveState.liftR<0.2)
    const targetSquat=plantedSquat?liveState.squat:0
    const squatSmoothing=clamp(1-Math.exp(-Math.max(0,dt)*9),0,0.5)
    this.squatAmount+=(targetSquat-this.squatAmount)*squatSmoothing
    if(plantedSquat && this.liftAmount>0) {
      this.liftAmount=0
      this.liftSource=null
      this.liftSide=null
    }
    const liftedLeg=!plantedSquat && (requestedLift || this.liftAmount>0.0001) && Boolean(this.liftSource)
    const restFrame=(this.legEnabled || liftedLeg) ? {
      bodyPosition:this.body.position.clone(), hipsRotation:this.hips.quaternion.clone(),
      legs:this.legs.map(l=>({upper:l.upper.quaternion.clone(),lower:l.lower.quaternion.clone(),foot:l.foot.position.clone()}))
    } : null
    const stanceApplied=Boolean(liveState && this.legEnabled && !liftedLeg &&
      this.applyFootStance(liveState,dt,xWorld))
    // Compute the seat height using EACH leg's calibrated lengths and its
    // neutral hip-to-foot spacing. The shallower reachable leg is the limit.
    this.lastSeatedDrop=0
    this.lastSeatedFlex=0
    if(plantedSquat && this.squatAmount>0.001) {
      const results=[]
      for(const leg of this.legs) {
        const upperSeg=this.segments.find(seg=>seg.key===`thigh${leg.side}`)
        const hip=leg.upper.getWorldPosition(vec())
        const ankle=leg.foot.getWorldPosition(vec())
        const knee=calculateSeatDrop(upperSeg.length,leg.length,
          hip.distanceTo(ankle),this.squatAmount,this.config)
        if(knee)results.push(knee)
      }
      if(results.length===2) {
        const depth=Math.min(...results.map(item=>item.drop))
        const scale=this.body.parent.getWorldScale(vec())
        this.lastBodyBase=this.body.position.clone()
        this.body.position.y-=depth/Math.max(0.01,Math.abs(scale.y))
        this.body.position.z-=Math.min(0.08,depth*0.12)/Math.max(0.01,Math.abs(scale.z))
        this.lastSeatedDrop=depth
        this.lastSeatedFlex=Math.min(...results.map(item=>item.flexionDeg))
        if(this.baseHipsRotation) {
          const lean=quat().setFromAxisAngle(new THREE.Vector3(1,0,0),
            0.25*this.squatAmount)
          this.hips.quaternion.copy(this.baseHipsRotation).premultiply(lean).normalize()
        }
        this.character.updateMatrixWorld(true)
      }
    } else if(this.baseHipsRotation) this.hips.quaternion.copy(this.baseHipsRotation)

    // Mixer/previous-frame rotations must not become the next frame's twist
    // baseline: wrist orientation is unobservable from the twelve 2D joints.
    if(this.armEnabled && this.armNeutral) {
      for(const {node,rotation} of this.armNeutral)node.quaternion.copy(rotation)
      this.character.updateMatrixWorld(true)
    }
    // Calibrated bone axes plus the SAME 2D segment headings used by the SVG.
    // Apply upper before lower: the child rotates with its parent.
    for(const s of this.segments) {
      if((s.type==='arm'&&!this.armEnabled) || (s.type==='leg'&&(!this.legEnabled||plantedSquat||liftedLeg||stanceApplied))) continue
      const heading=state.directions.get(s.key)?.angle
      if(!Number.isFinite(heading)) continue
      // Preserve frontal direction; add limited inferred knee forward bend only
      // when both feet are shorter on screen (squat).
      const squatDepth=s.type==='leg' ? state.squat*0.20*(s.upper?1:-1) : 0
      const desired=xWorld.clone().multiplyScalar(Math.sin(heading))
        .addScaledVector(yWorld,-Math.cos(heading)).addScaledVector(zWorld,squatDepth).normalize()
      if(!s.filtered) s.filtered=s.axis.clone().applyQuaternion(s.node.getWorldQuaternion(quat())).normalize()
      s.filtered.lerp(desired,smooth).normalize()
      aim(s.node,s.axis,s.filtered)
      this.character.updateMatrixWorld(true)
    }

    // Apply the chest clearance AFTER the ordinary screen-plane arm headings.
    // End effectors near the torso are pushed forward and solved by a two-bone arm.
    this.lastArmCorrected=0
    if(liveState && this.armEnabled) {
      const shoulders=this.segments.filter(seg=>seg.key==='upperArmL'||seg.key==='upperArmR')
      const chest=shoulders[0].node.getWorldPosition(vec())
        .add(shoulders[1].node.getWorldPosition(vec())).multiplyScalar(0.5)
      const hips=this.legs[0].upper.getWorldPosition(vec())
        .add(this.legs[1].upper.getWorldPosition(vec())).multiplyScalar(0.5)
      const center=chest.clone().lerp(hips,0.43)
      const shoulderWidth=shoulders[0].node.getWorldPosition(vec())
        .distanceTo(shoulders[1].node.getWorldPosition(vec()))
      const torsoHeight=chest.distanceTo(hips)
      if(torsoHeight>0.09 && shoulderWidth>0.09) {
        const uvScale=clamp(torsoHeight/liveState.torso,0.0001,100000)
        for(const side of ['L','R']){
          const id=side==='L' ? {sh:11,wr:15} : {sh:12,wr:16}
          const sh2=liveState.point.get(id.sh),wr2=liveState.point.get(id.wr)
          const upper=this.segments.find(seg=>seg.key===`upperArm${side}`)
          const lower=this.segments.find(seg=>seg.key===`forearm${side}`)
          const shoulder=upper.node.getWorldPosition(vec())
          const goal=shoulder.clone()
            .addScaledVector(xWorld,(wr2.x-sh2.x)*uvScale)
            .addScaledVector(yWorld,-(wr2.y-sh2.y)*uvScale)
          const relative=goal.clone().sub(center)
          const boundary=resolveTorsoHandClearance({
            x:relative.dot(xWorld),y:relative.dot(yWorld),z:relative.dot(zWorld),
            halfWidth:shoulderWidth*0.48,halfHeight:torsoHeight*0.57,
            clearance:this.config.armClearance})
          if(!boundary?.corrected){
            this.armIK[side].upper=null;this.armIK[side].lower=null
            continue
          }
          goal.addScaledVector(zWorld,boundary.delta)
          // Guard reach before the elbow plane solve; otherwise aim could flip.
          const reach=goal.clone().sub(shoulder)
          const maxReach=upper.length+lower.length-0.012
          const minReach=Math.abs(upper.length-lower.length)+0.015
          if(reach.length()<0.015 || maxReach<=minReach)continue
          const length=reach.length()
          if(length>maxReach)goal.copy(shoulder).addScaledVector(reach,maxReach/length)
          if(length<minReach)goal.copy(shoulder).addScaledVector(reach,minReach/length)
          const shoulderSide=shoulder.clone().sub(center).dot(xWorld)
          const outward=shoulderSide===0?(side==='L'?-1:1):Math.sign(shoulderSide)
          const pole=xWorld.clone().multiplyScalar(outward)
            .addScaledVector(zWorld,0.50).addScaledVector(yWorld,-0.10).normalize()
          const elbow=plantedKnee(shoulder,goal,upper.length,lower.length,pole)
          if(!elbow)continue
          const priorUpper=upper.node.quaternion.clone()
          aim(upper.node,upper.axis,elbow.sub(shoulder))
          const targetUpper=upper.node.quaternion.clone()
          const armAlpha=clamp(1-Math.exp(-Math.max(0,dt)*15),0.04,0.65)
          const smoothed=this.armIK[side]
          if(smoothed.upper)upper.node.quaternion.copy(smoothed.upper).slerp(targetUpper,armAlpha)
          else upper.node.quaternion.copy(priorUpper).slerp(targetUpper,armAlpha)
          smoothed.upper=upper.node.quaternion.clone()
          this.character.updateMatrixWorld(true)
          const elbowWorld=lower.node.getWorldPosition(vec())
          const priorLower=lower.node.quaternion.clone()
          aim(lower.node,lower.axis,goal.sub(elbowWorld))
          const targetLower=lower.node.quaternion.clone()
          if(smoothed.lower)lower.node.quaternion.copy(smoothed.lower).slerp(targetLower,armAlpha)
          else lower.node.quaternion.copy(priorLower).slerp(targetLower,armAlpha)
          smoothed.lower=lower.node.quaternion.clone()
          this.character.updateMatrixWorld(true)
          this.lastArmCorrected++
        }
      }
    }

    // Grounded standing and squat use the same two-bone IK, so shoes never
    // slide away from their shins as the stance width changes.
    if(plantedSquat || stanceApplied) {
      const targets=[]
      for(const leg of this.legs) {
        const upperSeg=this.segments.find(s=>s.key===`thigh${leg.side}`)
        const hip=leg.upper.getWorldPosition(vec())
        const ankle=leg.foot.getWorldPosition(vec())
        const ids=leg.side==='L' ? [23,25] : [24,26]
        const p=state.point.get(ids[0]),k=state.point.get(ids[1])
        const lateral=clamp((k.x-p.x)/state.torso,-0.5,0.5)
        const bend=zWorld.clone().multiplyScalar(this.config.kneeForward)
          .addScaledVector(yWorld,-(1-this.config.kneeForward)*0.75)
          .addScaledVector(xWorld,lateral*0.55).normalize()
        const knee=plantedKnee(hip,ankle,upperSeg.length,leg.length,bend)
        if(!knee) break
        targets.push({leg,upperSeg,hip,ankle,knee})
      }
      if(targets.length!==2) {
        if(restFrame) {
          this.body.position.copy(restFrame.bodyPosition)
          this.hips.quaternion.copy(restFrame.hipsRotation)
          this.legs.forEach((leg,i)=>{
            leg.upper.quaternion.copy(restFrame.legs[i].upper)
            leg.lower.quaternion.copy(restFrame.legs[i].lower)
            leg.foot.position.copy(restFrame.legs[i].foot)
          })
          this.lastBodyBase=null
          this.character.updateMatrixWorld(true)
        }
        return
      }
      for(const {leg,upperSeg,hip,ankle,knee} of targets) {
        aim(leg.upper,upperSeg.axis,knee.sub(hip))
        this.character.updateMatrixWorld(true)
        const currentKnee=leg.lower.getWorldPosition(vec())
        aim(leg.lower,leg.shinAxis,ankle.sub(currentKnee))
        this.character.updateMatrixWorld(true)
      }
      return
    }

    // R hold: one stable shoe anchor + one shared 2-bone IK target.
    // IMPORTANT: even while R stays selected, mixer.update() runs every frame.
    // Therefore never use a PREVIOUSLY MODIFIED shoe as the next starting point;
    // it can build a frame-to-frame feedback loop and visually snap the leg.
    if(liftedLeg) {
      const liftSide=this.liftSide
      const pose=this.liftSource
      const amount=this.liftAmount
      const leg=this.legs.find(l=>l.side===liftSide)
      const upperSeg=this.segments.find(s=>s.key===`thigh${liftSide}`)
      if(!leg || !upperSeg) return
      // Capture neutral shoe exactly once per held R action.
      if(!this.liftAnchorLocal) {
        this.character.updateMatrixWorld(true)
        this.liftAnchorLocal=this.character.worldToLocal(leg.foot.getWorldPosition(vec()))
      }
      const hip=leg.upper.getWorldPosition(vec())
      const ankle2D=pose.point.get(liftSide==='L'?27:28)
      const hip2D=pose.point.get(liftSide==='L'?23:24)
      const observedKnee=liftSide==='L'?pose.kneeL:pose.kneeR
      const kneeFlex=clamp(observedKnee?.flex??0,0,1)
      if(!ankle2D || !hip2D) return
      const lateral=clamp((ankle2D.x-hip2D.x)/pose.torso,-0.6,0.6)
      const target=this.character.localToWorld(this.liftAnchorLocal.clone())
        .addScaledVector(yWorld,(0.25+0.10*kneeFlex)*amount)
        .addScaledVector(zWorld,0.19*amount)
        .addScaledVector(xWorld,lateral*0.065*amount)
      // Stay away from exact full extension (near-singular knee flip).
      const delta=target.clone().sub(hip)
      const maxReach=upperSeg.length+leg.length-0.025
      const minReach=Math.abs(upperSeg.length-leg.length)+0.025
      const distance=delta.length()
      if(!Number.isFinite(distance)||distance<0.02||maxReach<=minReach) return
      if(distance>maxReach) target.copy(hip).addScaledVector(delta,maxReach/distance)
      if(distance<minReach) target.copy(hip).addScaledVector(delta,minReach/distance)
      // Different 2D knee positions must produce visibly different bend
      // directions even when ankle height (liftAmount) happens to be identical.
      const bend=zWorld.clone().multiplyScalar(0.7)
        .addScaledVector(xWorld,(observedKnee?.lateral??0)*2.2)
        .addScaledVector(yWorld,(observedKnee?.vertical??0)*1.3)
        .normalize()
      const knee=plantedKnee(hip,target,upperSeg.length,leg.length,bend)
      if(!knee) return
      const alpha=clamp(1-Math.exp(-Math.max(0,dt)*9),0,0.5)
      // Smooth UPPER LEG rotation, not only the shoe location.
      aim(leg.upper,upperSeg.axis,knee.sub(hip))
      const upperGoal=leg.upper.quaternion.clone()
      if(leg.smoothedUpper) leg.upper.quaternion.copy(leg.smoothedUpper).slerp(upperGoal,alpha)
      leg.smoothedUpper=leg.upper.quaternion.clone()
      this.character.updateMatrixWorld(true)
      const kneeWorld=leg.lower.getWorldPosition(vec())
      aim(leg.lower,leg.shinAxis,target.clone().sub(kneeWorld))
      const lowerGoal=leg.lower.quaternion.clone()
      if(leg.smoothedLower) leg.lower.quaternion.copy(leg.smoothedLower).slerp(lowerGoal,alpha)
      leg.smoothedLower=leg.lower.quaternion.clone()
      this.character.updateMatrixWorld(true)
      // Separate GLTF Foot bone: attach its shoe to the ACTUAL damped shin tip,
      // not a second independently moving target (avoids disconnected/snapping foot).
      const shoeWorld=leg.lower.getWorldPosition(vec()).add(
        leg.shinAxis.clone().applyQuaternion(leg.lower.getWorldQuaternion(quat())).normalize().multiplyScalar(leg.length)
      )
      leg.foot.parent.updateWorldMatrix(true,false)
      leg.foot.position.copy(leg.foot.parent.worldToLocal(shoeWorld))
      leg.lastFootTarget=shoeWorld.clone()
      this.character.updateMatrixWorld(true)
      return
    }

    // The two independent Foot bones are NOT children of LowerLeg in this GLTF.
    // To prevent shoes stretching away from the calf, ALL proposed foot corrections
    // are validated before changing either foot. Unsafe frame -> neutral legs.
    if(this.legEnabled) {
      const corrections=[]
      let safe=true
      for(const leg of this.legs) {
        const originalFoot=leg.foot.getWorldPosition(vec())
        const knee=leg.lower.getWorldPosition(vec())
        const shaft=leg.shinAxis.clone().applyQuaternion(leg.lower.getWorldQuaternion(quat())).normalize()
        const target=knee.addScaledVector(shaft,leg.length)
        const shift=target.clone().sub(originalFoot)
        const footSafe=Number.isFinite(shift.length()) && shift.length() < 0.65 &&
          shift.y > -0.055 && shift.y < 0.43 && target.y >= 0.008
        corrections.push({leg,target,shift})
        safe &&= footSafe
      }
      if(safe) {
        for(const {leg,target,shift} of corrections) {
          if(shift.length()<0.008) continue
          const next=leg.lastFootTarget ? leg.lastFootTarget.clone().lerp(target,smooth) : target
          leg.lastFootTarget=next.clone()
          leg.foot.parent.updateWorldMatrix(true,false)
          leg.foot.position.copy(leg.foot.parent.worldToLocal(next))
        }
        this.character.updateMatrixWorld(true)
      } else {
        // This also restores the squat body drop if the foot cannot stay planted.
        this.body.position.copy(restFrame.bodyPosition)
        this.hips.quaternion.copy(restFrame.hipsRotation)
        this.legs.forEach((leg,i)=>{
          leg.upper.quaternion.copy(restFrame.legs[i].upper)
          leg.lower.quaternion.copy(restFrame.legs[i].lower)
          leg.foot.position.copy(restFrame.legs[i].foot)
          leg.lastFootTarget=null
        })
        this.character.updateMatrixWorld(true)
        for(const s of this.segments) if(s.type==='leg') s.filtered=null
        if(performance.now()-this.warnAt>2500) {
          this.warnAt=performance.now()
          console.warn('[PoseRig anatomical] unsafe leg/foot frame rejected; neutral legs restored')
        }
      }
    }

  }
  footStatus() {
    if(!this.ready) return null
    this.character.updateMatrixWorld(true)
    return this.legs.map(l=>({side:l.side,y:l.foot.getWorldPosition(vec()).y}))
  }
}
