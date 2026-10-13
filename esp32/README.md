# ESP32 — Wi-Fi CSI 수집 장치

ESP32 펌웨어는 **TX 1대와 RX 5대**가 Wi-Fi 신호를 일정한 순서로 관측하고, CSI를 하나의 수집 주기(cycle)로 모아 Zynq PS에 전달하는 부분입니다. TX는 수집을 조정하고, RX는 실제 채널 상태 정보를 측정합니다.

## 구현 기능과 장치 역할

| 구성 | 하는 일 | 구현 문서 |
|---|---|---|
| **TX Coordinator** (`ESP-TX/`) | SoftAP로 RX 연결, ESP-NOW 모드·슬롯 할당, 트리거 송신, RX UDP 수집, CSI cycle 취합, USB CDC ACM 전송 | [TX 동작·프로토콜·빌드](ESP-TX/README.md) |
| **RX 센서** (`ESP-RX/`) | TX AP 접속, CSI 콜백으로 수신 상태 측정, 자기 슬롯에서 UDP 전송, 재접속·채널 변경 대응 | [RX 동작·설정·빌드](ESP-RX/README.md) |

```text
TX: Wi-Fi 트리거·ESP-NOW 제어 ──→ RX 0~4
TX: UDP 3333으로 측정 CSI 수신 ←── RX 0~4
TX: RX별 CSI를 cycle로 취합 ──────→ PS (USB CDC ACM)
```

TX와 RX는 역할이 다릅니다. RX의 측정값이 **UDP 3333**으로 TX에 모이고, TX에서 PS로 보낼 때는 **USB CDC ACM의 별도 바이너리 프레임**을 사용합니다. PS가 다시 PC로 보내는 TCP 5000/5001과도 구분해야 합니다.

UDP CSI record에는 `trigger_seq`가 없으므로 늦게 수신된 기록이 어느 트리거에 속하는지 항상 구분할 수는 없습니다.

## 설정·연동

- 실제 시연 구성은 **TX 1 + RX 5**이며, 펌웨어의 RX 관리 용량은 최대 8대입니다.
- TX 코드 기본값은 채널 **9/above**, HT40, timeout **4,000 µs**, UDP slot gap **500 µs**입니다. 저장된 NVS 설정이 있으면 실제 값이 달라질 수 있으므로 STATUS로 확인합니다.
- RX가 학습 시 사용한 **RX index/MAC/배치**와 같은 순서로 수집되는지 확인해야 위치 추론의 입력과 일치합니다.
- 현재 TX/RX 프로젝트의 저장된 IDF target은 모두 `esp32s3`입니다. 실제 RX 장치가 ESP32-WROOM-32 계열이라면 **빌드 대상과 보드를 먼저 확인**해야 합니다.
- TX/PS의 USB 패킷 형식은 [TX README](ESP-TX/README.md) 및 [PS CSI 파서](../ps/README.md), 전체 인터페이스는 [통신 규격](../docs/interface.md)을 참고합니다.

## 펌웨어 빌드

ESP-IDF 환경에서 `ESP-TX/`와 `ESP-RX/`를 **서로 다른 프로젝트**로 빌드·플래시합니다. 자세한 업로드 명령, 각 모드와 패킷 구조는 [TX](ESP-TX/README.md) · [RX](ESP-RX/README.md)에 있습니다. TX의 `main/idf_component.yml`에는 IDF `>=5.5` 및 `espressif/esp_tinyusb` 의존성이 선언되어 있습니다.
