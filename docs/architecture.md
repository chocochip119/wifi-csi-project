# System Architecture

## 목표

Wi-Fi CSI를 수집해 Zynq PS/PL에서 처리하고, 자세·호흡·위치 정보를 추정하는 시스템을 구성한다.

## 현재 구상

```text
ESP32 TX
   ↓ Wi-Fi
ESP32 RX
   ↓ CSI
Zynq PS
   ├─ CSI parsing / buffering
   └─ PL control
        ↓ AXI
Zynq PL
   ├─ CNN → Pose Estimation
   ├─ FFT → Respiration Analysis
   ├─ Localization → Position Estimation
   └─ TOP → Module Integration
```

## TODO

- [ ] ESP32 수량 및 배치 확정
- [ ] CSI packet format 확정
- [ ] PS/PL 역할 분담 확정
- [ ] CNN 입력 형상 확정
- [ ] FFT 적용 위치 및 호흡 추정 방식 확정
- [ ] 위치 추정 방식 확정
- [ ] 전체 블록다이어그램 작성
