import './style.css'
import { setupManagedShutdown } from './launcherControl.js'
import * as THREE from 'three'
import { createRoomCameraControls } from './roomCameraControls.js'
import { createLivingRoomScene } from './livingRoomScene.js'
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js'
import { connectBackend } from './websocket.js'
import { PoseRigController } from './poseRig.js'
import {normalizeAnatomyConfig,DEFAULT_ANATOMY_CONFIG} from './anatomySolver.js'
import { solvePoseAngles, hasMeaningfulArmPose } from './poseAngles.js'
import { createTestPose } from './poseTests.js'
import { DEFAULT_VIEWER_SETTINGS, resolveViewerLocation, selectViewerPose } from './viewerSettings.js'
import { MIRROR_MODES, resolvePoseMirror, toDisplayX } from './poseOrientation.js'
import { PoseFilter, sanitizePose } from './poseInput.js'
import { parsePoseRecording } from './poseReplay.js'

// ========================================
// 화면 레이아웃
// ========================================
const app = document.querySelector('#app')
app.innerHTML = `
  <div class="app-shell">
    <header class="topbar">
      <div>
        <h1>WiSensing</h1>
        <p>Wireless Spatial Motion Viewer</p>
      </div>

      <div class="topbar-actions">
        <span class="viewer-badge" id="viewer-live-state">CONNECTING</span>
        <button id="viewer-settings-open" class="settings-trigger" type="button">⚙ 관리자 · 관절 테스트</button>
        <button id="viewer-stop-app" class="settings-trigger" type="button" hidden>⏻ 프로그램 종료</button>
      </div>
    </header>



    <main class="dashboard">
      <section class="scene-card">
        <div class="scene-title">
          <span>SPACE VIEW</span>
          <strong>Zone 5</strong>
        </div>
        <div class="location-view-switch" role="group" aria-label="3D 캐릭터 위치 표시 방식">
          <button type="button" id="mode-follow" class="selected" aria-pressed="true">위치 따라가기</button>
          <button type="button" id="mode-center" aria-pressed="false">중앙 고정 · 모션 보기</button>
        </div>
        <div id="scene-container"></div>
        <input id="pose-replay-file" type="file" accept=".json,.jsonl,.ndjson,application/json,text/plain" hidden>
        <div class="pose-replay-label" id="pose-replay-label" hidden>LOCAL REPLAY · B: LIVE 복귀</div>
        <div class="character-selector">
          <button class="character-button" data-character="Female01">
            <span class="avatar">F</span>Female01
          </button>
          <button class="character-button active" data-character="Male01">
            <span class="avatar">M</span>Male01
          </button>
          <button class="character-button" data-character="Male02">
            <span class="avatar">M</span>Male02
          </button>
          <button class="character-button" data-character="Female02">
            <span class="avatar">F</span>Female02
          </button>
        </div>
      </section>

      <aside class="result-column">
        <section class="result-card pose-card">
          <div class="card-header">
            <div><span class="eyebrow">AI INFERENCE</span><h2>POSE RESULT</h2></div>
            <span class="joint-badge">12 JOINTS</span>
          </div>
          <div class="pose-view">
            <svg id="pose-svg" viewBox="0 0 240 330" class="pose-svg">
              <g id="pose-lines" class="pose-lines"></g>
              <g id="pose-joints" class="pose-joints"></g>
            </svg>
            <div id="pose-unavailable" class="pose-unavailable show">Unavailable</div>
          </div>
          <div class="result-row">
            <span>Posture</span><strong>Unknown</strong>
          </div>
        </section>

        <section class="result-card location-card">
          <div class="card-header">
            <div><span class="eyebrow">POSITION</span><h2>LOCATION RESULT</h2></div>
          </div>
          <div class="location-main">
            <div class="location-number">P05</div>
            <div><span>Current Zone</span><strong>Zone 5</strong></div>
          </div>
          <div class="mini-grid">
            <div>P01</div><div>P02</div><div>P03</div>
            <div>P04</div><div class="selected">P05</div><div>P06</div>
            <div>P07</div><div>P08</div><div>P09</div>
          </div>
        </section>
      </aside>
    </main>
  </div>
`
setupManagedShutdown()

// ========================================
// Three.js: 카메라, 방, 조명
// ========================================
const container = document.querySelector('#scene-container')
const scene = new THREE.Scene()
scene.background = new THREE.Color(0x0c1923)
scene.fog = new THREE.Fog(0x0c1923, 12, 22)

const camera = new THREE.PerspectiveCamera(40, 1, 0.1, 100)
camera.position.set(0, 3.4, 7)
camera.lookAt(0, 1.05, 0)
const roomCameraControls = createRoomCameraControls(camera, container)

const renderer = new THREE.WebGLRenderer({ antialias: true })
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2))
renderer.shadowMap.enabled = true
renderer.shadowMap.type = THREE.PCFSoftShadowMap
renderer.outputColorSpace = THREE.SRGBColorSpace
renderer.toneMapping = THREE.ACESFilmicToneMapping
renderer.toneMappingExposure = 1.1
container.appendChild(renderer.domElement)

const hemiLight = new THREE.HemisphereLight(0xffe8d9, 0x16293e, 1.65)
scene.add(hemiLight)
const mainLight = new THREE.DirectionalLight(0xfff0de, 2.15)
mainLight.position.set(4, 8, 5)
mainLight.castShadow = true
scene.add(mainLight)
const warmLight = new THREE.PointLight(0xffc281, 8.0, 11)
warmLight.position.set(-3, 3.5, 1)
scene.add(warmLight)
const cyanLight = new THREE.PointLight(0x4bbdd9, 6.0, 8)
cyanLight.position.set(0, 1, 0)
scene.add(cyanLight)

// ========================================
// Warm living room and 9 live CSI tracking zones.
// The location/pose engine continues to use the same zonePositions.
const { zonePositions, updateZoneHighlight } = createLivingRoomScene(scene)

// ========================================
// 위치 / 자세 UI
// ========================================
function updateLocationUI(zone, pointId = null) {
  const pointName = pointId === 'p10' ? 'P10' : `P${String(zone).padStart(2, '0')}`
  document.querySelector('.scene-title strong').textContent = pointId === 'p10' ? 'Zone 5 · Sitting' : `Zone ${zone}`
  document.querySelector('.location-number').textContent = pointName
  document.querySelector('.location-main strong').textContent = `Zone ${zone}`
  document.querySelectorAll('.mini-grid div').forEach((cell) => {
    cell.classList.toggle('selected', cell.textContent.trim() === (pointId === 'p10' ? 'P05' : pointName))
  })
  updateZoneHighlight(zone)
}

function clearLocationUI(message) {
  document.querySelector('.scene-title strong').textContent = message
  document.querySelector('.location-number').textContent = '--'
  document.querySelector('.location-main strong').textContent = message
  document.querySelectorAll('.mini-grid div').forEach((cell) => {
    cell.classList.remove('selected')
  })
  updateZoneHighlight(0)
}

function updatePostureUI(posture) {
  const labels = {
    standing: 'Standing',
    sitting: 'Sitting',
    empty: 'No person',
    unknown: 'Unknown'
  }
  document.querySelector('.result-row strong').textContent = labels[posture] ?? 'Unknown'
}

// ========================================
// 실제 12관절 Pose: Backend pose.joints
// ========================================
const POSE_IDS = [11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28]
const POSE_CONNECTIONS = [
  [11, 12], [11, 13], [13, 15], [12, 14], [14, 16],
  [11, 23], [12, 24], [23, 24], [23, 25], [25, 27],
  [24, 26], [26, 28]
]
const SVG_NS = 'http://www.w3.org/2000/svg'
const poseSvg = document.querySelector('#pose-svg')
const poseLines = document.querySelector('#pose-lines')
const poseJoints = document.querySelector('#pose-joints')
const poseUnavailable = document.querySelector('#pose-unavailable')

function renderPose(pose, mirrored = false) {
  poseLines.replaceChildren()
  poseJoints.replaceChildren()

  const points = new Map()
  if (pose?.valid && Array.isArray(pose.joints)) {
    for (const joint of pose.joints) {
      const id = Number(joint.id)
      const x = Number(joint.x)
      const y = Number(joint.y)
      if (POSE_IDS.includes(id) && Number.isFinite(x) && Number.isFinite(y)) {
        points.set(id, { x, y })
      }
    }
  }

  if (POSE_IDS.some((id) => !points.has(id))) {
    poseSvg.style.visibility = 'hidden'
    poseUnavailable.classList.add('show')
    return
  }

  const xs = [...points.values()].map((point) => point.x)
  const ys = [...points.values()].map((point) => point.y)
  const minX = Math.min(...xs)
  const maxX = Math.max(...xs)
  const minY = Math.min(...ys)
  const maxY = Math.max(...ys)
  const spanX = maxX - minX
  const spanY = maxY - minY

  if (spanX < 1e-8 && spanY < 1e-8) {
    poseSvg.style.visibility = 'hidden'
    poseUnavailable.classList.add('show')
    return
  }

  // model_output, fake_normalized 모두 화면 안에 동일 비율로 맞춘다.
  const scale = Math.min(180 / Math.max(spanX, 1e-8), 280 / Math.max(spanY, 1e-8))
  const centerX = (minX + maxX) / 2
  const centerY = (minY + maxY) / 2
  const mapped = new Map()
  for (const [id, point] of points) {
    mapped.set(id, {
      x: 120 + toDisplayX(point.x - centerX, mirrored) * scale,
      y: 165 + (point.y - centerY) * scale
    })
  }

  for (const [a, b] of POSE_CONNECTIONS) {
    const start = mapped.get(a)
    const end = mapped.get(b)
    const line = document.createElementNS(SVG_NS, 'line')
    line.setAttribute('x1', start.x)
    line.setAttribute('y1', start.y)
    line.setAttribute('x2', end.x)
    line.setAttribute('y2', end.y)
    poseLines.appendChild(line)
  }

  for (const id of POSE_IDS) {
    const point = mapped.get(id)
    const circle = document.createElementNS(SVG_NS, 'circle')
    circle.setAttribute('cx', point.x)
    circle.setAttribute('cy', point.y)
    circle.setAttribute('r', 6)
    poseJoints.appendChild(circle)
  }
  poseSvg.style.visibility = 'visible'
  poseUnavailable.classList.remove('show')
}

// ========================================
// GLTF 캐릭터와 애니메이션
// ========================================
const loader = new GLTFLoader()
const characterFiles = {
  Male01: '/models/Male01.gltf',
  Male02: '/models/Male02.gltf',
  Female01: '/models/Female01.gltf',
  Female02: '/models/Female02.gltf'
}
let character = null
let mixer = null
let currentAction = null
let characterAnimations = []
let poseRig = null
let anatomyConfig=normalizeAnatomyConfig(DEFAULT_ANATOMY_CONFIG)
let anatomyTelemetryAt=0
let characterRequestId = 0
const viewerSettings = {...DEFAULT_VIEWER_SETTINGS}
let selectedPointId = 'p05'
let sitFallbackBase = null
let sitAnimationName = null
let latestSnapshot = null
let customPose = null // 관리자에서 편집 중인 12관절. 실제 Backend 데이터는 그대로 유지합니다.
let activeReplaySnapshot = null
let replayFrames = []
let replayIndex = 0
let replayLastTick = 0
let replayActive = false
let backendLastSeenAt = 0
let backendExpired = false
const poseFilter = new PoseFilter()
let mirrorMode = 'auto'
let lastMirror = false
let cameraView = 'front'
// 본 화면에는 기술 상태를 늘어놓지 않고 LIVE/DEMO/WAITING만 표시한다.
// MAC, RX 배치, 모델 출력 검증은 별도 integration.html에서 확인한다.
const liveBadge = document.querySelector('#viewer-live-state')
let liveConnection = false
function setLiveBadge(value) {
  if (liveBadge) liveBadge.textContent = value
}
function updateLiveBadge(snapshot) {
  if (replayActive) { setLiveBadge('FILE REPLAY'); return }
  if (viewerSettings.locationMode === 'manual' || viewerSettings.jointsMode !== 'live') {
    setLiveBadge(liveConnection ? 'LIVE + TEST' : 'TEST MODE')
    return
  }
  if (!liveConnection) { setLiveBadge('DISCONNECTED'); return }
  const system = snapshot?.system || {}
  if (String(system.reason || '').includes('FAKE MODE')) { setLiveBadge('DEMO DATA'); return }
  setLiveBadge(system.ps_connected && system.pose_connected ? 'LIVE' : 'WAITING')
}

// 실제 FPGA 12관절 입력에 대해 팔과 다리 추종 모두 기본 ON.
// 사용자 설정으로 다리 추종을 끌 수 있고, 로컬 샘플 재생도 동일 리그를 사용한다.
let currentZone = 5
let targetZone = 5
let isMoving = false
const moveSpeed = 1.1 // GLTF Walk와 더 자연스럽게 맞추기 위한 화면 이동 속도
let targetPosture = 'standing'

function playAnimation(name, fadeTime = 0.25) {
  if (!mixer) return
  // ArmPoseIdle이 없다면 모든 GLTF에 있는 기본 서기로 복귀.
  const selectedName = name === 'ArmPoseIdle' && !THREE.AnimationClip.findByName(characterAnimations, name)
    ? 'Idle_Neutral' : name
  const clip = THREE.AnimationClip.findByName(characterAnimations, selectedName)
  if (!clip) {
    console.warn(`Animation not found: ${name}`)
    return
  }
  const nextAction = mixer.clipAction(clip)
  if (nextAction === currentAction) return
  nextAction.reset().fadeIn(fadeTime).play()
  if (currentAction) currentAction.fadeOut(fadeTime)
  currentAction = nextAction
}

// 일반적인 서기·걷기는 Idle_Neutral/Walk가 담당한다.
// 12관절 추종은 유효한 좌표가 있을 때만 mixer 뒤에 회전을 덮어쓴다.
function refreshIdleAnimation() {
  if (!character || isMoving) return
  if (targetPosture === 'sitting' && sitAnimationName) {
    playAnimation(sitAnimationName)
    return
  }
  playAnimation(poseRig?.ready && poseRig.armEnabled ? 'ArmPoseIdle' : 'Idle_Neutral')
}

function disableRig() {
  if (poseRig?.active) poseRig.clear()
  refreshIdleAnimation()
}

function moveCharacterTo(zone, posture = 'standing') {
  if (!character || !zonePositions[zone]) return
  character.visible = true
  targetPosture = posture

  const target = zonePositions[zone]
  const dx = target.x - character.position.x
  const dz = target.z - character.position.z
  const alreadyThere = Math.hypot(dx, dz) < 0.03

  if (alreadyThere) {
    character.position.x = target.x
    character.position.z = target.z
    currentZone = zone
    targetZone = zone
    isMoving = false
    character.rotation.y = 0
    refreshIdleAnimation()
    return
  }

  // 같은 목표가 반복되어도 Walk 애니메이션을 재시작하지 않는다.
  if (isMoving && targetZone === zone) return
  targetZone = zone
  isMoving = true
  if (poseRig?.active) poseRig.clear()
  playAnimation('Walk')
}

// P10은 P05와 같은 좌표에서 앉은 자세를 적용합니다.
// GLTF에 앉기 idle clip이 있으면 우선 사용하고, 없으면 안전한 제한적 본 포즈로 대체합니다.
const sitChair = new THREE.Group()
const sitMat = new THREE.MeshStandardMaterial({color: 0x48565a, roughness: 0.9})
const seat = new THREE.Mesh(new THREE.BoxGeometry(0.7, 0.075, 0.66), sitMat)
seat.position.set(0, 0.47, 0.08)
sitChair.add(seat)
for (const x of [-0.27, 0.27]) {
  for (const z of [-0.15, 0.30]) {
    const leg = new THREE.Mesh(new THREE.BoxGeometry(0.055, 0.45, 0.055), sitMat)
    leg.position.set(x, 0.225, z)
    sitChair.add(leg)
  }
}
const chairBack = new THREE.Mesh(new THREE.BoxGeometry(0.7, 0.53, 0.065), sitMat)
chairBack.position.set(0, 0.77, -0.22)
sitChair.add(chairBack)
sitChair.position.copy(zonePositions[5])
sitChair.visible = false
scene.add(sitChair)

function restoreSittingFallback() {
  if (!sitFallbackBase) return
  const original = sitFallbackBase
  original.body.position.copy(original.bodyPosition)
  for (const item of original.legs) {
    item.upper.quaternion.copy(item.upperRotation)
    item.lower.quaternion.copy(item.lowerRotation)
    item.foot.position.copy(item.footPosition)
  }
  sitFallbackBase = null
  character?.updateMatrixWorld(true)
}
function applySittingFallback() {
  if (!character || !poseRig?.ready) {sitChair.visible = false; return}
  const sitting = character.visible && !isMoving && targetPosture === 'sitting'
  sitChair.visible = sitting
  // Do not run procedural P10 seated fallback and live anatomical squat IK together.
  if (poseRig.legEnabled && poseRig.solution?.squat>0.075) {
    if (sitFallbackBase) restoreSittingFallback()
    return
  }
  if (!sitting || sitAnimationName) {
    if (sitFallbackBase) restoreSittingFallback()
    return
  }
  const body = poseRig.body
  if (!sitFallbackBase) {
    sitFallbackBase = {
      body, bodyPosition: body.position.clone(),
      legs: poseRig.legs.map(leg => ({
        upper: leg.upper, lower: leg.lower, foot: leg.foot,
        upperRotation: leg.upper.quaternion.clone(),
        lowerRotation: leg.lower.quaternion.clone(),
        footPosition: leg.foot.position.clone()
      }))
    }
    if (!poseRig.calibrated) poseRig.calibrate()
  }
  const rest = sitFallbackBase
  const parentScale = body.parent.getWorldScale(new THREE.Vector3())
  body.position.copy(rest.bodyPosition)
  body.position.y -= 0.40 / Math.max(Math.abs(parentScale.y), 0.01)
  const axis = new THREE.Vector3(1, 0, 0)
  for (const leg of rest.legs) {
    leg.upper.quaternion.copy(leg.upperRotation)
      .multiply(new THREE.Quaternion().setFromAxisAngle(axis, -1.10))
    leg.lower.quaternion.copy(leg.lowerRotation)
      .multiply(new THREE.Quaternion().setFromAxisAngle(axis, 1.22))
  }
  character.updateMatrixWorld(true)
  // Foot 본이 다리 본의 자식이 아닌 GLTF에서도 정강이 끝과 신발을 맞춥니다.
  for (let i = 0; i < rest.legs.length; i++) {
    const item = rest.legs[i]
    const leg = poseRig.legs[i]
    if (!leg.shinAxis || leg.length < 0.02) continue
    const tip = item.lower.getWorldPosition(new THREE.Vector3()).add(
      leg.shinAxis.clone().applyQuaternion(item.lower.getWorldQuaternion(new THREE.Quaternion())).normalize().multiplyScalar(leg.length)
    )
    item.foot.parent.updateWorldMatrix(true, false)
    item.foot.position.copy(item.foot.parent.worldToLocal(tip))
  }
  character.updateMatrixWorld(true)
}

function setAbsentState(message, posture) {
  isMoving = false
  targetZone = currentZone
  if (character) character.visible = false
  poseRig?.clear()
  playAnimation('Idle_Neutral')
  clearLocationUI(message)
  updatePostureUI(posture)
}

// 하나의 Pose가 오른쪽 스켈레톤과 3D 관절 모두를 움직입니다.
function updateMotionRig(pose, mirrored) {
  if (!pose?.valid || isMoving) {
    if (poseRig?.active) poseRig.clear()
    refreshIdleAnimation()
    return
  }
  const angles = solvePoseAngles(pose, mirrored)
  // LIVE/TEST 모두 동일 좌표로 관절을 계산합니다. 2D->3D 깊이는 리그가 추정합니다.
  const arms = viewerSettings.liveArms && Boolean(angles) && hasMeaningfulArmPose(pose)
  // When P10 uses the procedural seated fallback, leave its leg rotations
  // untouched unless a real squat pose is being tracked.
  const fallbackSeated=targetPosture==='sitting' && !sitAnimationName &&
    (!angles || angles.squat<=0.075)
  const legs = viewerSettings.liveLegs && !fallbackSeated && Boolean(angles &&
    (angles.activity > 0.14 || Number.isFinite(angles.footSpacingRatio)))
  if (arms || legs) poseRig?.setPose(pose, mirrored, {arms, legs})
  else if (poseRig?.active) poseRig.clear()
  refreshIdleAnimation()
}

function handleSnapshot(snapshot, source = 'backend') {
  if (!snapshot || snapshot.type !== 'snapshot') return
  if (source === 'backend') {
    latestSnapshot = snapshot
    if (replayActive) return
  } else if (source === 'replay') activeReplaySnapshot = snapshot

  // LIVE 관절은 위치 결과와 관계없이 수신합니다. TEST 관절은 화면에만 생성합니다.
  const validPose = sanitizePose(snapshot.pose)
  const livePose = validPose ? poseFilter.push(validPose) : null
  if (!livePose) poseFilter.reset()
  const sharedPose = viewerSettings.jointsMode === 'custom'
    ? customPose
    : selectViewerPose(viewerSettings.jointsMode, livePose, viewerSettings.jointsSample, createTestPose)
  const displayPose = sharedPose
  const motionPose = sharedPose
  const poseMirror = resolvePoseMirror(sharedPose, mirrorMode, lastMirror)
  if (sharedPose?.valid) lastMirror = poseMirror
  renderPose(sharedPose, poseMirror)
  const motionMirror = poseMirror

  const location = resolveViewerLocation(snapshot, viewerSettings)
  // 중앙 고정은 화면의 캐릭터 위치만 바꿉니다. 실제 위치 예측과 Pose는 항상 수신·표시합니다.
  if (viewerSettings.locationMode === 'center') {
    if (location.valid && !location.empty) {
      selectedPointId = location.pointId
      updateLocationUI(location.zone, selectedPointId)
      updatePostureUI(location.posture)
    } else {
      clearLocationUI(location.empty ? 'No person' : 'Unavailable')
      updatePostureUI(location.empty ? 'empty' : 'unknown')
    }
    const showPerson = Boolean(motionPose?.valid || displayPose?.valid || (location.valid && !location.empty))
    if (character) character.visible = showPerson
    if (showPerson) moveCharacterTo(5, location.posture === 'sitting' ? 'sitting' : 'standing')
    updateMotionRig(motionPose, motionMirror)
    updateLiveBadge(snapshot)
    return
  }
  if (location.empty) {
    if (viewerSettings.jointsMode !== 'live' && sharedPose?.valid) {
      clearLocationUI('No person')
      updatePostureUI('unknown')
      if (character) character.visible = true
      moveCharacterTo(5)
      updateMotionRig(sharedPose, poseMirror)
    } else setAbsentState('No person', 'empty')
    updateLiveBadge(snapshot)
    return
  }
  if (location.valid) {
    selectedPointId = location.pointId
    updateLocationUI(location.zone, selectedPointId)
    updatePostureUI(location.posture)
    if (character) character.visible = true
    moveCharacterTo(location.zone, location.posture)
  } else {
    clearLocationUI('Unavailable')
    updatePostureUI('unknown')
    if (character) character.visible = Boolean(sharedPose)
    if (sharedPose?.valid) moveCharacterTo(5)
  }
  updateMotionRig(sharedPose, poseMirror)
  updateLiveBadge(snapshot)
}

function loadCharacter(name) {
  const file = characterFiles[name]
  if (!file) return
  const requestId = ++characterRequestId
  isMoving = false

  if (mixer) mixer.stopAllAction()
  restoreSittingFallback()
  sitChair.visible = false
  poseRig = null
  mixer = null
  currentAction = null
  characterAnimations = []
  sitFallbackBase = null
  sitAnimationName = null
  if (character) scene.remove(character)
  character = null

  loader.load(file, (gltf) => {
    // 다른 캐릭터를 먼저 클릭한 경우 늦게 도착한 이전 모델은 무시.
    if (requestId !== characterRequestId) return
    character = gltf.scene

    const originalBox = new THREE.Box3().setFromObject(character)
    const size = new THREE.Vector3()
    originalBox.getSize(size)
    if (size.y <= 0) {
      console.error(`Invalid character height: ${name}`)
      return
    }
    character.scale.setScalar(1.9 / size.y)
    const scaledBox = new THREE.Box3().setFromObject(character)
    character.position.y = -scaledBox.min.y + 0.04
    const startPosition = zonePositions[currentZone]
    character.position.x = startPosition.x
    character.position.z = startPosition.z
    character.rotation.y = 0
    character.traverse((object) => {
      if (object.isMesh) {
        object.castShadow = true
        object.receiveShadow = true
      }
    })
    scene.add(character)
    poseRig = new PoseRigController(character)
    poseRig.setConfig(anatomyConfig)
    mixer = new THREE.AnimationMixer(character)
    // 서기/걷기를 기본으로 유지하고 추종 중에만 Bone rotation을 프레임 끝에 덮어쓴다.
    const idleClip = THREE.AnimationClip.findByName(gltf.animations, 'Idle_Neutral')
    if (idleClip) {
      const armBone = /(?:^|[./|])(?:UpperArm|LowerArm)[._][LR](?:\.|$)/i
      const armFreeTracks = idleClip.tracks.filter((track) => !armBone.test(track.name))
      const armIdleClip = new THREE.AnimationClip('ArmPoseIdle', idleClip.duration, armFreeTracks)
      characterAnimations = [...gltf.animations, armIdleClip]
      console.log(`[PoseRig] ArmPoseIdle: excluded ${idleClip.tracks.length - armFreeTracks.length} arm tracks; legs and feet remain animated`)
    } else {
      characterAnimations = gltf.animations
    }
    sitAnimationName = characterAnimations
      .filter(a => /sit|seated|chair/i.test(a.name) && !/sit.?down|stand.?up|get.?up|transition/i.test(a.name))
      .sort((a,b)=>Number(/idle|loop/i.test(b.name))-Number(/idle|loop/i.test(a.name)))[0]?.name ?? null
    playAnimation('Idle_Neutral')
    console.log(`${name} loaded; sitting clip: ${sitAnimationName ?? 'procedural fallback'}`)

    if (replayActive && activeReplaySnapshot) handleSnapshot(activeReplaySnapshot, 'replay')
    else if (latestSnapshot) handleSnapshot(latestSnapshot)
    else refreshViewer()
  }, undefined, (error) => console.error(`${name} load error`, error))
}

const characterButtons = document.querySelectorAll('.character-button')
characterButtons.forEach((button) => {
  button.addEventListener('click', () => {
    characterButtons.forEach((item) => item.classList.remove('active'))
    button.classList.add('active')
    loadCharacter(button.dataset.character)
  })
})
loadCharacter('Male01')

// 화면 테스트 설정: Backend/FPGA 동작을 바꾸지 않고 표시할 소스만 전환합니다.
const settingsOpen = document.querySelector('#viewer-settings-open')
const settingsChannel = new BroadcastChannel('wisensing-viewer-settings-v1')
let settingsPopup = null
function refreshViewer() {
  const snapshot = replayActive ? activeReplaySnapshot : latestSnapshot
  if (snapshot) handleSnapshot(snapshot, replayActive ? 'replay' : 'settings')
  else handleSnapshot({type:'snapshot',version:1,pose:null,location:{valid:false}}, 'settings')
}
function broadcastSettings() {
  settingsChannel.postMessage({type:'state', settings:{...viewerSettings}, cameraView, mirrorMode})
  settingsChannel.postMessage({type:'anatomy-state', config:{...anatomyConfig}})
}
function updateCameraView() {
  camera.position.set(cameraView === 'side' ? 4.6 : 0, cameraView === 'side' ? 3.2 : 3.4, cameraView === 'side' ? 5.5 : 7)
  camera.lookAt(0, 1.05, 0)
}
function updateViewerSettings(key, value) {
  const allowed = {
    locationMode: ['live','manual','center'],
    manualPoint: ['p01','p02','p03','p04','p05','p06','p07','p08','p09','p10'],
    jointsMode: ['live','sample','custom','off'], jointsSample: ['stand','armUp','armsWide','squat','legLift'],
    motionMode: ['live','sample','off'], motionSample: ['stand','armUp','armsWide','squat','legLift']
  }
  if (Object.hasOwn(allowed,key) && allowed[key].includes(value)) viewerSettings[key] = value
  else if (key === 'liveArms' || key === 'liveLegs') {
    if (typeof value !== 'boolean') return
    viewerSettings[key] = value
  } else if (key === 'cameraView' && ['front','side'].includes(value)) {
    cameraView = value
    updateCameraView()
  } else if (key === 'mirrorMode' && MIRROR_MODES.includes(value)) mirrorMode = value
  else return
  poseFilter.reset()
  poseRig?.clear()
  refreshViewer()
  syncLocationViewSwitch()
  broadcastSettings()
}
function syncLocationViewSwitch() {
  const center = viewerSettings.locationMode === 'center'
  for (const [id, selected] of [['mode-follow', !center], ['mode-center', center]]) {
    const button = document.getElementById(id)
    button.classList.toggle('selected', selected)
    button.setAttribute('aria-pressed', String(selected))
  }
}
document.getElementById('mode-follow').addEventListener('click', () => updateViewerSettings('locationMode','live'))
document.getElementById('mode-center').addEventListener('click', () => updateViewerSettings('locationMode','center'))
syncLocationViewSwitch()
settingsOpen.addEventListener('click', () => {
  settingsPopup = window.open('/integration.html', 'wisensing-admin', 'popup=yes,width=1300,height=950,resizable=yes,scrollbars=yes')
  if (settingsPopup) {
    settingsPopup.focus()
    broadcastSettings()
  } else window.location.href = '/integration.html'
})
settingsChannel.addEventListener('message', event => {
  const msg = event.data
  if (!msg || typeof msg !== 'object') return
  if (msg.type === 'hello') { broadcastSettings(); return }
  if (msg.type === 'anatomy-set') {
    anatomyConfig=normalizeAnatomyConfig({...anatomyConfig,...msg.values})
    poseRig?.setConfig(anatomyConfig)
    settingsChannel.postMessage({type:'anatomy-state',config:{...anatomyConfig}})
    return
  }
  if (msg.type === 'custom-pose') {
    const nextPose = sanitizePose(msg.pose)
    if (!nextPose) return
    customPose = {...nextPose, coordinate_space:'fake_normalized', test_pose:'custom'}
    if (viewerSettings.jointsMode === 'custom') refreshViewer()
    return
  }
  if (msg.type === 'update') { updateViewerSettings(msg.key, msg.value); return }
  if (msg.type === 'all-live') {
    viewerSettings.locationMode = 'live'
    viewerSettings.jointsMode = 'live'
    viewerSettings.motionMode = 'live'
    syncLocationViewSwitch()
  } else if (msg.type === 'reset') {
    Object.assign(viewerSettings, DEFAULT_VIEWER_SETTINGS)
    syncLocationViewSwitch()
    cameraView = 'front'
    mirrorMode = 'auto'
    updateCameraView()
  } else return
  poseFilter.reset()
  poseRig?.clear()
  refreshViewer()
  broadcastSettings()
})
window.addEventListener('beforeunload', () => {
  if (settingsPopup && !settingsPopup.closed) settingsPopup.close()
  settingsChannel.close()
})
// O=기록 재생, B=실시간 복귀, M=좌우 모드 순환.
window.addEventListener('keydown', (event) => {
  if (event.altKey || event.ctrlKey || event.metaKey) return
  if (event.target instanceof HTMLElement && /^(INPUT|TEXTAREA|SELECT|BUTTON)$/.test(event.target.tagName)) return
  const key = event.key.toLowerCase()
  if (key === 'o' && !replayActive) document.querySelector('#pose-replay-file').click()
  if (key === 'b' && replayActive) stopPoseReplay()
  if (key === 'm') {
    updateViewerSettings('mirrorMode', MIRROR_MODES[(MIRROR_MODES.indexOf(mirrorMode) + 1) % MIRROR_MODES.length])
    console.log('[WiSensing] X axis mode:',mirrorMode)
  }
})

// O: 내 PC에 저장된 실제 backend snapshot JSON/JSONL/24xINT8 파일을 재생.
// 파일은 브라우저 안에서만 읽는다. 서버에 업로드하지 않는다.
const replayFileInput = document.querySelector('#pose-replay-file')
const replayLabel = document.querySelector('#pose-replay-label')

function stopPoseReplay() {
  replayActive = false
  updateLiveBadge(latestSnapshot)
  replayFrames = []
  replayIndex = 0
  activeReplaySnapshot = null
  replayLabel.hidden = true
  replayFileInput.value = ''
  poseFilter.reset()
  poseRig?.clear()
  console.log('[Pose Replay] Backend LIVE mode restored')
  if (latestSnapshot && performance.now() - backendLastSeenAt < 5000) {
    handleSnapshot(latestSnapshot, 'backend')
  } else {
    refreshViewer()
  }
}

replayFileInput.addEventListener('change', async () => {
  const file = replayFileInput.files?.[0]
  if (!file) return
  try {
    const frames = parsePoseRecording(await file.text())
    if (frames.length === 0) throw new Error('유효한 12관절 프레임이 없습니다.')
    replayFrames = frames
    replayIndex = 0
    replayLastTick = performance.now()
    replayActive = true
    setLiveBadge('FILE REPLAY')
    activeReplaySnapshot = null
    backendExpired = false
    poseFilter.reset()
    poseRig?.clear()
    replayLabel.hidden = false
    replayLabel.textContent = `LOCAL REPLAY · ${frames.length} frame(s) · B: LIVE 복귀`
    console.log(`[Pose Replay] ${file.name}: ${frames.length} frames loaded (LOCAL FILE)`)
    handleSnapshot(frames[0], 'replay')
  } catch (error) {
    console.error('[Pose Replay] file error:', error)
    window.alert(`Pose 파일 재생 실패: ${error.message}`)
    replayFileInput.value = ''
  }
})

connectBackend((snapshot) => {
  backendLastSeenAt = performance.now()
  backendExpired = false
  if (replayActive) {
    latestSnapshot = snapshot
    return
  }
  handleSnapshot(snapshot, 'backend')
}, (connected) => {
  liveConnection = connected
  if (!connected && !replayActive) {
    setLiveBadge('DISCONNECTED')
    backendLastSeenAt = 0
    backendExpired = true
    poseFilter.reset()
    poseRig?.clear()
    latestSnapshot = null
    refreshViewer()
  } else {
    updateLiveBadge(latestSnapshot)
  }
})
console.log('[WiSensing] 관리자 통합 관절 테스트 / 동일 Pose가 2D와 3D를 동시 제어합니다; O=JSON 재생, B=복귀')

// ========================================
// 화면 크기 및 매 프레임 이동
// ========================================
function resizeRenderer() {
  const width = Math.max(1, container.clientWidth)
  const height = Math.max(1, container.clientHeight)
  renderer.setSize(width, height, false)
  camera.aspect = width / height
  // Room orbit camera baseline: preserve 9-zone framing when resizing.
  const narrow = camera.aspect < 1.35
  const baseEye = narrow ? new THREE.Vector3(0, 3.70, 8.35) : new THREE.Vector3(0, 3.40, 7.50)
  const baseTarget = narrow ? new THREE.Vector3(0, 1.08, -0.44) : new THREE.Vector3(0, 1.05, -0.16)
  roomCameraControls.setBaseView(baseEye, baseTarget)
  camera.updateProjectionMatrix()
}
window.addEventListener('resize', resizeRenderer)
resizeRenderer()

// WebGL 루프는 반드시 마지막에 호출해야 화면이 표시된다.
let lastFrame = performance.now()
function animate(now) {
  requestAnimationFrame(animate)
  const delta = Math.min((now - lastFrame) / 1000, 0.05)
  lastFrame = now
  // Restore last frame's additive pelvis IK offset BEFORE advancing animation.
  poseRig?.prepareFrame()
  if (mixer) mixer.update(delta)

  // 파일 재생은 시간 흐름에 따라 원본 snapshot/pose를 그대로 입력 파이프라인으로 보낸다.
  if (replayActive && replayFrames.length && now - replayLastTick >= 250) {
    replayLastTick = now
    replayIndex = (replayIndex + 1) % replayFrames.length
    handleSnapshot(replayFrames[replayIndex], 'replay')
  }

  // Backend가 끊기면 마지막 Pose가 계속 실시간인 것처럼 보이지 않도록 비활성화.
  if (!replayActive && backendLastSeenAt &&
      now - backendLastSeenAt > 5000 && !backendExpired) {
    backendExpired = true
    poseFilter.reset()
    poseRig?.clear()
    latestSnapshot = null
    refreshViewer()
    console.warn('[WiSensing] Backend snapshot timeout; live inputs discarded')
  }

  // 관리자가 편집한 12관절은 WS 패킷이 없어도 리그에 계속 적용합니다.
  if (!replayActive && viewerSettings.jointsMode === 'custom' && customPose?.valid) {
    updateMotionRig(customPose, resolvePoseMirror(customPose, mirrorMode, lastMirror))
  } else if (!replayActive && viewerSettings.jointsMode === 'sample') {
    const pose = createTestPose(viewerSettings.jointsSample)
    updateMotionRig(pose, resolvePoseMirror(pose, mirrorMode, lastMirror))
  }

  if (character && isMoving) {
    const target = zonePositions[targetZone]
    const dx = target.x - character.position.x
    const dz = target.z - character.position.z
    const distance = Math.hypot(dx, dz)
    const step = moveSpeed * delta

    if (distance <= Math.max(0.03, step)) {
      character.position.x = target.x
      character.position.z = target.z
      currentZone = targetZone
      isMoving = false
      character.rotation.y = 0
      // Sit 애니메이션은 아직 없으므로 기본 서기 애니메이션을 유지.
      refreshIdleAnimation()
      updateLocationUI(currentZone, selectedPointId)
      updatePostureUI(targetPosture)
    } else {
      const vx = dx / distance
      const vz = dz / distance
      character.position.x += vx * step
      character.position.z += vz * step
      // 모델의 정면(+Z) 기준으로 이동 방향 바라보기.
      character.rotation.y = Math.atan2(vx, vz)
    }
  }
  // Idle/Walk 이후 한 번만 동일 좌표의 팔·다리 방향을 적용한다.
  // 안전 범위를 벗어난 발 이동은 해당 다리의 IK를 적용하지 않는다.
  const rigWasActive = Boolean(poseRig?.active)
  applySittingFallback()
  poseRig?.update(delta, Boolean(character?.visible) && !isMoving)
  if (now-anatomyTelemetryAt>400) {
    anatomyTelemetryAt=now
    if (poseRig?.ready) settingsChannel.postMessage({type:'anatomy-telemetry',
      values:poseRig.diagnostics()})
  }
  if (rigWasActive && !poseRig?.active) refreshIdleAnimation()


  roomCameraControls.update(delta)
  renderer.render(scene, camera)
}
requestAnimationFrame(animate)
