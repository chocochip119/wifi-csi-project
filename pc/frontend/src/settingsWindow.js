import './style.css'
import './settingsWindow.css'

const $ = id => document.getElementById(id)
const channel = new BroadcastChannel('wisensing-viewer-settings-v1')
const ids = {
  locationMode:'settings-location-mode', jointsMode:'settings-joints-mode',
  jointsSample:'settings-joints-sample', motionMode:'settings-motion-mode',
  motionSample:'settings-motion-sample', liveArms:'settings-live-arms',
  liveLegs:'settings-live-legs'
}
let lastState = null

function render(state) {
  if (!state?.settings) return
  lastState = state
  for (const [key, id] of Object.entries(ids)) {
    const el = $(id)
    if (el.type === 'checkbox') el.checked = Boolean(state.settings[key])
    else el.value = state.settings[key]
  }
  $('settings-camera-view').value = state.cameraView
  $('settings-mirror-mode').value = state.mirrorMode
  $('settings-manual-fields').hidden = state.settings.locationMode !== 'manual'
  $('settings-joints-sample-field').hidden = state.settings.jointsMode !== 'sample'
  $('settings-motion-sample-field').hidden = state.settings.motionMode !== 'sample'
  $('settings-motion-live-options').hidden = state.settings.motionMode !== 'live'
  document.querySelectorAll('[data-manual-point]').forEach(button => {
    button.classList.toggle('active', button.dataset.manualPoint === state.settings.manualPoint)
  })
  const status = {live:'LIVE', manual:'TEST', sample:'TEST', off:'OFF'}
  $('viewer-settings-summary').textContent =
    `위치 ${status[state.settings.locationMode]} · 관절 ${status[state.settings.jointsMode]} · 모션 ${status[state.settings.motionMode]}` +
    (state.settings.locationMode === 'manual' ? ` · ${state.settings.manualPoint.toUpperCase()}` : '')
  $('settings-window-status').textContent = '메인 화면과 연결됨 · 변경 즉시 적용'
}
channel.addEventListener('message', event => {
  if (event.data?.type === 'state') render(event.data)
})
for (const [key,id] of Object.entries(ids)) {
  $(id).addEventListener('change', event => {
    channel.postMessage({type:'update',key,value: event.target.type === 'checkbox' ? event.target.checked : event.target.value})
  })
}
for (const id of ['settings-camera-view','settings-mirror-mode']) {
  $(id).addEventListener('change', event => {
    channel.postMessage({type:'update',key:id === 'settings-camera-view' ? 'cameraView' : 'mirrorMode',value:event.target.value})
  })
}
document.querySelectorAll('[data-manual-point]').forEach(button => {
  button.addEventListener('click', () => {
    channel.postMessage({type:'update',key:'manualPoint',value:button.dataset.manualPoint})
    channel.postMessage({type:'update',key:'locationMode',value:'manual'})
  })
})
$('settings-all-live').addEventListener('click', () => channel.postMessage({type:'all-live'}))
$('settings-reset').addEventListener('click', () => channel.postMessage({type:'reset'}))
$('viewer-settings-close').addEventListener('click', () => window.close())
document.addEventListener('keydown', event => {
  if (event.key === 'Escape') window.close()
})
window.addEventListener('beforeunload', () => channel.close())
$('viewer-settings-panel').insertAdjacentHTML('afterbegin',
  '<div id="settings-window-status" class="settings-window-status">메인 화면 연결 확인 중...</div>')
channel.postMessage({type:'hello'})
// 팝업을 다시 띄운 직후 main 페이지가 리로드 중이라면 소규모 재요청.
setTimeout(() => { if (!lastState) channel.postMessage({type:'hello'}) }, 500)
