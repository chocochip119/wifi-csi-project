# WiSensing PC Backend

PS가 TCP 5000 하나로 보내는 위치(PS 계산)·Pose(FPGA)·STATUS/ACK를 받아 최신 상태로 합쳐 HTTP/WebSocket으로 제공합니다. 위치 추론은 PS의 `ps/src/loc_ridge.c`가 하며, PC는 RX 배치를 확인한 뒤 결과를 표시합니다. 백엔드는 위치 모델을 재실행하지 않고 PS가 보낸 최신 추론 결과를 검증·통합한 뒤 브라우저에 전달합니다.

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

- `app/`: 설정, 상태 통합, FastAPI 서버, 실행 CLI. `app/ps_link.py`가 PS 단일 포트 클라이언트입니다.
- `protocol/wise_protocol.py`: v1.2 규격(wire version **2**, Location type 5 포함)의 순수 바이트 인코더/디코더
- `localization/`: 위치 실시간 엔진의 Python 기준 구현(PS C 엔진과 parity 테스트), 955개 특징의 Portable Ridge, 원본 CSI 수집용 TCP 입력
- `localization/models/localization/`: 위치 모델 원본 Portable Ridge `ridge_portable.npz`와 SHA-256/특징 계약 `ridge_portable.json`. 두 파일은 항상 함께 유지합니다. 현재 모델은 `run_20261013_122537_33a43334`(10/13 학습)의 Ridge를 `ml/localization/export_portable_model.py`로 내보낸 것입니다(검증 창 267개에서 sklearn과 점수 차이 0, 검증 정확도 0.9925). PS용 `ps/models/loc_ridge_rx5.bin`은 이 파일에서 만듭니다.
- `tests/`: 프로토콜, 모델 수치 회귀, HTTP/WebSocket, 실제 C↔Python TCP 테스트
- `tools/udp_receiver.py`: 기존 WCSI v1 UDP 경로 확인용. 현재 Backend 입력과 다른 규격입니다.
- `tools/replay_ps_server.py`: 가짜 PS. 녹화 위치 CSV를 재생하면서 PS와 같은 방식으로 위치(type 5)를 계산해 TCP 5000으로 보냅니다. 보드 없이 Backend/GUI를 시험합니다(STATUS는 합성값, Pose 없음, 모델 정확도 시험 아님). 원본 CSI도 필요하면 `--forward-csi`. 예: `python pc/backend/tools/replay_ps_server.py a.csv b.csv --port 5000`

`location_model.py`, `phase_features.py`, `labels.py`도 엔진 import에 필요한 동반 모듈입니다. 파일 두 개만 옮겨서는 실행되지 않습니다. 학습 코드는 `ml/localization/`, PC 실행은 이 폴더로 분리합니다. 두 곳의 `location_*.py`는 import 방식만 다르며, 특징 계산을 바꾸면 양쪽을 함께 고치고 NPZ와 fixture를 다시 생성합니다.

## 상태 및 API

| 경로 | 용도 |
|---|---|
| `GET /health` | Backend 동작 여부와 PS/추론 상태. `ok=true`는 보드 정확도를 뜻하지 않습니다. |
| `GET /api/snapshot` | 위치/사람 상태/Pose 최신 스냅샷 |
| `GET /api/rx-layout` | STATUS의 RX index↔MAC 및 무선 설정 |
| `POST /api/confirm-rx-layout` | 실제 배치와 학습 RX 순서를 확인한 후 PS 위치 결과 표시 시작 |
| `POST /api/inference/stop` | 위치 결과 표시만 정지(PS 추론은 계속) |
| `/ws` | 변경된 스냅샷 및 `ping`, `confirm_rx_layout`, `stop_inference` 명령 |

전달 모델에 학습 RX MAC이 저장되어 있지 않아, 첫 연결 후 RX 배치를 확인해야 합니다. 확인한 RX 서명(RX index↔MAC, 무선 설정, generation)과 현재 STATUS가 같을 때만 위치를 표시합니다. 서명이 바뀌면 다시 확인해야 합니다. PS 엔진은 STATUS 변경·RX 누락·1초 넘는 끊김에서 창을 버리고, PC는 2초 넘은 위치 결과(`WISE_LOCATION_STALE_S`)와 연결 종료 시 결과를 무효로 합니다. 누락 CSI는 `empty` 분류로 바꾸지 않습니다.

위치(PS 계산): RX 0..4, 384 bytes/RX, I/Q 순서는 imaginary→real, 처음 2쌍 제외, 진폭 평균 950개+RSSI 평균 5개. 2초 윈도우, 최소 10 사이클/1초 span, 0.1초 선택 간격. 모델의 학습 stride는 2초이고 실시간 엔진은 **0.5초 stride**를 사용합니다. `p10`은 `p05` 위치의 앉기 클래스이며 `empty`는 좌표 없음입니다. 좌표는 수집 지점의 대표 좌표입니다.

Pose: 실제 모델 output_scale을 곱한 12관절 좌표이며 `coordinate_space=model_output`입니다. 화면 정규화 좌표로 가정하지 마세요. 최신 Pose가 2초를 넘거나 연결이 끊기면 무효입니다. `infer_us`는 PS의 밀리초 측정값×1000이며 마이크로초 정밀 측정이 아닙니다.

환경 변수: `WISE_PS_HOST`, `WISE_PS_PORT`(기본 5000, 예전 `WISE_CSI_PORT`도 인식), `WISE_BIND_HOST`, `WISE_WEB_PORT`, `WISE_POSE_STALE_S`, `WISE_LOCATION_STALE_S`, `WISE_MONITOR_INTERVAL_S`, `WISE_FAKE`. 위치 모델을 바꾸면 `ps/tools/export_loc_model.py`로 PS용 `loc_ridge_rx5.bin`을 다시 만들어 보드에 배치합니다.

## 검증

저장소 루트에서(개발 의존성 `pytest`, `httpx` 필요):

```bash
python -m pip install -r pc/backend/requirements-dev.txt
python -m pytest pc/backend/tests ml/pose/tests -q
```

`tests/test_ps_location_parity.py`는 PS C 위치 엔진을 호스트 GCC로 빌드해 같은 USB 스트림에서 Python 엔진과 창·라벨·점수를 비교합니다(Windows MSYS2 GCC도 가능). `tests/test_transport.py`의 C 통합 테스트는 Linux/POSIX와 GCC가 필요합니다. `/dev/mem`이나 보드 없이 checksum-valid USB 프레임을 PS 파서에 넣고 TCP/실제 Backend까지 검증합니다. 현재 모델의 회귀 fixture 40개는 **합성 CSI 입력**으로, 특징/점수/라벨 계산 일치만 확인합니다. 현장 데이터 정확도나 원본 validation 점수는 재검증하지 못했습니다. 보드/ARM/PetaLinux 전체 빌드와 실제 모델 정확도 검증은 [점검 기록](../../docs/reviews/2026-10-07-pc-integration.md)을 참고하세요.
