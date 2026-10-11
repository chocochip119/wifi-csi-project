import * as THREE from 'three'

// Presentation camera only; neither pose coordinates nor zone mapping is changed.
// Three presses from front reach the left/right limit: 0, +/-12, +/-24, +/-36 deg.
export function createRoomCameraControls(camera, container) {
  const MAX_DEG = 36
  const STEP_DEG = 12
  const baseEye = new THREE.Vector3(0, 3.4, 7.5)
  const baseTarget = new THREE.Vector3(0, 1.05, -0.16)
  let angle = 0
  let targetAngle = 0

  const toolbar = document.createElement('div')
  toolbar.className = 'wisensing-camera-orbit'
  toolbar.setAttribute('role', 'group')
  toolbar.setAttribute('aria-label', '3D 공간 좌우 시점')
  // Scene card is already positioned relative; keep the controls inside it.
  Object.assign(toolbar.style, {
    position: 'absolute', top: '82px', right: '18px', zIndex: '24',
    display: 'flex', alignItems: 'center', gap: '6px',
    padding: '6px', border: '1px solid rgba(88,219,232,.42)',
    borderRadius: '12px', background: 'rgba(8,19,27,.88)',
    backdropFilter: 'blur(12px)', boxShadow: '0 9px 28px rgba(0,0,0,.25)'
  })

  const buttons = []
  function makeButton(text, label, onClick) {
    const button = document.createElement('button')
    button.type = 'button'
    button.textContent = text
    button.title = label
    button.setAttribute('aria-label', label)
    Object.assign(button.style, {
      color: '#e4f8fb', background: 'rgba(49,116,127,.14)',
      border: '1px solid rgba(92,200,213,.25)',
      borderRadius: '8px', fontSize: '12px', fontWeight: '600',
      minWidth: text === '정면' ? '53px' : '33px', height: '32px',
      padding: '3px 7px', cursor: 'pointer', touchAction: 'manipulation'
    })
    button.addEventListener('click', onClick)
    toolbar.appendChild(button)
    buttons.push(button)
    return button
  }
  const left = makeButton('◀', '왼쪽으로 12도 회전', () => setAngle(targetAngle - STEP_DEG))
  const home = makeButton('정면', '정면 시점으로 복귀', () => setAngle(0))
  const right = makeButton('▶', '오른쪽으로 12도 회전', () => setAngle(targetAngle + STEP_DEG))
  const indicator = document.createElement('span')
  Object.assign(indicator.style, {
    padding: '0 4px', minWidth: '33px', color: '#83eaf1',
    fontSize: '10px', fontWeight: '600', fontVariantNumeric: 'tabular-nums',
    textAlign: 'center'
  })
  toolbar.appendChild(indicator)
  container.parentElement.appendChild(toolbar)

  function setAngle(next) {
    targetAngle = Math.max(-MAX_DEG, Math.min(MAX_DEG, next))
    indicator.textContent = targetAngle === 0 ? '0°' : `${targetAngle > 0 ? '+' : ''}${targetAngle}°`
    left.disabled = targetAngle <= -MAX_DEG
    right.disabled = targetAngle >= MAX_DEG
    for (const button of [left, right]) {
      button.style.opacity = button.disabled ? '0.35' : '1'
      button.style.cursor = button.disabled ? 'default' : 'pointer'
    }
    home.style.borderColor = targetAngle === 0 ? 'rgba(105,228,236,.72)' : 'rgba(92,200,213,.25)'
  }

  function setBaseView(eye, lookAt) {
    baseEye.copy(eye)
    baseTarget.copy(lookAt)
    // Important: resize changes the baseline, but must not erase the user's orbit.
    update(0)
  }

  function update(dt) {
    const alpha = dt > 0 ? Math.min(1, 1 - Math.exp(-dt * 9)) : 1
    angle += (targetAngle - angle) * alpha
    if (Math.abs(targetAngle - angle) < 0.01) angle = targetAngle
    const radians = angle * Math.PI / 180
    const dx = baseEye.x - baseTarget.x
    const dz = baseEye.z - baseTarget.z
    const radScale = 1 + 0.10 * Math.abs(angle) / MAX_DEG
    const x = baseTarget.x + (dx * Math.cos(radians) + dz * Math.sin(radians)) * radScale
    const z = baseTarget.z + (dz * Math.cos(radians) - dx * Math.sin(radians)) * radScale
    const y = baseEye.y + 0.14 * Math.abs(angle) / MAX_DEG
    camera.position.set(x, y, z)
    camera.lookAt(baseTarget)
  }

  setAngle(0)
  return { update, setBaseView }
}
