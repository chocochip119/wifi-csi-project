# 저장소 구조와 소스 찾기

WiSensing 저장소는 **CSI 수집(ESP32) → PS 위치 계산·FPGA CNN → PC 결과 통합/시각화**라는 구현 역할에 따라 분리되어 있습니다. 각 폴더의 README는 해당 구성요소가 무엇을 하고 어떻게 동작하는지부터 설명하고, 상세 설정·테스트·규격은 아래에 연결합니다.

## 한눈에 보는 폴더

```text
wifi-csi-project/
├── esp32/          CSI 수집: TX / RX 펌웨어
├── ps/             Zynq PS 수신·전처리·C Ridge 위치·FPGA 제어·TCP
├── pl/             FPGA Pose CNN 및 Ridge 원본 RTL
├── ml/             Pose/Location 학습·양자화·테스트
├── pc/
│   ├── backend/    PS 위치/Pose 결과 수신·통합·WebSocket
│   └── frontend/   Three.js 2D 스켈레톤·3D 캐릭터·관리자 UI
├── integration/    Vivado IP·XSA 통합 하드웨어 자료
├── ps_location/    PS 위치 추론 이전 시험판 보관
├── ps_onlysw/      PS SW CNN 비교판 (별도)
├── docs/           구조·통신·실행·검증 기록
└── scripts/        실행 지원 스크립트
```

## 기능별 파일 위치

| 구분 | 디렉터리·대표 파일 | 주요 구현 기능 |
|---|---|---|
| **수집 TX** | [`esp32/ESP-TX/`](../esp32/ESP-TX/README.md) | SoftAP·트리거·ESP-NOW·RX 슬롯·UDP CSI 취합·USB CDC ACM |
| **수집 RX** | [`esp32/ESP-RX/`](../esp32/ESP-RX/README.md) | CSI 측정·TX 제어 처리·슬롯별 UDP 전송 |
| **Pose CNN Encoder** | `pl/cnn/rtl/CNN_Encoder/` | Conv1/2 MAC, Requant, GELU, Pool, 라인/중간 버퍼 |
| **Pose CNN FC** | `pl/cnn/rtl/FC/` | Flatten, FIFO, FC1/2/3, 24개 좌표 결과 |
| **Pose CNN 가중치** | `pl/cnn/rtl/Loader/` | 모델 blob 해석·가중치/파라미터 저장 |
| **FPGA 제어** | `pl/cnn/rtl/axi/`, `top/` | AXI4-Lite CSR, AXI master, LOAD/INFER FSM |
| **Pose RTL 검증** | [`pl/cnn/testbench/`](../pl/cnn/README.md) | Conv/FC/정수 연산/golden 일치 테스트 |
| **Ridge FPGA IP** | [`pl/localization/`](../pl/localization/README.md) | Ridge AXI4-Lite RTL·고정소수점 golden TB |
| **PS USB 전처리** | `ps/src/csi_pipeline.c` | CSI/STATUS/ACK 파서와 RX5 INT8 시간 윈도우 |
| **PS FPGA 제어** | `ps/src/pose_cnn_rx5_live.c`, `ps/include/` | DDR·AXI LOAD/INFER, CNN Pose 수신 |
| **PS ↔ PC 전송** | `ps/src/wise_server.c` | TCP 5000 Location/Pose/상태 송신 |
| **PS 설치** | `ps/petalinux/` | PetaLinux 설치 recipe·Device Tree |
| **Pose 학습** | [`ml/pose/`](../ml/pose/README.md) | CSV 전처리·Colab 학습·INT8 reference·golden |
| **Location 학습** | [`ml/localization/`](../ml/localization/README.md) | 955개 특징·11클래스 학습/검증·Portable Ridge export |
| **PC Backend** | `pc/backend/app/`, `protocol/` | FastAPI·WebSocket·Snapshot·TCP 규격 |
| **실시간 Location** | `pc/backend/localization/` | PS Ridge와의 parity 테스트·Portable Ridge 모델·RX 배치 검사 |
| **PC Frontend** | [`pc/frontend/`](../pc/frontend/README.md) | 3D 룸/캐릭터, 2D 관절, 좌우 전환, 관리자/테스트 화면 |
| **Vivado 통합** | [`integration/`](../integration/README.md) | 기존 CNN/병렬 CNN·Ridge IP 패키지, 별도 XSA |
| **별도 PS/CPU 실험** | [`ps_location/`](../ps_location/README.md), [`ps_onlysw/`](../ps_onlysw/README.md) | PS 위치 추론 시험판·PS CNN 비교 프로그램 |

`pl/fft/`는 이전 FFT 실험 코드입니다. `ml/respiration/`은 기본 12관절/위치 실행에 포함되지 않습니다. 실제 PC 프런트엔드는 **`pc/frontend/src/`에 구현되어 있습니다.**

## 수정할 때 함께 확인할 것

| 바꾸는 기능 | 원본 수정 위치 | 함께 점검할 항목 |
|---|---|---|
| CSI 수집·무선·USB | `esp32/ESP-TX/main/`, `ESP-RX/main/` | RX 할당·PS 파서·USB 패킷·RX MAC 순서 |
| Pose CNN 연산 | `pl/cnn/rtl/` | [정수 계약](../ml/pose/INT8.md)·golden·패키지 IP·bitstream |
| Ridge IP 연산 | `pl/localization/rtl/` | `integration/ridge_axi_1.0/`, 테스트벤치·PS 드라이버 |
| PS 전처리/제어 | `ps/src/`, `ps/include/` | 채널·tensor 순서·AXI/DDR·output_scale |
| PS ↔ PC 프로토콜 | `ps/src/wise_server.c`, `pc/backend/protocol/` | [wire format](ps_pc_protocol.md)·TCP 테스트 |
| Pose 학습/양자화 | `ml/pose/` | 모델/scale/blob, input·output golden, RTL 동작 |
| Location 학습/추론 | `ml/localization/`, `pc/backend/localization/` | RX 배치·955 특징·Portable Ridge NPZ/JSON |
| HTTP·WebSocket·UI | `pc/backend/app/`, `pc/frontend/src/` | 스냅샷 유효성·실제 보드 상태·화면 표시 |

**원본 RTL**과 **Vivado 패키지용 RTL 복사본**, **빌드된 XSA/bitstream**은 서로 다른 파일입니다. 소스가 변경되어도 패키지 및 실제 보드 이미지는 자동 변경되지 않습니다. 위치 계산도 기본 PC 경로와 PS/PL 시험 경로를 구분해서 반영하세요.

## 상세 문서

[루트 프로젝트 소개](../README.md) · [전체 시스템 구조](architecture.md) · [PS/PL 인터페이스](interface.md) · [설치·통합 실행](bringup.md) · [문서 목록](README.md)
