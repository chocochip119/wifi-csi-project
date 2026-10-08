# 저장소 루트에서 또는 scripts 폴더에서 실행 가능.
# 예: .\scripts\start_backend_real.ps1 -PsIp 192.168.10.2
param(
  [Parameter(Mandatory=$true)][string]$PsIp,
  [string]$ModelPath = ""
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$runner = Join-Path $root 'pc\backend\run_backend.py'
$venvPython = Join-Path $root '.venv\Scripts\python.exe'
if (!(Test-Path $runner)) { throw "Backend 실행파일 없음: $runner" }
$python = if (Test-Path $venvPython) { $venvPython } else { 'python' }
$argsList = @($runner, '--ps-host', $PsIp)
if ($ModelPath) { $argsList += @('--model', $ModelPath) }
Write-Host '============================================'
Write-Host '[WISE] 실제 보드 연결 모드 (fake 아님)'
Write-Host "[WISE] PS = $PsIp; TCP = 5000 CSI/STATUS, 5001 POSE"
Write-Host '[WISE] Web backend = http://127.0.0.1:8000'
Write-Host '[WISE] RX 배치/MAC 확인 후 별도 Integration 페이지에서 추론 시작'
Write-Host '============================================'
& $python @argsList
exit $LASTEXITCODE
