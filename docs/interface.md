# 인터페이스 — RX5 통합

| From | To | Data | Interface | Format / Width | 현재 구현 |
|---|---|---|---|---|---|
| ESP32 RX | TX Coordinator | raw CSI | ESP32 Wi-Fi 경로 | ESP32 수집 펌웨어 규격 | esp32/ |
| TX Coordinator | PS | CSI cycle / STATUS / ACK | USB CDC (`/dev/ttyACM0`) | 16-byte header, checksum32, cycle header 32, RX header 6 | ps/src/csi_pipeline.c |
| PS | PL | CSI tensor / control | DDR + AXI4-Lite, PL AXI master | INT8 `[15,128,10]`, 19,200 bytes | ps/src/pose_cnn_rx5_live.c |
| PL CNN | PS | Pose | DDR output | signed INT8 24 coords + CSR output_scale | 12관절 x/y |
| PS | PC Backend | raw CSI / STATUS / ACK | **TCP 5000** | WISE v2, 24-byte header | ps/src/wise_server.c |
| PS | PC Backend | Pose | **TCP 5001** | payload 40 bytes, 24 int8 + float32 scale | ps/src/wise_server.c |
| PC Backend | Frontend | Snapshot | **HTTP / WebSocket** (기본 8000) | JSON `/api/snapshot`, `/ws` | pc/backend/app/web.py |

PS↔PC 바이트 상세는 [ps_pc_protocol.md](ps_pc_protocol.md)를 참조합니다. FFT/호흡과 실행 프런트엔드는 현재 통합에 포함되지 않습니다. TCP는 호스트 C↔Python 테스트를 완료했으며 실제 Zybo/ARM 실행은 별도 확인 대상입니다.

## CSI와 Pose tensor

| 항목 | 계약 |
|---|---|
| 원본 I/Q | signed int8, imaginary→real 순서; 현재 위치 모델은 384 bytes/RX |
| 프레임 특징 | RX5 base/delta/mask `[15,128]` |
| PL 입력 | INT8 `[15,128,10]`, C 순서; 시간축이 마지막, 19,200 bytes |
| 채널 번호 | `ch=rx+5*ic`, `rx=0..4`, `ic=0/1/2` = base/delta/mask |
| Pool/Flatten | RX별 `32×8×4=1024` → 전체 5120 INT8 특징 |
| PL 출력 | signed INT8 24개, 12관절 x/y, scale은 LOAD 뒤 CSR에서 읽음 |
| 실수 Pose | `coordinate=int8*output_scale`, coordinate_space=model_output |

USB type 번호(STATUS=1, CYCLE=2, ACK=3)와 TCP type 번호(CSI=1, Pose=2, STATUS=3, ACK=4)는 다릅니다. PS가 프레임을 검증하고 TCP 규격으로 다시 인코딩합니다. USB recv/TCP recv의 한 번 읽기 길이를 프레임 경계로 사용하지 않습니다.

## PS↔PL CSR / DDR

현재 [pose_cnn_regs.h](../ps/include/pose_cnn_regs.h)와 RX5 하드웨어 설정 기준입니다.

| CSR offset | 내용 |
|---|---|
| `0x00` | CONTROL: bit0 START, bit1 CLEAR(done/error 상태 정리) |
| `0x04` | STATUS: BUSY/DONE/ERROR/CFG_OK, error code |
| `0x08` | CMD: 0=INFER, 1=LOAD |
| `0x0C` | INPUT_ADDR |
| `0x10` | WEIGHT_ADDR |
| `0x14` | OUTPUT_ADDR |
| `0x18` | output_scale의 float32 bits |

CSR base는 `0x43C00000`, DDR 가중치/입력/출력은 각각 `0x3F000000` / `0x3F100000` / `0x3F200000`입니다. `0x3F000000`부터 16MiB를 Device Tree에서 no-map으로 예약합니다. input/weight 주소는 8-byte, output 주소는 32-byte 정렬입니다. CLEAR는 DMA 중단이나 강제 reset 명령이 아닙니다.

새 XSA에서는 주소·RX·버퍼 크기·Device Tree·CSR를 함께 확인합니다. 자세한 설치는 [PS README](../ps/README.md), 웹 API는 [Backend](../pc/backend/README.md), 통합 순서는 [bringup](bringup.md)에 있습니다.
