import {createTestPose} from './poseTests.js'

export const JOINT_NAMES = Object.freeze({
  11:'왼쪽 어깨',12:'오른쪽 어깨',13:'왼쪽 팔꿈치',14:'오른쪽 팔꿈치',
  15:'왼쪽 손목',16:'오른쪽 손목',23:'왼쪽 골반',24:'오른쪽 골반',
  25:'왼쪽 무릎',26:'오른쪽 무릎',27:'왼쪽 발목',28:'오른쪽 발목'
})
export const EDITOR_IDS = Object.freeze(Object.keys(JOINT_NAMES).map(Number))
export const EDITOR_EDGES = Object.freeze([[11,12],[11,13],[13,15],[12,14],[14,16],
  [11,23],[12,24],[23,24],[23,25],[25,27],[24,26],[26,28]])
export const POSE_PRESETS = Object.freeze([
  {id:'stand',label:'기본 서기'},
  {id:'armUp',label:'왼팔 올리기'},
  {id:'armsWide',label:'양팔 벌리기'},
  {id:'squat',label:'스쿼트'},
  {id:'legLift',label:'왼다리 들기'},
  {id:'rightArmUp',label:'오른팔 올리기'},
  {id:'bothArmsUp',label:'양팔 위로'},
  {id:'leftElbowBent',label:'왼쪽 팔꿈치 굽히기'},
  {id:'rightElbowBent',label:'오른쪽 팔꿈치 굽히기'},
  {id:'handsForward',label:'양손 모으기'},
  {id:'rightLegLift',label:'오른다리 들기'},
  {id:'leftKneeBent',label:'왼 무릎 굽히기'},
  {id:'rightKneeBent',label:'오른 무릎 굽히기'},
  {id:'wideLegs',label:'다리 벌리기'},
  {id:'squatHandsUp',label:'스쿼트 + 팔 들기'},
  {id:'reachDiagonal',label:'대각선 뻗기'}
])

const CHANGES = Object.freeze({
  rightArmUp:{14:[.73,.13],16:[.83,.02]},
  bothArmsUp:{13:[.27,.13],15:[.17,.02],14:[.73,.13],16:[.83,.02]},
  leftElbowBent:{13:[.27,.37],15:[.37,.18]},
  rightElbowBent:{14:[.73,.37],16:[.63,.18]},
  handsForward:{13:[.42,.39],15:[.49,.36],14:[.58,.39],16:[.51,.36]},
  rightLegLift:{26:[.66,.58],28:[.65,.69]},
  leftKneeBent:{25:[.33,.67],27:[.42,.77]},
  rightKneeBent:{26:[.67,.67],28:[.58,.77]},
  wideLegs:{25:[.31,.74],27:[.23,.94],26:[.69,.74],28:[.77,.94]},
  squatHandsUp:{11:[.40,.31],12:[.60,.31],13:[.27,.16],15:[.17,.04],14:[.73,.16],16:[.83,.04],
    23:[.43,.65],24:[.57,.65],25:[.42,.78],26:[.58,.78],27:[.40,.94],28:[.60,.94]},
  reachDiagonal:{13:[.27,.13],15:[.16,.03],14:[.77,.34],16:[.91,.43]}
})
export function asEditorPose(value) {
  const items=Array.isArray(value) ? value : value?.joints
  if(!Array.isArray(items) || items.length!==12) return null
  const points=new Map()
  for(const item of items){
    const id=Number(item?.id),x=Number(item?.x),y=Number(item?.y)
    if(!EDITOR_IDS.includes(id)||points.has(id)||item?.x==null||item?.y==null||!Number.isFinite(x)||!Number.isFinite(y)||Math.max(Math.abs(x),Math.abs(y))>10)return null
    points.set(id,{id,x,y})
  }
  if(points.size!==12)return null
  return {valid:true,coordinate_space:'fake_normalized',test_pose:'custom',
    joints:EDITOR_IDS.map(id=>points.get(id))}
}
export function createEditorPreset(name){
  if(!POSE_PRESETS.some(p=>p.id===name))throw new Error('Unknown pose preset: '+name)
  if(['stand','armUp','armsWide','squat','legLift'].includes(name))
    return asEditorPose(createTestPose(name))
  const point=asEditorPose(createTestPose('stand'))
  for(const joint of point.joints){
    const xy=CHANGES[name]?.[joint.id]
    if(xy){joint.x=xy[0];joint.y=xy[1]}
  }
  return point
}
export function cloneEditorPose(pose){return asEditorPose(pose)}
export function updateEditorJoint(pose,id,x,y){
  const next=asEditorPose(pose)
  if(!next)return null
  const index=next.joints.findIndex(j=>j.id===Number(id))
  if(index<0 || ![x,y].every(Number.isFinite)||Math.max(Math.abs(x),Math.abs(y))>10)return null
  next.joints[index]={id:Number(id),x,y}
  return next
}
export function blendEditorPose(a,b,t){
  const from=asEditorPose(a), to=asEditorPose(b)
  if(!from||!to)return null
  const alpha=Math.max(0,Math.min(1,Number(t)))
  if(!Number.isFinite(alpha))return null
  return asEditorPose(from.joints.map((item,i)=>({
    id:item.id,x:item.x+(to.joints[i].x-item.x)*alpha,
    y:item.y+(to.joints[i].y-item.y)*alpha
  })))
}
export function normalizeBackendPose(raw){
  const input=raw?.joints
  if(!Array.isArray(input)||input.length!==12)return null
  const seen=new Map()
  for(const j of input){
    const id=Number(j?.id),x=Number(j?.x),y=Number(j?.y)
    if(!EDITOR_IDS.includes(id)||seen.has(id)||j?.x==null||j?.y==null ||
      !Number.isFinite(x)||!Number.isFinite(y)||Math.max(Math.abs(x),Math.abs(y))>1e7)return null
    seen.set(id,{id,x,y})
  }
  if(seen.size!==12)return null
  const joints=EDITOR_IDS.map(id=>seen.get(id))
  const xs=joints.map(j=>j.x),ys=joints.map(j=>j.y)
  const xMin=Math.min(...xs),xMax=Math.max(...xs),yMin=Math.min(...ys),yMax=Math.max(...ys)
  const span=Math.max(xMax-xMin,yMax-yMin)
  if(span<1e-8)return null
  return asEditorPose(joints.map(j=>({id:j.id,
    x:.10+(j.x-xMin)/span*.8,y:.10+(j.y-yMin)/span*.8})))
}
