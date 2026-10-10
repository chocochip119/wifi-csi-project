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
