import './style.css'
import * as THREE from 'three'
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js'
import { connectBackend } from './websocket.js'
import { PoseRigController } from './poseRig.js'
import { solvePoseAngles } from './poseAngles.js'
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
        <button id="viewer-settings-open" class="settings-trigger" type="button" aria-controls="viewer-settings-panel" aria-expanded="false">⚙ 설정 · 테스트</button>
      </div>
    </header>

    <aside class="viewer-settings-panel" id="viewer-settings-panel" aria-label="시연 및 테스트 설정" hidden>
      <div class="settings-header"><div><strong>시연 · 테스트 설정</strong><p>위치, 관절, 3D 모션을 서로 독립적으로 선택합니다.</p></div><button id="viewer-settings-close" type="button" aria-label="설정 닫기">닫기 ✕</button></div>
      <div class="settings-section">
        <label for="settings-location-mode">① 위치 입력</label>
        <select id="settings-location-mode"><option value="live">실제 위치추적 (LIVE)</option><option value="manual">수동 위치 (TEST)</option></select>
        <div id="settings-manual-fields" hidden>
          <div class="settings-zone-grid" role="group" aria-label="수동 위치 선택">
            <button type="button" data-manual-point="p01">P01</button>
            <button type="button" data-manual-point="p02">P02</button>
            <button type="button" data-manual-point="p03">P03</button>
            <button type="button" data-manual-point="p04">P04</button>
            <button type="button" data-manual-point="p05">P05</button>
            <button type="button" data-manual-point="p06">P06</button>
            <button type="button" data-manual-point="p07">P07</button>
            <button type="button" data-manual-point="p08">P08</button>
            <button type="button" data-manual-point="p09">P09</button>
            <button type="button" data-manual-point="p10" class="settings-p10">P10 · 앉기</button>
          </div>
          <p class="settings-help">P05와 P10 모두 중앙 Zone 5입니다. P10은 앉은 자세로 표시합니다.</p>
        </div>
      </div>
      <div class="settings-section">
        <label for="settings-joints-mode">② 오른쪽 12관절 그림</label>
        <select id="settings-joints-mode"><option value="live">실제 FPGA 관절 (LIVE)</option><option value="sample">샘플 관절 (TEST)</option><option value="off">숨김</option></select>
        <div id="settings-joints-sample-field" hidden><label for="settings-joints-sample">샘플 관절 자세</label><select id="settings-joints-sample"><option value="stand">기본 서기</option><option value="armUp">한 팔 올리기</option><option value="armsWide">양팔 벌리기</option><option value="squat">스쿼트</option><option value="legLift">다리 들기</option></select></div>
      </div>
      <div class="settings-section">
        <label for="settings-motion-mode">③ 3D 캐릭터 모션</label>
        <select id="settings-motion-mode"><option value="live">실제 FPGA 관절 추종 (LIVE)</option><option value="sample">샘플 모션 (TEST)</option><option value="off">기본 서기/앉기 자세</option></select>
        <div id="settings-motion-sample-field" hidden><label for="settings-motion-sample">샘플 모션 자세</label><select id="settings-motion-sample"><option value="stand">기본 서기</option><option value="armUp">한 팔 올리기</option><option value="armsWide">양팔 벌리기</option><option value="squat">스쿼트</option><option value="legLift">다리 들기</option></select></div>
        <div id="settings-motion-live-options" class="settings-checks">
          <label><input id="settings-live-arms" type="checkbox" checked> 실제 팔 추종</label>
          <label><input id="settings-live-legs" type="checkbox"> 실제 다리 추종 (실험적)</label>
        </div>
      </div>
      <p id="viewer-settings-summary" class="settings-summary" aria-live="polite"></p>
      <div class="settings-actions"><button id="settings-all-live" type="button">전체 LIVE</button><button id="settings-reset" type="button">설정 초기화</button></div>
      <p class="settings-help">TEST 값은 화면에만 반영합니다. Zybo·Backend 추론 결과는 바꾸지 않습니다.</p>
    </aside>

    <main class="dashboard">
      <section class="scene-card">
        <div class="scene-title">
          <span>SPACE VIEW</span>
          <strong>Zone 5</strong>
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

// ========================================
// Three.js: 카메라, 방, 조명
// ========================================
const container = document.querySelector('#scene-container')
const scene = new THREE.Scene()
scene.background = new THREE.Color(0x12161b)
scene.fog = new THREE.Fog(0x12161b, 9, 18)

const camera = new THREE.PerspectiveCamera(40, 1, 0.1, 100)
camera.position.set(0, 3.4, 7)
camera.lookAt(0, 1.05, 0)

const renderer = new THREE.WebGLRenderer({ antialias: true })
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2))
renderer.shadowMap.enabled = true
renderer.outputColorSpace = THREE.SRGBColorSpace
renderer.toneMapping = THREE.ACESFilmicToneMapping
renderer.toneMappingExposure = 1.1
container.appendChild(renderer.domElement)

const hemiLight = new THREE.HemisphereLight(0xffead8, 0x182333, 1.8)
scene.add(hemiLight)
const mainLight = new THREE.DirectionalLight(0xffffff, 2.8)
mainLight.position.set(4, 8, 5)
mainLight.castShadow = true
scene.add(mainLight)
const warmLight = new THREE.PointLight(0xffc58e, 25, 12)
warmLight.position.set(-3, 3.5, 1)
scene.add(warmLight)
const cyanLight = new THREE.PointLight(0x00e8ff, 14, 8)
cyanLight.position.set(0, 1, 0)
scene.add(cyanLight)

const floor = new THREE.Mesh(
  new THREE.PlaneGeometry(9, 8),
  new THREE.MeshStandardMaterial({ color: 0x4f4843, roughness: 0.92 })
)
floor.rotation.x = -Math.PI / 2
floor.receiveShadow = true
scene.add(floor)

const backWall = new THREE.Mesh(
  new THREE.PlaneGeometry(9, 4.5),
  new THREE.MeshStandardMaterial({ color: 0x312f30, roughness: 0.95 })
)
backWall.position.set(0, 2.25, -4)
backWall.receiveShadow = true
scene.add(backWall)

const sideWall = new THREE.Mesh(
  new THREE.PlaneGeometry(8, 4.5),
  new THREE.MeshStandardMaterial({ color: 0x292a2d, roughness: 0.95, side: THREE.DoubleSide })
)
sideWall.rotation.y = Math.PI / 2
sideWall.position.set(-4.5, 2.25, 0)
scene.add(sideWall)

const sofaMaterial = new THREE.MeshStandardMaterial({ color: 0x514b48, roughness: 0.85 })
const sofaSeat = new THREE.Mesh(new THREE.BoxGeometry(2.4, 0.45, 0.85), sofaMaterial)
sofaSeat.position.set(-2.4, 0.38, -3.15)
sofaSeat.castShadow = true
scene.add(sofaSeat)
const sofaBack = new THREE.Mesh(new THREE.BoxGeometry(2.4, 0.9, 0.3), sofaMaterial)
sofaBack.position.set(-2.4, 0.9, -3.5)
sofaBack.castShadow = true
scene.add(sofaBack)

// ========================================
// P01 ~ P09 바닥 그리드
// ========================================
const GRID_SPACING = 1.45
const zoneObjects = {}
const zonePositions = {}

function makeZoneLabel(text) {
  const canvas = document.createElement('canvas')
  canvas.width = 256
  canvas.height = 128
  const ctx = canvas.getContext('2d')
  ctx.font = '600 40px Arial'
  ctx.textAlign = 'center'
  ctx.textBaseline = 'middle'
  ctx.fillStyle = '#ffffff'
  ctx.fillText(text, 128, 64)
  const texture = new THREE.CanvasTexture(canvas)
  const sprite = new THREE.Sprite(new THREE.SpriteMaterial({
    map: texture, transparent: true, depthWrite: false
  }))
  sprite.scale.set(0.7, 0.35, 1)
  return sprite
}

function createZone(x, z, number) {
  const selected = number === 5
  const group = new THREE.Group()
  const zoneSize = 1.3
  const thickness = 0.035
  const material = new THREE.MeshStandardMaterial({
    color: selected ? 0x55f6ff : 0x3a8590,
    emissive: selected ? 0x00d9e8 : 0x103b43,
    emissiveIntensity: selected ? 3 : 0.8
  })
  const edgeX = new THREE.BoxGeometry(zoneSize, 0.025, thickness)
  const edgeZ = new THREE.BoxGeometry(thickness, 0.025, zoneSize)

  for (const side of [-1, 1]) {
    const horizontal = new THREE.Mesh(edgeX, material)
    horizontal.position.z = side * zoneSize / 2
    group.add(horizontal)
    const vertical = new THREE.Mesh(edgeZ, material)
    vertical.position.x = side * zoneSize / 2
    group.add(vertical)
  }

  const fill = new THREE.Mesh(
    new THREE.PlaneGeometry(1.22, 1.22),
    new THREE.MeshBasicMaterial({
      color: 0x00eaf5,
      transparent: true,
      opacity: selected ? 0.12 : 0,
      side: THREE.DoubleSide,
      depthWrite: false
    })
  )
  fill.rotation.x = -Math.PI / 2
  fill.position.y = 0.015
  group.add(fill)
  group.position.set(x, 0.035, z)
  scene.add(group)

  const label = makeZoneLabel(`P${String(number).padStart(2, '0')}`)
  label.position.set(x, 0.18, z)
  label.material.color.setHex(selected ? 0xffffff : 0x83cbd1)
  scene.add(label)
  zoneObjects[number] = { material, fill, label }
  zonePositions[number] = new THREE.Vector3(x, 0, z)
}

for (let row = 0; row < 3; row++) {
  for (let col = 0; col < 3; col++) {
    const number = row * 3 + col + 1
    createZone((col - 1) * GRID_SPACING, (row - 1) * GRID_SPACING, number)
  }
}

function updateZoneHighlight(zone) {
  for (let i = 1; i <= 9; i++) {
    const item = zoneObjects[i]
    const selected = i === zone
    item.material.color.setHex(selected ? 0x55f6ff : 0x3a8590)
    item.material.emissive.setHex(selected ? 0x00d9e8 : 0x103b43)
    item.material.emissiveIntensity = selected ? 3 : 0.8
    item.fill.material.opacity = selected ? 0.12 : 0
    item.label.material.color.setHex(selected ? 0xffffff : 0x83cbd1)
  }
}

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
let characterRequestId = 0
const viewerSettings = {...DEFAULT_VIEWER_SETTINGS}
let selectedPointId = 'p05'
let sitFallbackBase = null
let sitAnimationName = null
let latestSnapshot = null
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
// 본 화면에는 기술 상태를 늘어놓지 않고 LIVE/DEMO/WAITING만 표시한다.
// MAC, RX 배치, 모델 출력 검증은 별도 integration.html에서 확인한다.
const liveBadge = document.querySelector('#viewer-live-state')
let liveConnection = false
function setLiveBadge(value) {
  if (liveBadge) liveBadge.textContent = value
}
function updateLiveBadge(snapshot) {
  if (replayActive) { setLiveBadge('FILE REPLAY'); return }
  if (viewerSettings.locationMode !== 'live' || viewerSettings.jointsMode !== 'live' || viewerSettings.motionMode !== 'live') {
    setLiveBadge(liveConnection ? 'LIVE + TEST' : 'TEST MODE')
    return
  }
  if (!liveConnection) { setLiveBadge('DISCONNECTED'); return }
  const system = snapshot?.system || {}
  if (String(system.reason || '').includes('FAKE MODE')) { setLiveBadge('DEMO DATA'); return }
  setLiveBadge(system.ps_connected && system.pose_connected ? 'LIVE' : 'WAITING')
}

// 팔은 기본 ON, 다리는 안전을 위해 실제 Backend에서 L 키를 눌러야 ON.
// 로컬 샘플 재생은 관절 각도 확인을 위해 다리도 자동 적용한다.
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

// 좌표계가 y-아래 방향이라고 가정하는 보수적 '팔 들기/벌리기' 감지.
// 무조건 서기 자세까지 강제로 뼈에 적용하지 않도록 방어한다.
function hasMeaningfulArmPose(pose) {
  if (!pose?.valid || !Array.isArray(pose.joints)) return false
  const points = new Map(pose.joints.map((joint) => [Number(joint.id), joint]))
  for (const [shoulderId, wristId, hipId] of [[11, 15, 23], [12, 16, 24]]) {
    const shoulder = points.get(shoulderId)
    const wrist = points.get(wristId)
    const hip = points.get(hipId)
    if (!shoulder || !wrist || !hip) continue
    const vals = [shoulder.x, shoulder.y, wrist.x, wrist.y, hip.y].map(Number)
    if (!vals.every(Number.isFinite)) continue
    const torso = Math.abs(Number(hip.y) - Number(shoulder.y))
    if (torso < 1e-5) continue
    const dx = Math.abs(Number(wrist.x) - Number(shoulder.x)) / torso
    const dy = (Number(wrist.y) - Number(shoulder.y)) / torso
    // 손목이 어깨보다 높거나, 손목이 어깨 높이 근처에서 바깥으로 뻗은 경우.
    if (dy < -0.12 || (dx > 0.58 && Math.abs(dy) < 0.66)) return true
  }
  return false
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

function setAbsentState(message, posture) {
  isMoving = false
  targetZone = currentZone
  if (character) character.visible = false
  poseRig?.clear()
  playAnimation('Idle_Neutral')
  clearLocationUI(message)
  updatePostureUI(posture)
}

// 관절 입력과 캐릭터 위치·모션은 화면에서만 독립적으로 선택합니다.
function updateMotionRig(pose, mirrored) {
  if (!pose?.valid || viewerSettings.motionMode === 'off' || isMoving) {
    if (poseRig?.active) poseRig.clear()
    refreshIdleAnimation()
    return
  }
  const sample = viewerSettings.motionMode === 'sample'
  const angles = solvePoseAngles(pose, mirrored)
  const arms = sample
    ? ['armUp', 'armsWide'].includes(viewerSettings.motionSample)
    : viewerSettings.liveArms && pose.coordinate_space === 'model_output' && hasMeaningfulArmPose(pose)
  const legs = sample
    ? ['squat', 'legLift'].includes(viewerSettings.motionSample)
    : viewerSettings.liveLegs && pose.coordinate_space === 'model_output' && Boolean(angles && angles.activity > 0.14)
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
  const displayPose = selectViewerPose(viewerSettings.jointsMode, livePose, viewerSettings.jointsSample, createTestPose)
  const motionPose = selectViewerPose(viewerSettings.motionMode, livePose, viewerSettings.motionSample, createTestPose)
  const displayMirror = resolvePoseMirror(displayPose, mirrorMode, lastMirror)
  const motionMirror = resolvePoseMirror(motionPose, mirrorMode, lastMirror)
  if (motionPose?.valid) lastMirror = motionMirror
  else if (displayPose?.valid) lastMirror = displayMirror
  renderPose(displayPose, displayMirror)

  const location = resolveViewerLocation(snapshot, viewerSettings)
  if (location.empty) {
    setAbsentState('No person', 'empty')
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
    if (character) character.visible = Boolean(displayPose || motionPose)
  }
  updateMotionRig(motionPose, motionMirror)
  updateLiveBadge(snapshot)
}

function loadCharacter(name) {
  const file = characterFiles[name]
  if (!file) return
  const requestId = ++characterRequestId
  isMoving = false

  if (mixer) mixer.stopAllAction()
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

const poseTestBar = document.querySelector('#pose-test-bar')
const poseTestButtons = [...document.querySelectorAll('[data-pose-test]')]
const poseTestNote = document.querySelector('#pose-test-note')
const sideViewButton = document.querySelector('#demo-side-view')
const legToggleButton = document.querySelector('#demo-leg-toggle')

function refreshLegControls() {
  legToggleButton.textContent = experimentalLegs ? 'K · 다리 각도 ON' : 'K · 다리 각도 OFF'
  legToggleButton.classList.toggle('active', experimentalLegs)
  legToggleButton.setAttribute('aria-pressed', String(experimentalLegs))
  poseTestButtons.forEach((button) => {
    if (button.dataset.poseTest === 'squat' || button.dataset.poseTest === 'legLift') {
      button.disabled = !experimentalLegs
      button.title = experimentalLegs ? '같은 12관절의 고관절/무릎 각도로 움직입니다 (깊이 추정)' : 'K를 눌러 다리 각도 추종을 켜세요'
    }
  })
}

function toggleLegAngles() {
  experimentalLegs = !experimentalLegs
  if (!experimentalLegs && (demoPoseName === 'squat' || demoPoseName === 'legLift')) {
    selectPoseTest('stand')
  }
  refreshLegControls()
  if (rigDemoMode) {
    poseTestNote.textContent = experimentalLegs
      ? '다리 각도 ON: Pose Result와 동일한 12관절로 고관절/무릎 각도를 계산합니다. 안전 범위를 넘으면 Idle로 되돌립니다.'
      : TEST_POSES[demoPoseName].hint
  }
  console.log(`[PoseRig v13] 2D angle leg tracking: ${experimentalLegs ? 'ON' : 'OFF'}`)
}
legToggleButton.addEventListener('click', toggleLegAngles)
refreshLegControls()

// V는 테스트 전용 카메라 확인: 최종 UI 카메라는 변경하지 않는다.
function updateDemoView() {
  const active = rigDemoMode && demoSideView
  camera.position.set(active ? 4.6 : 0, active ? 3.2 : 3.4, active ? 5.5 : 7)
  camera.lookAt(0, 1.05, 0)
  sideViewButton.classList.toggle('active', active)
  sideViewButton.setAttribute('aria-pressed', String(active))
}
sideViewButton.addEventListener('click', () => {
  if (!rigDemoMode) return
  demoSideView = !demoSideView
  updateDemoView()
})

function selectPoseTest(name) {
  if (!TEST_POSES[name] || (!experimentalLegs && (name === 'squat' || name === 'legLift'))) return
  demoPoseName = name
  poseTestButtons.forEach((button) => {
    button.classList.toggle('active', button.dataset.poseTest === name)
  })
  poseTestNote.textContent = TEST_POSES[name].hint
  demoLastRenderAt = 0
  // 버튼만 눌러도 테스트 모드 진입.
  if (!rigDemoMode) setPoseTestMode(true)
  poseRig?.clear()
  refreshIdleAnimation()
  console.log(`[PoseRig] Test pose: ${TEST_POSES[name].label}`)
}

function setPoseTestMode(enabled) {
  rigDemoMode = enabled
  if (enabled) setLiveBadge('TEST MODE')
  else if (replayActive) setLiveBadge('FILE REPLAY')
  else updateLiveBadge(latestSnapshot)
  poseTestBar.hidden = !enabled
  if (!enabled) demoSideView = false
  updateDemoView()
  poseRig?.clear()
  console.log(`[PoseRig] Test mode ${enabled ? 'ON' : 'OFF'}`)
  if (enabled) {
    poseFilter.reset()
    isMoving = false
    currentZone = targetZone = 5
    if (character) {
      character.visible = true
      character.position.x = zonePositions[5].x
      character.position.z = zonePositions[5].z
      character.rotation.y = 0
      playAnimation('Idle_Neutral')
    }
    updateLocationUI(5)
    updatePostureUI('standing')
    poseTestNote.textContent = TEST_POSES[demoPoseName].hint
    demoLastRenderAt = 0
  } else {
    renderPose(null)
    if (replayActive && activeReplaySnapshot) handleSnapshot(activeReplaySnapshot, 'replay')
    else if (latestSnapshot) handleSnapshot(latestSnapshot)
    else disableRig()
    refreshIdleAnimation()
  }
}

poseTestButtons.forEach((button) => {
  button.addEventListener('click', () => selectPoseTest(button.dataset.poseTest))
})

// 키보드 1~9=위치 이동. T=테스트, S=기본 서기, P=실제 팔, L=실제 다리 추종 토글.

window.addEventListener('keydown', (event) => {
  if (event.altKey || event.ctrlKey || event.metaKey) return
  if (event.target instanceof HTMLElement && /^(INPUT|TEXTAREA|SELECT)$/.test(event.target.tagName)) return

  if (event.key.toLowerCase() === 't') {
    setPoseTestMode(!rigDemoMode)
    return
  }

  const keyToPose = { s: 'stand', q: 'armUp', w: 'armsWide', e: 'squat', r: 'legLift' }
  const testName = keyToPose[event.key.toLowerCase()]
  if (testName && rigDemoMode) {
    selectPoseTest(testName)
    return
  }

  if (event.key.toLowerCase() === 'k' && rigDemoMode) {
    toggleLegAngles()
    return
  }

  // V: 테스트 중에만 대각선 측면 확인(스쿼트 깊이 확인용).
  if (event.key.toLowerCase() === 'v' && rigDemoMode) {
    demoSideView = !demoSideView
    updateDemoView()
    return
  }

  // P/L: 실제 CNN 팔/다리 각도 추종을 각각 토글. Walk 중에는 자동 중지.
  if (event.key.toLowerCase() === 'o' && !rigDemoMode) {
    document.querySelector('#pose-replay-file').click()
    return
  }
  if (event.key.toLowerCase() === 'b' && !rigDemoMode && replayActive) {
    stopPoseReplay()
    return
  }

  if (event.key.toLowerCase() === 'p' && !rigDemoMode) {
    liveArmTracking = !liveArmTracking
    if (!liveArmTracking) disableRig()
    if (replayActive && activeReplaySnapshot) handleSnapshot(activeReplaySnapshot, 'replay')
    else if (latestSnapshot) handleSnapshot(latestSnapshot)
    console.log(`[PoseRig v13] Live arm tracking: ${liveArmTracking ? 'ON' : 'OFF'}`)
    return
  }

  if (event.key.toLowerCase() === 'l' && !rigDemoMode) {
    liveLegTracking = !liveLegTracking
        poseRig?.clear()
    if (replayActive && activeReplaySnapshot) handleSnapshot(activeReplaySnapshot, 'replay')
    else if (latestSnapshot) handleSnapshot(latestSnapshot)
    console.log(`[WiSensing v13] Live 2D knee/hip angle tracking: ${liveLegTracking ? 'ON (bounded)' : 'OFF'}`)
    return
  }

  // M: 자동 → 강제 반전 → 반전 없음 (실제 CNN 좌표계 보정용)
  if (event.key.toLowerCase() === 'm') {
    const next = (MIRROR_MODES.indexOf(mirrorMode) + 1) % MIRROR_MODES.length
    mirrorMode = MIRROR_MODES[next]
    console.log(`[PoseRig] X axis mode: ${mirrorMode}`)
    poseRig?.clear()
    if (!rigDemoMode && replayActive && activeReplaySnapshot) handleSnapshot(activeReplaySnapshot, 'replay')
    else if (!rigDemoMode && latestSnapshot) handleSnapshot(latestSnapshot)
    return
  }

  if (rigDemoMode) return
  const zone = Number(event.key)
  if (Number.isInteger(zone) && zone >= 1 && zone <= 9) {
    updateLocationUI(zone)
    updatePostureUI('standing')
    moveCharacterTo(zone)
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
    renderPose(null)
    setAbsentState('Unavailable', 'unknown')
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
  if (!connected && !rigDemoMode && !replayActive) {
    setLiveBadge('DISCONNECTED')
    backendLastSeenAt = 0
    backendExpired = true
    poseFilter.reset()
    poseRig?.clear()
    renderPose(null)
    setAbsentState('Unavailable', 'unknown')
  } else {
    updateLiveBadge(latestSnapshot)
  }
})
console.log('[WiSensing v13] T/K=12관절 다리 테스트, P/L=CNN 각도 추종, O=JSON 재생, B=복귀')

// ========================================
// 화면 크기 및 매 프레임 이동
// ========================================
function resizeRenderer() {
  const width = Math.max(1, container.clientWidth)
  const height = Math.max(1, container.clientHeight)
  renderer.setSize(width, height, false)
  camera.aspect = width / height
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
  if (mixer) mixer.update(delta)

  // 파일 재생은 시간 흐름에 따라 원본 snapshot/pose를 그대로 입력 파이프라인으로 보낸다.
  if (replayActive && !rigDemoMode && replayFrames.length && now - replayLastTick >= 250) {
    replayLastTick = now
    replayIndex = (replayIndex + 1) % replayFrames.length
    handleSnapshot(replayFrames[replayIndex], 'replay')
  }

  // Backend가 끊기면 마지막 Pose가 계속 실시간인 것처럼 보이지 않도록 비활성화.
  if (!rigDemoMode && !replayActive && backendLastSeenAt &&
      now - backendLastSeenAt > 5000 && !backendExpired) {
    backendExpired = true
    poseFilter.reset()
    poseRig?.clear()
    renderPose(null)
    clearLocationUI('Unavailable')
    updatePostureUI('unknown')
    refreshIdleAnimation()
    console.warn('[WiSensing] Backend snapshot timeout; Pose hidden')
  }

  // Backend Fake는 팔·다리 각도가 거의 바뀌지 않는다.
  // T 키를 누르면 테스트용 12관절을 만들어 GLTF 본 연결을 눈으로 확인한다.
  if (rigDemoMode) {
    const demoPose = createTestPose(demoPoseName)
    const mirrored = resolvePoseMirror(demoPose, mirrorMode, lastMirror)
    lastMirror = mirrored
    const arms = demoPoseName === 'armUp' || demoPoseName === 'armsWide'
    const legs = experimentalLegs && (demoPoseName === 'squat' || demoPoseName === 'legLift')
    if (arms || legs) poseRig?.setPose(demoPose, mirrored, { arms, legs })
    else if (poseRig?.active) poseRig.clear()
    refreshIdleAnimation()
    if (now - demoLastRenderAt >= 80) {
      renderPose(demoPose, mirrored)
      demoLastRenderAt = now
    }
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
      updateLocationUI(currentZone)
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
  poseRig?.update(delta, Boolean(character?.visible) && !isMoving)
  if (rigWasActive && !poseRig?.active) refreshIdleAnimation()


  renderer.render(scene, camera)
}
requestAnimationFrame(animate)
