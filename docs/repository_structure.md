# 저장소 구조와 소스 관리

현재 저장소는 장치/실행 역할에 따라 `esp32`, `pl`, `ps`, `ml`, `pc`, `integration`, `docs`로 나눕니다. 폴더 이름은 실제 checkout 기준이며 파일을 이동하는 작업 없이 안내를 정리했습니다.

## 영역별 파일 찾기

| 위치 | 내용 / 상태 |
|---|---|
| [esp32/dataset_collecter/ESP-TX](../esp32/dataset_collecter/ESP-TX/README.md) | SoftAP, RX slot 관리, trigger, UDP 수집, USB CDC 프레임 |
| [esp32/dataset_collecter/ESP-RX](../esp32/dataset_collecter/ESP-RX/README.md) | CSI callback, ESP-NOW 제어, UDP 전송 |
| `pl/cnn/rtl/CNN_Encoder/` | Conv MAC, requant, GELU, Pool, 입력/중간 buffer |
| `pl/cnn/rtl/FC/` | Flatten, FIFO, FC MAC/controller, requant/GELU, hidden/pose RAM |
| `pl/cnn/rtl/Loader/` | blob decoder/loader, weight/parameter/LUT RAM |
| `pl/cnn/rtl/axi/` | AXI4-Lite CSR 및 AXI master wrapper |
| `pl/cnn/rtl/top/` | pose_cnn core와 LOAD/INFER controller |
| [pl/cnn/testbench/CNN_Encoder](../pl/cnn/testbench/CNN_Encoder/README.md) | MAC·requant·Encoder 테스트와 벡터 생성기 |
| [pl/cnn/testbench/rounding](../pl/cnn/testbench/rounding/README.md) | 반올림 회귀 runner, 두 requantizer/Pool, 전체 RX5 golden TB |
| `ps/src/`, `ps/include/` | USB 파서·전처리·보드 앱·TCP 서버 및 공통 헤더 |
| `ps/petalinux/` | 앱 설치 스크립트·BitBake recipe·Device Tree 설정 |
| [ps/test_vectors](../ps/test_vectors/README.md) | 과거 RX5 시험 blob/입력/기대 출력, 최신 반올림 재검증 필요 |
| `ps/tests/` | 호스트 TCP 테스트용 C 서버 |
| [ml/pose](../ml/pose/README.md) | 전처리·INT8 reference/golden·v4/v5 notebook·회귀 테스트 |
| [ml/localization](../ml/localization/README.md) | 위치 모델 학습/분석용 자리; 전체 학습 원본 없음 |
| `ml/respiration/` | 현재 실행/학습 코드가 없는 자리 |
| `pc/backend/app/` | 설정, BackendService, HTTP/WebSocket, CLI |
| `pc/backend/protocol/` | PS↔PC WISE 바이트 규격 |
| `pc/backend/localization/` | 실시간 위치 입력/특징/Portable Ridge, 모델 NPZ+JSON |
| `pc/backend/tests/`, `pc/backend/tools/` | 회귀 테스트·fixture, 이전 UDP 디버그 도구 |
| [pc/frontend](../pc/frontend/README.md) | 현재 README만 있음; Frontend 구현 추가 위치 |
| [integration/pose_cnn_1.1](../integration/README.md) | component.xml, xgui, 패키지 IP의 RTL 소스 복사본 |
| `integration/design_1_wrapper.xsa` | 기존 하드웨어 export, 내부 bitstream 포함 |
| [docs](README.md) | 시스템/규격/실행/검증 및 팀 기록 |

AXI/top의 실제 소스는 `pl/cnn/rtl/axi/`, `pl/cnn/rtl/top/`에 있습니다. `pl/fft/rtl/test.v`는 이전 실험이며 `pl/localization/`은 골격입니다. 현재 위치 실행은 `pc/backend/localization/`에서 이뤄집니다. CNN testbench의 구현 디렉터리는 `CNN_Encoder/`와 `rounding/` 두 곳입니다.

## 수정 위치와 함께 맞춰야 할 것

| 작업 | 수정 시작점 | 함께 확인 |
|---|---|---|
| 수집/무선/USB 프레임 변경 | ESP-TX / ESP-RX `main/main.c` | 양쪽 패킷, PS USB 파서, CSV 수집 계약 |
| CNN 연산/연결 변경 | `pl/cnn/rtl/` | 패키지 IP 소스, Python reference, golden, Vivado 재빌드 |
| PS 전처리/제어 변경 | `ps/src/`, `ps/include/` | tensor 순서, CSR/DDR, input/output scale, recipe |
| PS↔PC 패킷 변경 | `ps/src/wise_server.c`, `pc/backend/protocol/wise_protocol.py` | [규격](ps_pc_protocol.md), 실제 C↔Python TCP 테스트 |
| Pose 학습/양자화 변경 | `ml/pose/` | cache, INT8 artifacts, blob, golden, PS 입력 scale |
| 위치 실행/모델 변경 | `pc/backend/localization/` | NPZ+JSON, RX index↔MAC/배치, 특징 회귀 |
| HTTP/WebSocket/화면 변경 | `pc/backend/app/`, `pc/frontend/` | snapshot schema, unavailable/stale, RX 확인 API |

원본 RTL은 `pl/cnn/rtl/`입니다. `integration/pose_cnn_1.1/src/`는 Vivado 패키지의 복사본이므로 원본 수정 후 필요한 파일을 함께 갱신하고 IP를 다시 패키징합니다. XSA/bitstream은 빌드 산출물이며 소스 수정만으로 업데이트되지 않습니다.

학습 데이터·실행 로그·새 모델 출력은 실행 환경에서 관리합니다. 저장소의 Portable Ridge 모델과 회귀 fixture, 과거 보드 fixture는 이미 추적 중인 자료이므로 `.gitignore`만 추가해도 사라지거나 새 모델로 바뀌지 않습니다.
