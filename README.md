# Wi-Fi CSI Project

Wi-Fi CSI(Channel State Information)를 이용해 사람의 상태를 비접촉으로 추정하는 7인 팀 프로젝트입니다.

현재는 기획 초기 단계이며 세부 기능과 담당은 진행하면서 조정할 수 있습니다.

## 주요 기능

- ESP32 기반 Wi-Fi CSI 수집
- Zynq PS에서 CSI 수신/전처리 및 PL 제어
- CNN 기반 자세 추정
- FFT 기반 호흡/주기성 분석
- CSI 기반 사람 위치 추정(Localization)
- AXI 기반 PS-PL 데이터 통신
- PL TOP 및 전체 시스템 통합

## Repository Structure

```text
wifi-csi-project/
├─ docs/               # 아키텍처, 인터페이스, 팀원별 정리
├─ esp32/
│  ├─ tx/              # Wi-Fi 송신
│  └─ rx/              # CSI 수집/수신
├─ ps/                 # PS 소프트웨어
├─ pl/
│  ├─ cnn/             # 자세 추정 가속/RTL
│  ├─ fft/             # FFT 관련 RTL
│  ├─ localization/    # 위치 추정 관련 RTL
│  ├─ axi/             # AXI 인터페이스
│  └─ top/             # PL TOP
├─ ml/
│  ├─ pose/            # 자세 추정 모델/실험
│  ├─ respiration/     # 호흡 분석 모델/실험
│  └─ localization/    # 위치 추정 모델/실험
└─ integration/        # Vivado BD 및 전체 통합
```

PL의 각 기능은 필요에 따라 `rtl/`과 `testbench/`로 구분하며, UVM을 사용할 경우 `testbench/uvm/` 아래에 추가합니다.

## Reference

- Wi-Fi CSI Pose Estimation: https://github.com/ziziccc/wifi-csi-pose
