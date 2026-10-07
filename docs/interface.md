# Interface

| From | To | Data | Interface | Format / Width | 현재 구현 |
|---|---|---|---|---|---|
| ESP32 RX | TX Coordinator | raw CSI | ESP32 Wi-Fi 경로 | ESP32 수집 펌웨어 규격 | esp32/ |
| TX Coordinator | PS | CSI cycle / STATUS / ACK | USB CDC (`/dev/ttyACM0`) | 16-byte header, checksum32, cycle header 32, RX header 6 | ps/src/csi_pipeline.c |
| PS | PL | CSI tensor / control | DDR + AXI4-Lite, PL AXI master | INT8 `[15,128,10]`, 19,200 bytes | ps/src/pose_cnn_rx5_live.c |
| PL CNN | PS | Pose | DDR output | signed INT8 24 coords + CSR output_scale | 12관절 x/y |
| PS | PC Backend | raw CSI / STATUS / ACK | **TCP 5000** | WISE v2, 24-byte header | ps/src/wise_server.c |
| PS | PC Backend | Pose | **TCP 5001** | payload 40 bytes, 24 int8 + float32 scale | ps/src/wise_server.c |
| PC Backend | Frontend | Snapshot | **HTTP / WebSocket** (기본 8000) | JSON `/api/snapshot`, `/ws` | pc/backend/app/web.py |
| FFT | PS/TOP | Respiration | TBD | TBD | 현재 PC 통합 구현 없음 |

PS↔PC 바이트 상세는 [ps_pc_protocol.md](ps_pc_protocol.md), CSR/DDR 주소는 [PS README](../ps/README.md)를 참조합니다. 프런트엔드는 아직 구현되지 않았습니다. TCP 경로는 호스트 C↔Python 테스트를 완료하며 실제 Zybo/ARM 실행은 별도 확인 대상입니다.
