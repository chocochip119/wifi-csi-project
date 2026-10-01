# Wi-Fi CSI Project

ESP32로 수집한 **Wi-Fi CSI(Channel State Information)** 를 이용해 사람의 동작/자세를 추정하고, CNN 추론을 Zynq FPGA에서 가속하는 프로젝트입니다.

현재 프로젝트는 **CSI 기반 동작·자세 추정(CNN)** 에 집중하고 있습니다.

## Project Scope

- ESP32 TX/RX 기반 Wi-Fi CSI 수집
- CSI 데이터셋 수집 및 전처리
- CNN 기반 자세 추정
- CNN 연산의 RTL 구현 및 FPGA 가속
- INT8 / Fixed-point 기반 연산
- AXI 기반 Zynq PS ↔ PL 통신
- PS/PL 통합 및 실시간 추론

## System Flow

```text
ESP32 TX
   ↓ Wi-Fi
ESP32 RX
   ↓ CSI
Zynq PS
   ├─ CSI parsing / buffering
   ├─ preprocessing
   └─ PL control
        ↓ AXI
Zynq PL
   └─ CNN Accelerator
        ├─ CNN Encoder
        ├─ Flatten
        ├─ Fully Connected
        ├─ Requantization
        └─ GELU
             ↓
        Pose / Motion Result
```

## CNN Structure

현재 FPGA 구현 기준 CNN 구조입니다.

```text
Encoder × 3
    ↓
Concat
    ↓
Flatten (3072)
    ↓
FC1 (3072 → 128)
    ↓
GELU
    ↓
FC2 (128 → 128)
    ↓
GELU
    ↓
FC3 (128 → 24)
    ↓
12 Keypoints (x, y)
```

CNN Encoder와 FC 연산부를 RTL로 구현하고 있으며, 양자화된 가중치와 Fixed-point 연산을 사용해 FPGA 추론을 목표로 합니다.

## Repository Structure

```text
wifi-csi-project/
├─ esp32/
│  ├─ dataset_collecter/       # 데이터셋 수집용 ESP32 TX/RX
│  ├─ tx/                      # ESP32 TX
│  └─ rx/                      # ESP32 RX
│
├─ pl/
│  ├─ cnn/
│  │  ├─ rtl/
│  │  │  ├─ CNN_Encoder/       # CNN Encoder RTL
│  │  │  └─ FC/                # Flatten / FC / GELU / Requant 등
│  │  └─ testbench/            # CNN RTL 검증
│  ├─ axi/                     # PS ↔ PL AXI 인터페이스
│  ├─ top/                     # PL 전체 통합
│  ├─ fft/                     # 이전 실험 코드
│  └─ localization/            # 이전 실험 코드
│
├─ ps/                         # Zynq PS 프로그램
├─ ml/                         # 모델 학습 / Python 실험
├─ integration/                # Vivado Block Design / 전체 통합
└─ docs/                       # 시스템 구조 및 인터페이스 문서
```

> `fft`, `localization`은 이전 실험 과정의 코드이며 현재 최종 통합 범위에는 포함하지 않습니다.

## Target Platform

- **FPGA Board:** Zybo Z7-20 (Zynq-7000)
- **CSI Nodes:** ESP32 series
- **FPGA Development:** Vivado
- **Embedded Linux:** PetaLinux 2020.2
- **ESP32 Development:** ESP-IDF
- **RTL:** Verilog

## Documentation

- [System Architecture](docs/architecture.md)
- [Interface Specification](docs/interface.md)

