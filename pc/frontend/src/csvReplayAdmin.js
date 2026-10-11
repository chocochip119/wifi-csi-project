// Admin CSV -> existing RX5 INT8 CPU CNN -> same viewer pose replay pipeline.
// Nothing is uploaded to a third-party service: the local WiSensing backend runs
// the offline conversion, and the result stays in this browser session.
export function setupCsvReplayControls({channel, backend}) {
  const $ = id => document.getElementById(id)
  const fileField = $('csv-replay-file')
  const status = $('csv-replay-status')
  const play = $('csv-replay-pause')
  const end = $('csv-replay-stop')
  const postprocess = $('csv-replay-filter')
  const speed = $('csv-replay-speed')
  let frames = null
  let paused = false
  let pending = false
  let enabled = false
  const setStatus = message => { status.textContent = message }
  const updateButtons = () => {
    $('csv-replay-load').disabled = pending
    play.disabled = !enabled
    end.disabled = !enabled
    $('csv-replay-restart').disabled = !enabled
    play.textContent = paused ? '▶ 계속 재생' : '⏸ 일시정지'
  }
  $('csv-replay-load').addEventListener('click', async () => {
    const file = fileField.files?.[0]
    if (!file) { setStatus('먼저 CSI 원본 CSV를 선택하세요.'); return }
    if (file.size > 50*1024*1024) { setStatus('CSV 최대 크기는 50MB입니다.'); return }
    pending = true
    updateButtons()
    setStatus('PC CPU에서 CSI 전처리 + INT8 CNN 추론 중... 잠시 기다려 주세요.')
    try {
      const url = new URL('/api/offline-pose', backend).href
      const response = await fetch(url, {
        method:'POST', body:file,
        headers:{'Content-Type':'text/csv; charset=utf-8'}
      })
      const data = await response.json()
      if (!response.ok) throw Error(data.detail || `서버 응답 ${response.status}`)
      if (!Array.isArray(data.frames) || data.frames.length === 0) throw Error('유효한 예측 프레임 없음')
      frames = data.frames
      paused = false
      enabled = true
      channel.postMessage({type:'csv-replay-start', frames,
        postprocess:postprocess.checked, speed:Number(speed.value)})
      const s = data.summary
      const mae = s.reference_mae == null ? '없음' : s.reference_mae.toFixed(4)
      setStatus(`CSV 추론 완료 · ${s.windows}개 프레임 / ${s.input_rows}행 · CNN 처리 ${s.elapsed_s}s · 카메라 정답 MAE ${mae}\n후처리 ON/OFF는 추론 재실행 없이 동일한 원본 예측을 비교합니다.`)
    } catch(error) {
      setStatus(`CSV 추론 실패: ${error.message}\n로컬 백엔드가 실행 중인지, 모델 파일이 설치됐는지 확인해 주세요.`)
    } finally { pending=false; updateButtons() }
  })
  play.addEventListener('click', () => {
    if (!enabled) return
    paused = !paused
    channel.postMessage({type:'csv-replay-pause',paused})
    updateButtons()
  })
  end.addEventListener('click', () => {
    if (!enabled) return
    enabled = false; paused=false; frames=null
    channel.postMessage({type:'csv-replay-stop'})
    updateButtons()
    setStatus('CSV 테스트 종료. LIVE 표시로 복귀했습니다.')
  })
  $('csv-replay-restart').addEventListener('click', () => {
    if (!enabled || !frames) return
    paused=false
    channel.postMessage({type:'csv-replay-start',frames,
      postprocess:postprocess.checked,speed:Number(speed.value)})
    updateButtons()
  })
  speed.addEventListener('change', () => {
    if (enabled) channel.postMessage({type:'csv-replay-speed',speed:Number(speed.value)})
  })
  postprocess.addEventListener('change', () => {
    if (enabled) channel.postMessage({type:'csv-replay-filter',postprocess:postprocess.checked})
  })
  channel.addEventListener('message', event => {
    if (event.data?.type === 'csv-replay-stopped') {
      enabled=false;paused=false;frames=null
      updateButtons()
      setStatus('메인 화면에서 CSV 테스트를 종료하고 LIVE로 복귀했습니다.')
    }
  })
  for (const id of ['admin-all-live','admin-reset']) {
    $(id)?.addEventListener('click', () => { if (enabled) end.click() })
  }
  updateButtons()
}
