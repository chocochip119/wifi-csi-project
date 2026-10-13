<div align="center">

![WiSensing 대표 이미지](docs/assets/wisensing-hero.svg)

### Wi-Fi 신호로 사람의 자세와 위치를 추정하는 Camera-less Sensing

**TX 1 · RX 5** &nbsp;|&nbsp; **12관절 Motion** &nbsp;|&nbsp; **9구역 Location** &nbsp;|&nbsp; **Zynq PS + FPGA PL**

[시스템 설명](docs/presentation_20261008.md) · [실행 가이드](docs/bringup.md) · [프로젝트 구조](docs/repository_structure.md) · [통신 규격](docs/ps_pc_protocol.md)

</div>

![시스템 데이터 흐름](docs/assets/wisensing-architecture.svg)

> **구현 구분:** 아래 기본 시스템은 `ps/` + `pc/backend/`의 **PC 위치 추론** 구조입니다. `ps_location/`의 **PS 위치 추론·단일 TCP 포트**는 별도 시험판이며, 발표(2026-10-08) 이후 개발한 기능입니다. 실제 보드 배포·autostart 상태는 소스 머지 여부만으로 확인되지 않습니다.

## 한눈에 보는 프로젝트

| 기능 | 접근 방법 | 결과 |
|:---|:---|:---|
| **Motion** | Wi-Fi CSI → PS 전처리 → FPGA CNN | 카메라 입력 없이 12개 관절의 (x, y) 추정 |
| **Location** | CSI 진폭·RSSI → 2초 특징 → Portable Ridge | 9개 위치 구역 + 추가 상태 클래스 분류 |
| **Visualization** | PS/PC 데이터 통합 | 자세 관절점과 구역 상태를 실시간 표시 |

발표 자료의 **6.52ms FPGA 추론 / PS 1코어 대비 29.7배 / Location Balanced Accuracy 97.78%**는 **발표 시점의 평가 결과**입니다. 서로 다른 모델·시험 환경/기간의 결과를 같은 보드 실행 결과로 혼합하지 않았습니다. 계산 구조·시험 범위·검증의 한계는 [발표자료 기반 기술 해설](docs/presentation_20261008.md)에 정리했습니다.

---

## 시스템

TX Coordinator가 RX의 CSI를 모아 USB CDC ACM(`/dev/ttyACM0`)으로 PS에 보냅니다. PS는 같은 CSI cycle을 두 경로로 사용합니다.

| 경로 | 처리 위치 | PC까지 전달 |
|---|---|---|
| 자세 | PS 전처리 → DDR → FPGA CNN → PS에서 INT8 좌표와 scale 읽기 | TCP **5001** |
| 위치 | PS에서 원본 CSI/STATUS/ACK 전달 → PC Portable Ridge | TCP **5000** |
| 화면 연결 | PC Backend가 위치/Pose 최신 상태 통합 | HTTP/WebSocket **8000** 기본값 |

전체 연결 그림은 [시스템 구조](docs/architecture.md), 바이트 규격은 [PS↔PC 규격](docs/ps_pc_protocol.md)을 참고하세요. 실시간 Three.js 프런트엔드는 구현되어 있으며, Windows에서는 [원클릭 실행기](docs/oneclick_launcher.md)로 PC Backend/Frontend를 함께 실행할 수 있습니다. 호흡 통합은 별도 개발 범위입니다.

## 현재 CNN 기준

| 항목 | RX5 구성 |
|---|---|
| 입력 | INT8 `[15,128,10]`, **19,200 bytes**; batch 포함 시 `[B,15,128,10]` |
| 채널 순서 | RX0..4 base → RX0..4 delta → RX0..4 mask |
| 공유 Encoder | RX별 Conv `3→16, 5×3` → GELU → Conv `16→32, 3×3` → GELU → Pool 출력 `8×4` |
| Encoder 출력 | RX당 `32×8×4=1024`개 INT8 특징 |
| FC | Flatten **5120** → FC1 **128** → GELU → FC2 **128** → GELU → FC3 **24** |
| 출력 | INT8 24 bytes = 12관절 `(x,y)`; 실수 좌표는 `INT8 × output_scale` |
| 가중치 blob | RX5 v2, **685,136 bytes** |

하드웨어는 하나의 Encoder 연산부를 RX별로 재사용합니다. RTL의 RX 파라미터와 별개로 현재 PS·학습·위치 모델·통합 구성은 RX5에 맞춰져 있습니다. 연산 규칙과 golden 생성은 [INT8 계약](ml/pose/INT8.md)을 참고하세요.

## 저장소 안내

| 폴더 | 역할 | 시작 문서 |
|---|---|---|
| `esp32/` | TX Coordinator / RX 수집 펌웨어, 이전 PC 확인 스크립트 | [ESP32](esp32/README.md) |
| `pl/` | CNN Encoder·FC·Loader·AXI·top 원본 RTL과 testbench | [PL](pl/README.md) |
| `ps/` | USB 파서·전처리·FPGA 제어·TCP 서버, PetaLinux 앱 | [PS](ps/README.md) |
| `ml/` | 학습·전처리·INT8 reference·golden 생성 | [ML](ml/README.md) |
| `pc/` | 위치/Pose Backend와 Frontend 추가 위치 | [PC](pc/README.md) |
| `integration/` | 패키지 IP 소스 및 기존 XSA | [하드웨어 통합](integration/README.md) |
| `docs/` | 구조·규격·실행 순서·검증 기록·팀 작업 안내 | [문서 목록](docs/README.md) |

세부 파일 위치와 소스 수정 순서는 [저장소 구조](docs/repository_structure.md)에 정리했습니다. `pl/fft`, `pl/localization`은 이전 실험/빈 골격이고, 현재 위치 추론은 `pc/backend/localization/`에서 실행됩니다.

## Windows 시연 원클릭 실행

이미 Python `.venv`, Node.js, Frontend 의존성이 설치된 개발 PC에서는 `WiSensing_Start.bat`를 더블클릭하세요. 실제 Zybo의 CNN은 별도로 먼저 실행해야 하며, 설정은 별도 팝업으로 열리고 PC 앱은 화면의 종료 버튼 또는 `WiSensing_Stop.bat`로 종료합니다. 상세 내용은 [원클릭 실행 가이드](docs/oneclick_launcher.md)를 참고하세요. 로컬 GLTF 캐릭터 파일은 Git에서 제외되어 그대로 유지됩니다.

## 먼저 실행하기

저장소 루트에서 Python 3.10 이상을 사용합니다.

```bash
python -m venv .venv
# Linux/macOS
source .venv/bin/activate
# Windows PowerShell: .\.venv\Scripts\Activate.ps1
python -m pip install -r pc/backend/requirements.txt
python pc/backend/run_backend.py --fake
```

`http://127.0.0.1:8000/api/snapshot`에서 가짜 스냅샷을 확인합니다. 실제 PS 연결은 `--fake` 대신 `--ps-host <PS_IP>`를 사용하고 RX 배치를 확인해야 위치 추론을 시작할 수 있습니다. [통합 실행 순서](docs/bringup.md)와 [Backend API](pc/backend/README.md)를 참고하세요.

## 검증과 배포 상태

- Python/전처리/Backend/C↔Python 실제 TCP: **102 tests passed**.
- RX5 Encoder 640 words 일치. 전체 CNN은 합성 회귀 입력으로 LOAD 후 reset 없는 INFER 2회, 각 **24/24 bytes** 일치.
- FC·Encoder·Pool·패키지 IP 소스와 Python의 정수 반올림 계약 통일.
- 기존 `integration/design_1_wrapper.xsa`에는 bitstream이 포함되어 있습니다. 해당 XSA와 `ps/test_vectors/`는 과거 통합 자료이며 최신 RTL/최종 학습 모델에 맞춰 재검증해야 합니다.
- 최신 Vivado synthesis/implementation·IP 재패키징·bitstream/XSA 생성, ARM/PetaLinux 전체 빌드, 실제 보드/최종 모델 검증은 별도입니다.

재현 방법과 남은 ESP32 trigger 정합·Pose 윈도우 정책은 [2026-10-07 점검 기록](docs/reviews/2026-10-07-pc-integration.md)에 있습니다. [Git 작업 가이드](docs/git_guide.md)를 따라 브랜치/PR에서 변경을 검토하고 main에 합칩니다.

## 개발 환경

Zybo Z7-20, Vivado, PetaLinux 2020.2, ESP-IDF, Verilog, C, Python/NumPy/FastAPI를 사용합니다. Colab의 모델 학습에는 PyTorch가 필요합니다. ESP32 TX/RX의 저장된 IDF target은 모두 `esp32s3`이며 실제 RX 보드 target은 [ESP32 안내](esp32/README.md)에서 확인하세요.
