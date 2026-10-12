// LIVE CSI CNN 12-joint estimates -> optional three-state visualizer.
// This is a VIEWER-ONLY posture gate, not a new CNN classifier or a trained model.
// Never feed canonical visualization coordinates back into the backend/FPGA.
import { createEditorPreset } from './poseEditor.js'

export const LIVE_THREE_ACTIONS = Object.freeze({
  stand: '정자세', squat: '스쿼트', bothArmsUp: '양팔 동시에 올리기'
})

const finite = value => typeof value === 'number' && Number.isFinite(value)
const now = () => typeof performance !== 'undefined' ? performance.now() : Date.now()
const byId = pose => new Map(pose.joints.map(j => [Number(j.id), j]))
const jcoord = (joint, key) => Number(joint?.[key])

export function classifyLiveThreeAction(pose) {
  if (!pose?.valid || !Array.isArray(pose.joints) || pose.joints.length !== 12) return null
  const j = byId(pose)
  if (j.size !== 12) return null
  const ids = [11,12,13,14,15,16,23,24,25,26,27,28]
  if (!ids.every(id => j.has(id) && finite(jcoord(j.get(id),'x')) && finite(jcoord(j.get(id),'y')))) return null
  const shoulderY = (j.get(11).y + j.get(12).y)/2
  const hipY = (j.get(23).y + j.get(24).y)/2
  const torso = hipY - shoulderY
  if (!(torso > 1e-6)) return null

  // Only accept a simultaneous full-arm raise, not a single wrist spike.
  const armsUp = [[11,13,15],[12,14,16]].every(([shoulder,elbow,wrist]) =>
    j.get(wrist).y < j.get(shoulder).y - torso*0.02 &&
    j.get(elbow).y < j.get(shoulder).y + torso*0.26)

  // Consistent with poseAngles.js: knees and ankles compress toward the pelvis.
  // One raised leg alone must NOT be classified as squat.
  const legL = (j.get(27).y - j.get(23).y) / torso
  const legR = (j.get(28).y - j.get(24).y) / torso
  const squatScore = Math.max(0, Math.min(1, (1.10 - Math.max(legL,legR)) / 0.27))
  const squat = squatScore >= 0.58 && legL > 0.10 && legR > 0.10
  if (squat) return 'squat'
  if (armsUp) return 'bothArmsUp'
  return 'stand'
}

function frameKeyOf(pose) {
  const key = pose.source_timestamp_us ?? pose.end_trigger_seq ?? pose.window_id
  return key == null
    ? pose.joints.map(j => `${j.id}:${j.x}:${j.y}`).join('|')
    : String(key)
}

const canonicalPose = Object.freeze({
  stand: createEditorPreset('stand'),
  squat: createEditorPreset('squat'),
  bothArmsUp: createEditorPreset('bothArmsUp')
})

export class LiveThreeActionLimiter {
  constructor({confirmFrames=3, minHoldMs=650} = {}) {
    this.confirmFrames = Math.max(1, Math.floor(confirmFrames))
    this.minHoldMs = Math.max(0, minHoldMs)
    this.reset()
  }
  reset() {
    this.active = null
    this.candidate = null
    this.votes = 0
    this.lastSwitchAt = -Infinity
    this.lastFrameKey = null
    this.lastOutput = null
  }
  push(pose, atMs=now()) {
    const detected=classifyLiveThreeAction(pose)
    if (!detected) { this.reset(); return null }
    const key=frameKeyOf(pose)
    if (key===this.lastFrameKey && this.lastOutput) return this.lastOutput
    this.lastFrameKey=key

    if (this.active===null) {
      this.active=detected
      this.lastSwitchAt=atMs
    } else if (detected===this.active) {
      this.candidate=null
      this.votes=0
    } else {
      if (this.candidate===detected) this.votes++
      else {this.candidate=detected;this.votes=1}
      if (this.votes>=this.confirmFrames && atMs-this.lastSwitchAt>=this.minHoldMs) {
        this.active=detected
        this.lastSwitchAt=atMs
        this.candidate=null
        this.votes=0
      }
    }

    // Canonical 2D joint geometry is for display only. Retain timing metadata
    // for snapshot deduplication and mark the result as LIVE-derived visualization.
    const template=canonicalPose[this.active]
    this.lastOutput={
      ...pose,
      valid:true,
      coordinate_space:'fake_normalized',
      joints:template.joints.map(j=>({...j})),
      live_three_action:this.active,
      live_three_visualization:true,
      test_pose:`live_three_${this.active}`
    }
    return this.lastOutput
  }
}
