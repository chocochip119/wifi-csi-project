# ESP32 CSI 수집

현재 실행 펌웨어는 `dataset_collecter/ESP-TX`와 `dataset_collecter/ESP-RX`입니다. 디렉터리의 `collecter` 철자는 기존 경로를 유지합니다.

| 위치 | 역할 |
|---|---|
| [ESP-TX](dataset_collecter/ESP-TX/README.md) | SoftAP/ESP-NOW로 RX 관리, trigger 송신, UDP CSI 수집, USB CDC ACM으로 PS 전달 |
| [ESP-RX](dataset_collecter/ESP-RX/README.md) | TX 제어 적용, CSI 측정, RX slot에 맞춰 UDP로 TX에 반환 |
| `rx/csi_test.py`, `rx/wave.py` | 이전 COM5·921600bps 텍스트 수신/CSI_DATA 그래프 도구 |
| `tx/` | 현재 펌웨어 코드가 없는 자리 |

RX→TX의 UDP 3333과 PS→PC의 TCP 5000/5001은 서로 다른 구간입니다. 현재 TX→PS는 네이티브 USB CDC ACM이고, 기존 Python 텍스트 도구는 TX의 binary USB cycle parser를 대신하지 않습니다.

## 현재 소스 설정

통합은 RX5를 사용하지만 펌웨어 최대 RX 수는 8입니다. TX의 소스 기본값은 채널 9/above, HT40, timeout 4000µs, UDP slot gap 500µs입니다. NVS 저장값이 있으면 기본값보다 우선하므로 실제 상태는 STATUS로 확인합니다. RX 자체 부팅 기본 채널은 6이며, 실제 접속/할당 시 TX 설정을 확인해야 합니다.

TX와 RX의 `sdkconfig`, `sdkconfig.defaults`는 모두 `CONFIG_IDF_TARGET="esp32s3"`로 저장되어 있습니다. 실제 RX가 ESP32-WROOM-32라면 해당 ESP-IDF 프로젝트의 target과 보드 설정을 확인한 뒤 빌드하세요. 문서에서 하드웨어를 바꾼 것으로 표시하거나 이 작업에서 target을 수정하지 않았습니다.

## 빌드 위치

ESP-IDF 환경에서 각 프로젝트 디렉터리로 이동한 뒤 실행합니다. TX의 `main/idf_component.yml`은 IDF `>=5.5` 및 `espressif/esp_tinyusb` 의존성을 선언합니다.

```bash
cd esp32/dataset_collecter/ESP-TX
idf.py build
idf.py -p COMx flash monitor
```

RX는 `esp32/dataset_collecter/ESP-RX`에서 동일한 방식으로 빌드합니다. `COMx`는 실제 flash 포트로 바꿉니다. 두 펌웨어의 패킷 구조를 함께 유지하고, PS 파서의 USB 프레임 계약도 확인하세요.

UDP CSI header에는 generation/RX index가 있으나 trigger_seq가 없어 늦은 record의 cycle 정합 문제가 남아 있습니다. 자세한 검증 범위는 [점검 기록](../docs/reviews/2026-10-07-pc-integration.md), 이후 연결은 [PS](../ps/README.md)와 [통합 실행](../docs/bringup.md)을 참고하세요.
