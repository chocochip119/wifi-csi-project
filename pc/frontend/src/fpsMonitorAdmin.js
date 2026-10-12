import { RecentFpsCounter, poseIdentity } from './fpsMetrics.js'

const backendCounter = new RecentFpsCounter(5000)
const poseCounter = new RecentFpsCounter(5000)
const els = {
  backend: document.getElementById('fps-backend'),
  pose: document.getElementById('fps-pose'),
  screen: document.getElementById('fps-screen'),
}
const label = (key, value) => { if (els[key]) els[key].textContent = value }
const format = (value) => Number.isFinite(value) ? value.toFixed(1) : '--'
let socket = null
let retry = null
let closed = false
let active = false
let screenLastAt = -Infinity
let screenFps = 0

const messages = new BroadcastChannel('wisensing-viewer-settings-v1')
messages.addEventListener('message', ({data}) => {
  if (data?.type !== 'screen-fps' || !Number.isFinite(data.fps)) return
  screenFps = Math.max(0, data.fps)
  screenLastAt = performance.now()
})

const source = new URLSearchParams(location.search).get('backend') ||
  `${location.protocol}//${location.hostname}:8000`
let wsUrl
try {
  const target = new URL(source, location.href)
  target.protocol = target.protocol === 'https:' ? 'wss:' : 'ws:'
  target.pathname = '/ws'
  target.search = ''
  wsUrl = target.toString()
} catch (error) {
  console.warn('[FPS] Backend URL 설정 오류:', error)
}

function reconnect() {
  if (closed || !wsUrl) return
  if (retry !== null) { clearTimeout(retry); retry = null }
  try { socket = new WebSocket(wsUrl) }
  catch (error) { console.warn('[FPS] WebSocket 시작 실패:', error); scheduleRetry(); return }
  socket.addEventListener('open', () => { active = true; backendCounter.reset(); poseCounter.reset() })
  socket.addEventListener('message', event => {
    try {
      const snap = JSON.parse(event.data)
      if (snap?.type !== 'snapshot' || snap.version !== 1) return
      const at = performance.now()
      backendCounter.observe(snap.seq, at)
      poseCounter.observe(poseIdentity(snap.pose), at)
    } catch (error) { console.warn('[FPS] snapshot parsing error:', error) }
  })
  socket.addEventListener('close', () => { active = false; backendCounter.reset(); poseCounter.reset(); scheduleRetry() })
  socket.addEventListener('error', () => { /* close event handles reconnect */ })
}
function scheduleRetry() {
  if (!closed && retry === null) retry = setTimeout(() => { retry = null; reconnect() }, 2500)
}
const timer = setInterval(() => {
  const at = performance.now()
  label('backend', active ? format(backendCounter.fps(at)) : '--')
  label('pose', active ? format(poseCounter.fps(at)) : '--')
  label('screen', at - screenLastAt < 2500 ? format(screenFps) : '--')
}, 500)
window.addEventListener('beforeunload', () => {
  closed = true
  clearInterval(timer)
  if (retry !== null) clearTimeout(retry)
  socket?.close()
  messages.close()
})
reconnect()
