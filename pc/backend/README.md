# WiSensing PC Backend

PS가 TCP 5000으로 보내는 원본 CSI/STATUS/ACK를 받아 위치를 추론하고, TCP 5001의 FPGA Pose를 최신 상태로 합쳐 HTTP/WebSocket으로 제공합니다. ZIP의 `handoff/`와 `backend/`를 역할별 Python 패키지로 정리한 실행 코드입니다.

전체 실행은 [통합 실행 순서](../../docs/bringup.md), PS 설정은 [PS README](../../ps/README.md), wire format은 [PS↔PC 규격](../../docs/ps_pc_protocol.md)을 참고하세요.

## 실행

Python 3.10 이상(검증 환경: 3.12). `pc/backend`에서:

```bash
python -m venv .venv
# Linux/macOS
source .venv/bin/activate
# Windows PowerShell: .\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
python run_backend.py --ps-host 192.168.10.2
```

PS에서 최신 `pose_cnn_rx5_live`를 실행해야 합니다. PS가 서버, PC가 클라이언트입니다. PC와 PS 주소는 실제 Ethernet 설정에 맞춰 변경하세요. 브라우저용 서버 기본 주소는 `http://127.0.0.1:8000`입니다. 다른 PC에서 접근하려면 `--host 0.0.0.0`과 해당 방화벽 설정을 사용합니다.

PS 없이 화면 연동만 확인:

```bash
python run_backend.py --fake
```

fake 모드는 모델/PS/FPGA 검증이 아닙니다.

## 구조

- `app/`: 설정, 상태 통합, FastAPI 서버, 실행 CLI
- `protocol/wise_protocol.py`: v1.1 규격(wire version **2**)의 순수 바이트 인코더/디코더
- `localization/`: TCP 입력, 위치 실시간 엔진, 955개 특징의 Portable Ridge
- `localization/models/`: 위치추론용 Portable Ridge `ridge_portable.npz`와 SHA-256/특징 계약 `ridge_portable.json`. 두 파일은 항상 함께 유지합니다. 현재 모델은 업로드한 `run_20261010_162043_79e78e64`(10/10 학습)의 **Ridge만** 변환한 것입니다. ZIP에는 원본 validation CSI CSV가 없어 기존 `ml/localization/export_portable_model.py`의 전체 검증 절차는 실행할 수 없었습니다. 대신 원본 Ridge 분류기와 NumPy 행렬 출력을 합성 40개 입력에 대해 비교했습니다. 검증용 fixture도 같은 합성 입력으로 교체했으므로 모델의 실제 정확도를 검증했다는 의미는 아닙니다.
- `tests/`: 프로토콜, 모델 수치 회귀, HTTP/WebSocket, 실제 C↔Python TCP 테스트
- `tools/udp_receiver.py`: 기존 WCSI v1 UDP 경로 확인용. 현재 Backend 입력과 다른 규격입니다.
- `tools/replay_ps_server.py`: 가짜 PS. 녹화 위치 CSV를 wire v2로 TCP 5000에 재생해 보드 없이 Backend/GUI를 시험합니다(STATUS는 합성값, Pose 없음, 모델 정확도 시험 아님). 예: `python pc/backend/tools/replay_ps_server.py a.csv b.csv --port 5000`

`location_model.py`, `phase_features.py`, `labels.py`도 엔진 import에 필요한 동반 모듈입니다. 파일 두 개만 옮겨서는 실행되지 않습니다. 학습 코드는 `ml/localization/`, PC 실행은 이 폴더로 분리합니다. 두 곳의 `location_*.py`는 import 방식만 다르며, 특징 계산을 바꾸면 양쪽을 함께 고치고 NPZ와 fixture를 다시 생성합니다.

## 상태 및 API

| 경로 | 용도 |
|---|---|
| `GET /health` | Backend 동작 여부와 PS/추론 상태. `ok=true`는 보드 정확도를 뜻하지 않습니다. |
| `GET /api/snapshot` | 위치/사람 상태/Pose 최신 스냅샷 |
| `GET /api/rx-layout` | STATUS의 RX index↔MAC 및 무선 설정 |
| `POST /api/confirm-rx-layout` | 실제 배치와 학습 RX 순서를 확인한 후 위치 추론 시작 |
| `POST /api/inference/stop` | 위치 추론만 정지 |
| `/ws` | 변경된 스냅샷 및 `ping`, `confirm_rx_layout`, `stop_inference` 명령 |

전달 모델에 학습 RX MAC이 저장되어 있지 않아, 첫 연결 후 RX 배치를 확인해야 합니다. STATUS를 받아도 확인 전 `status_ready=false`일 수 있습니다. 확인 뒤 새 STATUS를 받을 때 추론 준비가 완료됩니다(PS가 3초마다 조회). RX MAC/무선 설정 변경, 연결 종료, 수신 과부하에는 기존 위치 결과와 윈도우를 폐기합니다. 누락 CSI는 `empty` 분류로 바꾸지 않습니다.

위치: RX 0..4, 384 bytes/RX, I/Q 순서는 imaginary→real, 처음 2쌍 제외, 진폭 평균 950개+RSSI 평균 5개. 2초 윈도우, 최소 10 사이클/1초 span, 0.1초 선택 간격. 모델의 학습 stride는 2초이고 실시간 엔진은 **0.5초 stride**를 사용합니다. `p10`은 `p05` 위치의 앉기 클래스이며 `empty`는 좌표 없음입니다. 좌표는 수집 지점의 대표 좌표입니다.

Pose: 실제 모델 output_scale을 곱한 12관절 좌표이며 `coordinate_space=model_output`입니다. 화면 정규화 좌표로 가정하지 마세요. 최신 Pose가 2초를 넘거나 연결이 끊기면 무효입니다. `infer_us`는 PS의 밀리초 측정값×1000이며 마이크로초 정밀 측정이 아닙니다.

환경 변수: `WISE_PS_HOST`, `WISE_CSI_PORT`, `WISE_POSE_PORT`, `WISE_BIND_HOST`, `WISE_WEB_PORT`, `WISE_MODEL_PATH`, `WISE_POSE_STALE_S`, `WISE_MONITOR_INTERVAL_S`, `WISE_FAKE`. `--model` 사용 시 NPZ와 같은 이름의 JSON도 필요합니다.

## 검증

저장소 루트에서(개발 의존성 `pytest`, `httpx` 필요):

```bash
python -m pip install -r pc/backend/requirements-dev.txt
python -m pytest pc/backend/tests ml/pose/tests -q
```

C 통합 테스트는 Linux/POSIX와 GCC가 필요합니다. `/dev/mem`이나 보드 없이 checksum-valid USB 프레임을 PS 파서에 넣고 TCP/실제 Backend까지 검증합니다. 현재 모델의 회귀 fixture 40개는 **합성 CSI 입력**으로, 특징/점수/라벨 계산 일치만 확인합니다. 현장 데이터 정확도나 원본 validation 점수는 재검증하지 못했습니다. 보드/ARM/PetaLinux 전체 빌드와 실제 모델 정확도 검증은 [점검 기록](../../docs/reviews/2026-10-07-pc-integration.md)을 참고하세요.
