# Windows 원클릭 실행기 (Electron 사용 안 함)

현재 Windows PC의 **Python Backend + Three.js/Vite Frontend**를 한 번에 실행하고,
시연 화면에서 종료할 수 있도록 하는 개발용 실행 도구입니다. **Zybo의 CNN은 자동 실행하지 않습니다.**

## 첫 사용 준비

- Windows 저장소 경로 예: `D:\wifi_csi\wifi-csi-project`
- 저장소 루트 `.venv\Scripts\python.exe`, 설치된 Backend 의존성 필요
- Node.js LTS의 `npm.cmd`가 PATH에 있어야 함
- 로컬 모델 `pc/frontend/public/models/`는 그대로 유지하며 Git으로 다운로드하지 않음
- 실제 보드에서 `pose_cnn_rx5_live`를 실행하고 PC에서 Zybo 주소가 통신되어야 함
- 기존 VS Code에서 직접 실행 중인 **Backend(8000), Vite(5173)** 는 처음 한 번만 Ctrl+C로 종료 (관리하지 않는 프로세스는 강제로 종료하지 않음)

## 시작

1. 탐색기에서 저장소 루트 `WiSensing_Start.bat` 더블클릭
2. Python Backend가 8000, Vite가 5173에서 준비되면 브라우저의 WiSensing 화면 자동 실행
3. 시연 화면 우상단 **⚙ 설정 · 테스트** 클릭 → 별도 팝업에서 독립 테스트 설정
4. 시연 화면 우상단 **⏻ 프로그램 종료** 클릭 → 확인 후 이번 실행기가 시작한 PC 서버만 종료
5. 브라우저 탭은 종료 후 직접 닫기. 실수로 탭을 닫았다면 `WiSensing_Stop.bat` 더블클릭으로 종료 가능

**브라우저 탭의 X 버튼만 누르는 것은 서버 종료가 아닙니다.**
일반 `npm run dev`에서 열어 본 화면에는 종료 버튼이 표시되지 않습니다.

## Zybo 주소 변경

`WiSensing_Start.bat`의 마지막 실행 인자 `--ps-host 10.10.20.41` 부분을 실제 IP로 변경합니다.
현재 `10.10.20.41`은 테스트 중 Zybo `eth0`에 추가한 주소이므로 **Zybo를 재부팅하면 사라질 수 있습니다**.
실제 주소를 확인하고 시작하세요.

## 문제 해결

| 증상 | 확인 |
|---|---|
| 포트 8000/5173/8765 사용 중 | 이전 실행 터미널을 종료하고 다시 시작; 다른 프로세스를 강제로 끄지 않음 |
| Python 환경 없음 | 저장소 루트 `.venv` 생성 및 `pc/backend/requirements.txt` 설치 |
| `npm` 없음 | Node.js LTS 설치, Windows 환경변수 적용 |
| 캐릭터 미표시 | Git으로 관리되지 않는 `pc/frontend/public/models/` 및 연관 텍스처 유지 |
| Zybo 연결 없음 | PS 앱, PC↔Zybo Ethernet, TCP 5000/5001 확인 |
| 팝업 안 뜸 | 해당 사이트 팝업 허용 |
| 종료 버튼 없음 | 직접 웹 개발 서버로 접속한 상태. `WiSensing_Start.bat`에서 시작해야 사용 가능 |
| 자동 시작 실패 | `.wisensing_runtime/backend.log`, `frontend.log`, `npm-install.log` 확인 |

## 동작 및 안전 조건

- 관리자 권한 없이 Windows 사용자 세션에서 실행
- 로컬 Backend는 `127.0.0.1:8000`, Vite는 `127.0.0.1:5173`
- 종료 제어 서버는 **`127.0.0.1:8765`**에만 바인딩
- 브라우저에서 자동 종료할 때마다 임의 세션 토큰을 확인. 악의적인 타 사이트의 단순 HTTP 요청으로 종료되지 않도록 Origin과 토큰을 함께 검사
- 실행기 자신의 하위 프로세스만 `taskkill /T /F`로 종료. 다른 수동 실행 서버, Zybo, 모델 파일에는 영향 없음
- 설정 팝업은 동일 출처 `BroadcastChannel`로 본 화면에만 테스트 설정을 반영
- `.wisensing_runtime/` 세션 파일과 로그, `pc/frontend/public/models/`는 Git 추적에서 제외
- 이 도구는 Windows 개발 PC에서 Python/Node 설치를 활용하는 **BAT 실행기**입니다. Electron EXE 및 Python 의존성 내장 배포 파일이 아닙니다.

검증: Frontend는 `cd pc/frontend && npm test && npm run build`;
실행기 기본 로컬 HTTP 보호 검사는 `python -m unittest scripts.test_wisensing_launcher`로 확인.
