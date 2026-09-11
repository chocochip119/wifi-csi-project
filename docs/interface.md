# Interface

모듈 간 연결이 확정될 때마다 이 문서에 입력/출력과 데이터 형식을 정리합니다.

| From | To | Data | Interface | Format / Width | Status |
|---|---|---|---|---|---|
| ESP32 RX | PS | CSI packet | TBD | TBD | TBD |
| PS | PL AXI | CSI / control | AXI | TBD | TBD |
| AXI | CNN | CSI window | TBD | TBD | TBD |
| AXI | FFT | CSI time-series | TBD | TBD | TBD |
| AXI | Localization | CSI feature | TBD | TBD | TBD |
| CNN | PS/TOP | Pose result | TBD | 12 keypoints / 24 values 예정 | TBD |
| FFT | PS/TOP | Respiration result | TBD | TBD | TBD |
| Localization | PS/TOP | Position result | TBD | Zone 또는 coordinate 예정 | TBD |

## 작성 규칙

- 인터페이스가 바뀌면 코드보다 먼저 또는 코드와 함께 이 문서를 갱신한다.
- bit width, signed/unsigned, valid/ready, packet/frame 기준을 가능한 한 명확히 기록한다.
- 확정되지 않은 항목은 억지로 정하지 않고 `TBD`로 둔다.
