# 2026-10-07 PS↔PC TCP 통합 점검

## 기준

GitHub main `5715bf5a2af2e005325b3134701d365e8ac553a4`와 사용자 첨부 `wise_backend_ready_v1.zip`, Colab v5 notebook을 확인했습니다. 사전 상태를 먼저 보고한 후 사용자가 TCP 선택을 확정했습니다. 기존 전체 코드 점검의 후속으로, 이번 검증은 최신 PS 변경과 전달 Backend/노트북의 연결에 집중합니다.

## 수정 내용

| 사전 문제 | 조치 |
|---|---|
| PS의 UDP WCSI v1과 ZIP의 TCP WISE v2가 호환되지 않음 | PS에 wire v2 TCP 서버 추가: CSI/STATUS/ACK 5000, Pose 5001 |
| TCP 연결이 FPGA 추론 경로를 지연시킬 수 있음 | 포트별 스레드/64-frame 큐, 250ms 송신/큐 나이 제한, overflow 시 전체 연결 초기화 |
| UDP Pose에는 output_scale이 없어 ZIP 형식과 다름 | TCP Pose에 실제 PL output_scale, window/end sequence, infer time 및 24좌표 전달 |
| PS가 STATUS를 시작할 때만 요청해 PC 상태가 만료됨 | 실행 중 3초마다 TX STATUS 조회, 재접속 시 최근 STATUS 제공 |
| `_bypass` 이름으로 바뀐 소스와 recipe 이름 불일치, pthread 링크 누락 | 일반 pipeline/live 이름으로 정리, TCP 소스/헤더 및 `-pthread` 반영 |
| recipe에 없는 `.bin` 파일을 필수로 요구 | source-only 설치 지원, 검증된 바이너리 디렉터리 명시 시 선택적으로 함께 설치 |
| ZIP 폴더 이동 시 절대 import/임시 sys.path에 의존 | `pc/backend/app`, `protocol`, `localization` 패키지로 정리하고 상대 import 수정 |
| bare uvicorn만 설치하면 WebSocket 동반 패키지가 빠질 수 있음 | `uvicorn[standard]` 사용 |
| 잘못된 Pose scale NaN/Inf가 JSON 상태에 유입될 수 있음 | 유한 양수 scale 검사, 유한 좌표만 상태에 포함 |
| Pose 종료/접속 오류 시 cached Pose 및 스레드 정리 부족 | socket shutdown, 연결 종료 시 cached Pose 삭제, start 실패 자원 정리 |
| PS 입력 scale이 매우 작을 때 float→int 변환 전에 오버플로 | float 범위에서 ±127로 먼저 포화 |
| v5가 기존 외부 prepare를 계속 불러 빈 CSI를 mask=1로 표시 | 검증된 팀 `ml/pose/prepare.py`와 43개 회귀 테스트 추가, v5에서 수정 commit을 별도 모듈명으로 고정 로드 |
| CLI `--reload`가 실제로 무시됨 | 실행하지 않는 옵션 제거 |

`handoff/`, pycache 및 임시 원본 디렉터리를 GitHub 실행 구조에 넣지 않습니다. 모델 NPZ와 40-window 회귀 fixture는 전달받은 바이트를 유지합니다. JSON의 설정값을 유지하고 줄바꿈만 저장소의 LF 규칙으로 통일합니다. `pc/frontend`에는 구현 상태와 연결 API를 안내하는 README만 추가합니다. 원래 ZIP에 프런트엔드/GLB/텍스처가 없으므로 만들어진 것으로 표시하지 않습니다.

## 검증 결과

환경: Linux x86_64, Python 3.12, GCC, Icarus Verilog 12. 사용한 Python 버전은 전달 모델 제작 환경과 다르지만 Portable Ridge 수치 회귀는 일치했습니다.

- `python -m pytest pc/backend/tests ml/pose/tests -q`: **69 passed**, 테스트 클라이언트 의존성의 deprecation warning 1개.
- Backend/순수 protocol/model/lifecycle: 21개 테스트.
- C↔Python 실제 TCP: 5개 테스트. USB 프레임을 7-byte 조각으로 PS 파서에 입력하고 헤더/페이로드, checksum 거부, 누락 RX, STATUS/ACK/Pose, 실제 위치 추론, cached STATUS 재접속, 느린 CSI 수신자와 Pose 포트 분리를 확인했습니다.
- 수정 prepare: 43개 테스트. 빈/잘못된 CSI mask, 정상 zero CSI, shape/값 계약, CLI 경로 등을 확인했습니다.
- 모델 회귀: 전달된 40개 윈도우를 원본 I/Q에서 재계산. 특징 955개, 11-class 점수, 라벨 모두 전달된 sklearn 기준과 일치했습니다. 새 현장 데이터 정확도를 측정한 것은 아닙니다.
- PS live/board-test 앱: `gcc -std=c11 -Wall -Wextra -Werror` 호스트 컴파일 통과. live에는 `-lm -pthread` 적용.
- PetaLinux 설치 스크립트: bash 구문, source-only 배치, recipe가 참조하는 파일 존재, 배치된 소스의 호스트 컴파일, 선택 바이너리 배치 확인. 선택 바이너리 배치 시험에는 합성 파일을 사용했고 배포 모델로 저장하지 않았습니다.
- Colab v5: 코드 셀 17개 구문 검증. GPU 학습/실제 CSV/INT8 최종 export 실행은 수행하지 않았습니다.

## 남은 배포 확인 항목

### FC 원본 RTL / 패키지 IP / Python INT8 규칙 불일치

최신 main의 `pl/cnn/rtl/FC/Common/requant_core.v`는 음수에서 `value+half-1`을 shift합니다. `integration/pose_cnn_1.1/src/requant_core.v`와 v5가 고정한 외부 INT8 참고 구현은 기존 음수 offset 방식입니다.

Icarus로 `acc=-4, bias=0, multiplier=1, shift=2`를 넣은 결과:

| 구현 | 출력 |
|---|---:|
| 현재 FC 원본 RTL | -1 |
| 현재 패키지 IP의 requant_core | -2 |

두 경로가 수치적으로 같지 않으므로 v5에서 생성한 golden vector/실제 보드와 최신 FC RTL의 bit-exact 일치를 가정하면 안 됩니다. 이번 TCP 작업에서는 RTL 정책을 임의로 변경하지 않았습니다. 하드웨어 담당자가 Encoder/FC/export/reference/IP의 반올림 계약을 통일하고 IP 재패키징, Vivado 구현, 최종 모델 golden 비교를 해야 합니다.

### 기존 ESP32 수집 동기화 결함

이전 전체 점검에서 확인한 `esp32/dataset_collecter/ESP-TX/main/main.c`의 UDP CSI header에는 generation/RX index만 있고 trigger_seq가 없습니다. 최신 main에서도 이 경로는 변경되지 않았습니다. 이전 트리거의 늦은 CSI가 다음 cycle에 들어가는 수락 조건이 남아 있으므로 실제 측정의 시각 정합을 보장하려면 TX/RX 프로토콜과 측정→트리거 연결을 함께 수정해야 합니다. 이번 PS↔PC TCP 작업에서 ESP32 펌웨어는 변경하지 않았습니다.

### PS Pose 윈도우 시간 연속성 정책

기존 PS Pose 전처리는 trigger_seq의 누락/재시작/역전을 윈도우 초기화 조건으로 쓰지 않습니다. 수신 성공 cycle 10개를 묶는 동작이며, 학습 Dataset도 시간 간격을 기준으로 끊지 않습니다. "연속 측정 10개"인지 "최근 수신 성공 10개"인지 계약을 결정하고 학습/PS를 함께 맞춰야 합니다. 이번 위치 엔진의 stale/window 검사와 별개로 남아 있는 기존 Pose 경로의 정책 항목입니다.

### 보드와 최종 데이터

ARM cross compile, PetaLinux 전체 빌드, 실제 Zybo TCP/네트워크 부하, 실제 ESP32 RX 배치, 최종 학습 모델의 input/output scale 및 Pose 정확도는 장비/데이터가 없어 여기서 실행하지 못했습니다. PS README의 2026-09-30 보드 기록은 이전 코드의 기록이며 이번 TCP 코드 검증으로 해석하지 않습니다.

전달 위치 모델에는 RX MAC이 없어 물리 배치와 학습 순서를 직접 확인해야 합니다. 학습 stride=2초, 실시간 stride=0.5초 override가 적용됩니다. Pose 좌표는 모델 출력 좌표계이며 frontend 화면 좌표로 자동 정규화하지 않습니다.

기존 UDP 디버그 경로는 선택적으로 유지합니다. PC Backend는 새 TCP 규격만 받습니다. 프런트엔드와 호흡 통합은 아직 구현되지 않았습니다.
