import {POSE_PRESETS, JOINT_NAMES, EDITOR_IDS, EDITOR_EDGES,
  createEditorPreset, asEditorPose, updateEditorJoint, blendEditorPose, normalizeBackendPose} from './poseEditor.js'
import './adminController.css'

const $ = id => document.getElementById(id)
const channel = new BroadcastChannel('wisensing-viewer-settings-v1')
const params = new URLSearchParams(location.search)
const backend = new URL(params.get('backend') || (location.protocol + '//' + location.hostname + ':8000'),location.href).origin
let state = {settings:{locationMode:'live',manualPoint:'p05',jointsMode:'live',liveArms:true,liveLegs:true},
  cameraView:'front',mirrorMode:'auto'}
let receivedViewer = false
let pose = createEditorPreset('stand')
let selectedJoint = 15
let frames = []
let playing = null
let dragging = null
let playerIndex = 0
let stepIndex = 0
let originalLive = null

function sendSetting(key,value){
  channel.postMessage({type:'update',key,value})
  state.settings[key]=value
  renderSettings()
}
function sendCustom(){
  channel.postMessage({type:'custom-pose',pose})
  if(state.settings.jointsMode!=='custom'){
    sendSetting('jointsMode','custom')
  }
  $('admin-source').value='custom'
  $('admin-preview-status').textContent='TEST 12관절을 스켈레톤과 3D 캐릭터에 함께 전송'
}
function showMessage(message){$('admin-test-message').textContent=message}
function renderSettings(){
  $('admin-location-mode').value=state.settings.locationMode||'live'
  $('admin-source').value=['live','custom','off'].includes(state.settings.jointsMode)
    ? state.settings.jointsMode : 'custom'
  $('admin-arms').checked=state.settings.liveArms!==false
  $('admin-legs').checked=state.settings.liveLegs!==false
  $('admin-camera').value=state.cameraView||'front'
  $('admin-mirror').value=state.mirrorMode||'auto'
  $('admin-manual-points').hidden=state.settings.locationMode!=='manual'
  document.querySelectorAll('[data-admin-point]').forEach(btn=>{
    btn.classList.toggle('current',btn.dataset.adminPoint===state.settings.manualPoint)
  })
  $('admin-preview-status').textContent=(state.settings.jointsMode==='live'?'LIVE FPGA':
    state.settings.jointsMode==='off'?'관절 표시 안 함':'TEST 편집 좌표')+
    ' · 팔 '+(state.settings.liveArms?'ON':'OFF')+' · 다리 '+(state.settings.liveLegs?'ON':'OFF')
}
function sendRequest(){
  channel.postMessage({type:'hello'})
  setTimeout(()=>{if(!receivedViewer)channel.postMessage({type:'hello'})},850)
}
channel.addEventListener('message',ev=>{
  const data=ev.data
  if(data?.type!=='state'||!data.settings)return
  receivedViewer=true
  state=data
  renderSettings()
})
$('admin-location-mode').addEventListener('change',ev=>sendSetting('locationMode',ev.target.value))
$('admin-source').addEventListener('change',ev=>{
  const mode=ev.target.value
  if(mode==='custom'){channel.postMessage({type:'custom-pose',pose})}
  sendSetting('jointsMode',mode)
})
$('admin-arms').addEventListener('change',ev=>sendSetting('liveArms',ev.target.checked))
$('admin-legs').addEventListener('change',ev=>sendSetting('liveLegs',ev.target.checked))
$('admin-camera').addEventListener('change',ev=>channel.postMessage({type:'update',key:'cameraView',value:ev.target.value}))
$('admin-mirror').addEventListener('change',ev=>channel.postMessage({type:'update',key:'mirrorMode',value:ev.target.value}))
document.querySelectorAll('[data-admin-point]').forEach(btn=>btn.addEventListener('click',()=>{
  sendSetting('manualPoint',btn.dataset.adminPoint)
  sendSetting('locationMode','manual')
}))
$('admin-all-live').addEventListener('click',()=>{
  stopPlayer()
  channel.postMessage({type:'all-live'})
  state.settings.locationMode='live'
  state.settings.jointsMode='live'
  renderSettings()
})
$('admin-reset').addEventListener('click',()=>{
  stopPlayer()
  pose=createEditorPreset('stand')
  frames=[]
  selectedJoint=15
  renderEditor()
  renderFrames()
  channel.postMessage({type:'reset'})
  state.settings={locationMode:'live',manualPoint:'p05',jointsMode:'live',liveArms:true,liveLegs:true}
  renderSettings()
})
function putPose(next,broadcast=true){
  if(!next){showMessage('12개 관절의 번호와 X/Y 좌표를 확인하세요.');return}
  pose=next
  renderEditor()
  if(broadcast)sendCustom()
}
function choosePreset(name){
  stopPlayer()
  try{
    putPose(createEditorPreset(name))
    showMessage('선택한 관절 좌표를 적용했습니다: '+POSE_PRESETS.find(item=>item.id===name)?.label)
  }catch(err){showMessage(String(err))}
}
const presetSelect=$('admin-preset')
POSE_PRESETS.forEach(item=>{
  const option=document.createElement('option');option.value=item.id;option.textContent=item.label
  presetSelect.appendChild(option)
})
presetSelect.addEventListener('change',ev=>choosePreset(ev.target.value))
const jointSelect=$('admin-joint')
EDITOR_IDS.forEach(id=>{
  const opt=document.createElement('option');opt.value=String(id)
  opt.textContent=String(id)+' · '+JOINT_NAMES[id]
  jointSelect.appendChild(opt)
})
jointSelect.value=String(selectedJoint)
jointSelect.addEventListener('change',ev=>{
  selectedJoint=Number(ev.target.value);renderEditor()
})
for(const axis of ['x','y']){
  $('admin-joint-'+axis).addEventListener('input',ev=>{
    const xy=pose.joints.find(j=>j.id===selectedJoint)
    const newValue=Number(ev.target.value)
    if(ev.target.value===''||!Number.isFinite(newValue))return
    const next=updateEditorJoint(pose,selectedJoint,axis==='x'?newValue:xy.x,axis==='y'?newValue:xy.y)
    if(next)putPose(next)
  })
}
$('admin-joint-nudge').addEventListener('click',()=>{
  const id=selectedJoint;const item=pose.joints.find(j=>j.id===id)
  if(!item)return
  putPose(updateEditorJoint(pose,id,Math.round(item.x*100)/100,Math.round(item.y*100)/100))
})
function svgElem(name,attrs){
  const el=document.createElementNS('http://www.w3.org/2000/svg',name)
  for(const [k,v] of Object.entries(attrs))el.setAttribute(k,String(v))
  return el
}
const canvas=$('admin-joint-canvas')
function editorPixel(joint){return {x:30+joint.x*340,y:20+joint.y*450}}
function renderEditor(){
  $('admin-joint').value=String(selectedJoint)
  const selected=pose.joints.find(j=>j.id===selectedJoint)
  if(selected){
    if(document.activeElement!==$('admin-joint-x'))$('admin-joint-x').value=selected.x.toFixed(3)
    if(document.activeElement!==$('admin-joint-y'))$('admin-joint-y').value=selected.y.toFixed(3)
  }
  canvas.replaceChildren()
  canvas.appendChild(svgElem('rect',{x:30,y:20,width:340,height:450,rx:9,fill:'#0b1821',stroke:'#385363'}))
  const points=new Map(pose.joints.map(j=>[j.id,editorPixel(j)]))
  for(const [a,b] of EDITOR_EDGES){
    const from=points.get(a),to=points.get(b)
    canvas.appendChild(svgElem('line',{x1:from.x,y1:from.y,x2:to.x,y2:to.y,
      stroke:'#64cec4','stroke-width':4,'stroke-linecap':'round'}))
  }
  for(const joint of pose.joints){
    const xy=points.get(joint.id),active=joint.id===selectedJoint
    const circle=svgElem('circle',{cx:xy.x,cy:xy.y,r:active?10:7,fill:active?'#ffe09a':'#e4fbf6',
      stroke:active?'#ffbc48':'#17595e','stroke-width':active?3:2,'data-joint-id':joint.id})
    circle.style.cursor='grab'
    canvas.appendChild(circle)
    const label=svgElem('text',{x:xy.x+11,y:xy.y-7,fill:active?'#ffe09a':'#99c5c8',
      'font-size':12,'pointer-events':'none'})
    label.textContent=String(joint.id)
    canvas.appendChild(label)
  }
}
canvas.addEventListener('pointerdown',ev=>{
  const id=Number(ev.target?.getAttribute('data-joint-id'))
  if(!EDITOR_IDS.includes(id))return
  stopPlayer()
  selectedJoint=id
  dragging=ev.pointerId
  canvas.setPointerCapture(ev.pointerId)
  renderEditor()
})
canvas.addEventListener('pointermove',ev=>{
  if(dragging!==ev.pointerId)return
  const rect=canvas.getBoundingClientRect()
  const viewX=(ev.clientX-rect.left)*400/rect.width
  const viewY=(ev.clientY-rect.top)*500/rect.height
  const x=Math.round(Math.max(-.2,Math.min(1.2,(viewX-30)/340))*1000)/1000
  const y=Math.round(Math.max(-.2,Math.min(1.2,(viewY-20)/450))*1000)/1000
  putPose(updateEditorJoint(pose,selectedJoint,x,y))
})
for(const name of ['pointerup','pointercancel','lostpointercapture']){
  canvas.addEventListener(name,()=>{dragging=null})
}
$('admin-save-frame').addEventListener('click',()=>{
  if(frames.length>=100){showMessage('최대 100개의 프레임을 저장할 수 있습니다.');return}
  frames.push(asEditorPose(pose))
  renderFrames()
  showMessage('현재 좌표를 프레임 '+frames.length+'로 저장했습니다.')
})
$('admin-clear-frames').addEventListener('click',()=>{
  stopPlayer();frames=[];renderFrames()
})
function renderFrames(){
  $('admin-frame-count').textContent='저장된 자세 '+frames.length+'개'
  const list=$('admin-frame-list');list.replaceChildren()
  frames.forEach((frame,index)=>{
    const btn=document.createElement('button')
    btn.textContent='#'+(index+1);btn.title='저장한 관절 자세 재적용'
    btn.addEventListener('click',()=>{stopPlayer();putPose(asEditorPose(frame));})
    list.appendChild(btn)
  })
}
function stopPlayer(){
  if(playing!==null){clearInterval(playing);playing=null}
  $('admin-play-frames').textContent='▶ 연속 재생'
}
$('admin-play-frames').addEventListener('click',()=>{
  if(playing!==null){stopPlayer();return}
  if(frames.length<2){showMessage('연속 재생하려면 자세 2개 이상을 저장해 주세요.');return}
  sendCustom();playerIndex=0;stepIndex=0
  playing=setInterval(()=>{
    const start=frames[playerIndex%frames.length]
    const target=frames[(playerIndex+1)%frames.length]
    const interpolated=blendEditorPose(start,target,stepIndex/10)
    if(interpolated)putPose(interpolated)
    stepIndex++
    if(stepIndex>10){stepIndex=0;playerIndex=(playerIndex+1)%frames.length}
  },85)
  $('admin-play-frames').textContent='■ 재생 중지'
})
function asDownload(name,content){
  const blob=new Blob([JSON.stringify(content,null,2)],{type:'application/json'})
  const url=URL.createObjectURL(blob)
  const link=document.createElement('a');link.href=url;link.download=name
  document.body.appendChild(link);link.click();link.remove()
  setTimeout(()=>URL.revokeObjectURL(url),1000)
}
$('admin-export').addEventListener('click',()=>{
  asDownload('wisensing_pose_test.json',{type:'pose_test',version:1,
    pose,frames})
})
$('admin-import-file').addEventListener('change',async ev=>{
  const file=ev.target.files?.[0]
  if(!file)return
  try{
    if(file.size>1048576)throw Error('파일이 1MB를 넘습니다.')
    const json=JSON.parse(await file.text())
    const next=asEditorPose(json.pose||json)
    const imported=Array.isArray(json.frames)?json.frames.map(asEditorPose):[]
    if(!next||imported.includes(null)||imported.length>100)throw Error('12관절 JSON 형식을 확인하세요.')
    stopPlayer();frames=imported;putPose(next);renderFrames()
    showMessage('JSON 좌표와 저장된 자세를 불러왔습니다.')
  }catch(err){showMessage('불러오기 실패: '+String(err))}
  ev.target.value=''
})
$('admin-capture-live').addEventListener('click',async()=>{
  try{
    const ctrl=new AbortController()
    const tm=setTimeout(()=>ctrl.abort(),3000)
    let response
    try{response=await fetch(backend+'/api/snapshot',{signal:ctrl.signal,cache:'no-store'})}
    finally{clearTimeout(tm)}
    if(!response.ok)throw Error('HTTP '+response.status)
    const json=await response.json()
    originalLive=json.pose
    const normalized=normalizeBackendPose(json.pose)
    if(!normalized||json.pose?.valid!==true)throw Error('유효한 실제 12관절 데이터가 없습니다.')
    stopPlayer();putPose(normalized)
    showMessage('현재 Backend 좌표를 화면 테스트용으로 정규화해 복사했습니다. 원본은 관리자 진단에 그대로 남습니다.')
  }catch(err){showMessage('실제 관절 복사 실패: '+String(err))}
})
$('admin-preview-refresh').addEventListener('click',()=>{
  const iframe=$('admin-main-preview')
  iframe.src='/'
  receivedViewer=false;setTimeout(sendRequest,300)
})
window.addEventListener('beforeunload',()=>{stopPlayer();channel.close()})
renderEditor();renderFrames();renderSettings();sendRequest()
