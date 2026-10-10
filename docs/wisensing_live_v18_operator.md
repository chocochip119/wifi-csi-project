# WiSensing 실제 PC 설치 / LIVE 시연 및 관리자 화면

이 문서는 기존 `main`의 원클릭 실행·설정 팝업 기능을 보존하면서 LIVE 위치·모션 시연을 설명합니다.

## 구동 PC에서 가져오기

```powershell
cd D:\wifi_csi\wifi-csi-project
git switch main
git pull --ff-only origin main
cd pc\frontend
npm ci
```

새 구동 PC라면 `git clone https://github.com/chocochip119/wifi-csi-project.git` 후 같은 절차를 진행합니다. Python 의존성 설치는 `python -m pip install -r pc/backend/requirements.txt` (저장소 루트)로 수행합니다.

**주의:** `pc/frontend/public/models/{Male01,Male02,Female01,Female02}.gltf`와 참조하는 .bin/텍스처가 저작권 및 용량 때문에 Git에 없습니다. 기존 PC에서 사용권 있는 모델 파일을 옮겨야 캐릭터가 보입니다. 최종 FPGA 가중치·BOOT.BIN도 별도 준비가 필요합니다.

## 실행

Zybo PetaLinux 콘솔에서 최종 모델과 동일한 input_scale, blob으로 `pose_cnn_rx5_live /dev/ttyACM0 <encoder.input_scale> 0 /root/weights_5rx.bin` 실행. PC 저장소 루트에서:

```powershell
.\scripts\start_backend_real.ps1 -PsIp 192.168.10.2
```

주소는 **실제 Zybo IP**로 바꿔야 하며 `--fake`는 실물 검증용이 아닙니다. PC의 별도 터미널에서 `cd pc\frontend; npm run dev` 실행. 기존 `WiSensing_Start.bat` 원클릭 실행도 유지됩니다(자세한 내용은 `docs/oneclick_launcher.md`).

- 시연: http://localhost:5173/
- 관리자: http://localhost:5173/integration.html
- 모션·수동위치·좌우반전 테스트: 메인 상단 **설정 · 테스트** 팝업

## 시연 모드

- **위치 따라가기**: 실제 P01~P09의 위치에 캐릭터 이동
- **중앙 고정 · 모션 보기**: **Location Result는 실제 위치를 계속 표시**하지만 캐릭터는 Zone 5에 고정
- 모드는 실제 CSI TCP 5000, Pose TCP 5001, WebSocket 수신을 차단하지 않습니다.
- 관리자에서 RX0..4의 실제 MAC/슬롯/학습 배치를 확인한 다음에만 **배치 확인 후 위치 추론 시작**을 클릭하세요. 위치가 Unavailable이면 원인/STATUS와 RX 상태를 확인하세요.
- Pose Result 스켈레톤은 CNN 12관절 좌표를 표시하고 캐릭터는 해당 좌표로 리깅합니다. 2D 좌표에서 3D 깊이는 복원되지 않으므로 완전 일치는 보장되지 않습니다. 실제 다리 추종은 기본 OFF, 설정 팝업에서 켤 수 있습니다.
- `T`나 `O` 재생 중에는 테스트 데이터가 우선될 수 있습니다. 실제 확인 전 `B`로 로컬 재생을 종료하고 설정 팝업에서 **전체 LIVE**를 누르세요.

## 관리자 지표

- `location.infer_ms`: PC 위치 모델 `predictor()` 실행시간, CSI 2초 윈도우 수집시간 제외
- `location.age_ms`: CSI 윈도우의 타임스탬프 이후 현재까지 경과시간
- `pose.infer_ms`: PS가 보고한 FPGA Pose 추론시간
- `pose.age_ms`: Backend가 마지막 Pose 패킷을 수신한 후 경과시간
- 값이 없으면 **측정 전**으로 표시합니다. 모든 지표가 전체 종단 간 지연시간을 의미하지는 않습니다.
- 관리자 진단의 `raw_pose_joints`는 3D 표시 전 Backend 원본 좌표입니다.

## 검증

```powershell
python pc\backend\tools\verify_wise_live.py --seconds 30 --require-pose --require-location --record recordings\wise_live_30s.jsonl
```

모델 파일이 없다면 실제 캐릭터 표시는 불가합니다. 실제 하드웨어·모델 정확도 검증은 구동 PC/Zybo 연결 후 진행해야 합니다.


## 통합 관리자 및 12관절 직접 편집 (v19)

- 메인 시연 화면 오른쪽 상단 `⚙ 관리자 · 관절 테스트` 버튼 → `/integration.html`. 기존 `/settings.html`은 관리자 화면으로 이동합니다.
- 관리자에서 실제 위치/중앙 고정/수동 위치, 관절 소스(LIVE/TEST/비활성), 카메라 시점·좌우 반전, 실제 팔·다리 추종을 설정합니다.
- 실제 팔과 **다리 모두 기본 ON**입니다. 좌표를 조정해 2D↔3D 깊이 추정 오차를 확인하며, 불안정하면 관리자에서 개별적으로 OFF 가능합니다.
- 16가지 좌표 프리셋, 12관절 SVG 드래그 및 X/Y 수치 편집, 실측 Pose 편집 복사, 프레임 저장·부드러운 연속 재생, JSON 내보내기/불러오기 기능을 제공합니다.
- 스켈레톤과 3D 리그는 동일한 Pose 객체를 사용합니다. 단, 2D→3D IK는 보정이 필요하며 단순히 같은 좌표로 구동한다는 것이 실제 사람 자세와의 일치를 보장하지 않습니다.
- 관리자의 내장 미리보기 iframe은 별도 WebGL 장면이므로 GPU/CPU 사용량이 늘어날 수 있습니다. GPU 성능이 부족하면 시연 화면은 별도 창에서 테스트하세요.
- 브라우저 테스트는 FPGA/위치 Backend 입력을 변경하지 않습니다. 시스템 상태는 언제든 관리자가 따로 조회합니다.
