// 기존 Backend /ws 계약: type=snapshot, version=1.
// Frontend와 Backend가 같은 PC에서 실행될 때 localhost/127.0.0.1을 자동 사용.
// 다른 컴퓨터에서 Frontend에 접근하는 경우 Backend의 --host 0.0.0.0 및 방화벽 설정 필요.
export function connectBackend(onSnapshot, onConnection = () => {}) {
  let socket = null
  let stopped = false
  let retryTimer = null
  const override = import.meta.env.VITE_BACKEND_WS_URL
  const scheme = location.protocol === 'https:' ? 'wss' : 'ws'
  const url = override || `${scheme}://${location.hostname}:8000/ws`

  function scheduleRetry() {
    if (stopped || retryTimer !== null) return
    retryTimer = setTimeout(() => {
      retryTimer = null
      connect()
    }, 2000)
  }
  function connect() {
    if (stopped) return
    try { socket = new WebSocket(url) }
    catch (error) { console.warn('Cannot start backend websocket:', error); onConnection(false); scheduleRetry(); return }
    socket.addEventListener('open', () => {
      console.log(`[WiSensing] Backend WebSocket connected: ${url}`)
      onConnection(true)
    })
    socket.addEventListener('message', (event) => {
      try {
        const msg = JSON.parse(event.data)
        if (msg?.type === 'snapshot' && msg.version === 1) onSnapshot(msg)
      } catch (error) { console.warn('Invalid backend snapshot', error) }
    })
    socket.addEventListener('close', () => {
      onConnection(false)
      scheduleRetry()
    })
    socket.addEventListener('error', () => {
      console.warn('Backend WebSocket unavailable:', url)
      // onclose schedules retry
    })
  }
  connect()
  return { close() {
    stopped = true
    if (retryTimer !== null) clearTimeout(retryTimer)
    if (socket) socket.close()
  } }
}
