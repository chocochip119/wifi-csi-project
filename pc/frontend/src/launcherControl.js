// The managed shutdown button is shown ONLY for a page opened by WiSensing_Start.bat.
// Ordinary npm run dev / browser preview never receives a launcher token.
export function setupManagedShutdown() {
  const button = document.querySelector('#viewer-stop-app')
  if (!button) return
  const match = /^#wise-launcher=([A-Za-z0-9_-]{30,})$/.exec(window.location.hash)
  if (!match) {
    button.hidden = true
    return
  }
  const token = match[1]
  button.hidden = false
  button.addEventListener('click', async () => {
    if (!window.confirm('WiSensing을 종료하고 PC Backend와 Frontend도 함께 종료할까요?\nZybo의 CNN은 계속 실행됩니다.')) return
    button.disabled = true
    button.textContent = '종료 중...'
    try {
      const response = await fetch('http://127.0.0.1:8765/stop', {
        method: 'POST',
        headers: {'X-WiSensing-Token': token},
        cache: 'no-store',
        mode: 'cors'
      })
      if (!response.ok) throw new Error(`종료 요청 실패: HTTP ${response.status}`)
      button.textContent = '종료 요청 완료'
      window.alert('WiSensing PC 서버 종료를 요청했습니다.\n이 브라우저 탭을 닫아 주세요.')
    } catch (error) {
      button.disabled = false
      button.textContent = '⏻ 프로그램 종료'
      window.alert('자동 종료에 실패했습니다. WiSensing_Stop.bat로 종료해 주세요.\n' + error.message)
    }
  })
}
