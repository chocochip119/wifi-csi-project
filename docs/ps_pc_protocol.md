# PS ↔ PC 통신규격 v1.1

이 문서의 규격 번호는 v1.1이며 **바이트 헤더 version은 2**입니다. `ps/src/wise_server.c`와 `pc/backend/protocol/wise_protocol.py`가 같은 규격을 구현합니다. 기존 UDP WCSI v1 패킷과 호환되지 않습니다.

실행 순서는 [통합 실행](bringup.md), USB·tensor·CSR 경계는 [인터페이스](interface.md), 구현 안내는 [PS](../ps/README.md) / [Backend](../pc/backend/README.md)를 참고하세요.

## 연결과 역할

| 서버 | 클라이언트 | 포트 | 패킷 |
|---|---|---|---|
| PS | PC Backend | TCP 5000 | CSI(1), STATUS(3), ACK(4) |
| PS | PC Backend | TCP 5001 | Pose(2) |
| PC Backend | Frontend | HTTP/WebSocket 8000 기본값 | JSON snapshot 및 API |

PS는 기본 `0.0.0.0`에 바인딩하며 `WISE_TCP_BIND`로 IPv4 주소를 제한할 수 있습니다. 각 포트당 활성 PC 연결 1개를 지원합니다. 이 버전에서 PC는 TCP 5000/5001로 명령을 보내지 않습니다. TX 제어와 3초마다 STATUS 조회는 PS가 담당합니다. `ACK`는 TX USB의 명령 응답을 관찰용으로 전달하는 것이며 TCP 수신확인 메시지가 아닙니다.

TCP는 메시지 경계를 보존하지 않으므로 recv 단위로 파싱하지 않습니다. 24-byte 헤더를 모은 다음 payload_size만큼 읽고, 남은 바이트는 다음 프레임에 사용합니다. 모든 정수와 float32는 **little-endian**, 패딩은 아래에 표시된 바이트만 있습니다.

## 공통 헤더 — 24 bytes

Python 형식: `<4sBBHIIQ`.

| Offset | Bytes | 내용 |
|---|---:|---|
| 0 | 4 | ASCII `WISE` |
| 4 | 1 | version=2 |
| 5 | 1 | type: CSI=1, Pose=2, STATUS=3, ACK=4 |
| 6 | 2 | header_size=24 |
| 8 | 4 | payload_size, 최대 8272 |
| 12 | 4 | sequence, 포트별 송신 프레임 번호, uint32 wrap |
| 16 | 8 | timestamp_us, PS CLOCK_MONOTONIC 마이크로초 |

timestamp_us는 USB 프레임 파싱/Pose 게시 시각이며 Unix 시간이 아닙니다. PC는 연결별 시계 offset으로 자체 perf_counter 축에 대응시킵니다. sequence는 TCP 연결에서 연속되며 재접속 첫 값은 0이라고 가정하지 않습니다.

## CSI — type 1

한 TX USB cycle 전체를 한 TCP 패킷으로 보냅니다. 원본 CSI bytes를 전달하며 Pose용 INT8 입력 tensor를 보내는 것이 아닙니다.

CSI 고정 부분(`<IIBBBBB3x`, 16 bytes):

| Offset | Bytes | 내용 |
|---|---:|---|
| 0 | 4 | trigger_seq |
| 4 | 4 | uart_seq, 원본 TX USB 프레임 헤더 번호 |
| 8 | 1 | active_nodes |
| 9 | 1 | received_nodes, valid 레코드 수 |
| 10 | 1 | rx_count, 레코드 수(0..8), active_nodes와 같음 |
| 11 | 1 | valid_mask, RX id별 bit |
| 12 | 1 | timeout_fired, 0/1 |
| 13 | 3 | 예약, 0 |

이후 rx_count개 레코드가 이어집니다. 각 레코드(`<BBbBHH`, 8 bytes) 뒤에 csi_len bytes가 붙습니다.

| 레코드 Offset | Bytes | 내용 |
|---|---:|---|
| 0 | 1 | rx_id 0..7, 중복 금지 |
| 1 | 1 | valid 0/1 |
| 2 | 1 | rssi signed int8 |
| 3 | 1 | 예약 0 |
| 4 | 2 | csi_len: 짝수, 최대 1024 |
| 6 | 2 | 예약 0 |
| 8 | csi_len | 원본 signed int8 I/Q bytes |

valid=0이면 csi_len=0, valid=1이면 양의 길이입니다. 누락 RX 레코드는 유지하고 CSI bytes를 채워 만들지 않습니다. received_nodes/valid_mask가 레코드와 다르면 거부합니다. 실시간 위치 모델은 이 범용 규격 중 RX 0..4 전부와 384 bytes/RX만 허용합니다.

원본 TX USB cycle payload는 32-byte header와 6-byte RX header를 사용합니다. PS가 checksum 검증 후 위 16+8-byte Ethernet 형식으로 변환합니다. CSI 송신은 PS Pose 윈도우가 완성될 때까지 기다리지 않습니다.

## Pose — type 2, 40 bytes

Python 형식: `<IIIf24b`.

| Offset | Bytes | 내용 |
|---|---:|---|
| 0 | 4 | window_id, PS window_seq의 하위 uint32 |
| 4 | 4 | end_trigger_seq |
| 8 | 4 | infer_us, 현재 PS infer_ms 측정값×1000 |
| 12 | 4 | output_scale, 유한 양수 IEEE-754 binary32 |
| 16 | 24 | signed int8 좌표 12관절×(x,y) |

순서: left/right shoulder, elbow, wrist, hip, knee, ankle. 복원은 `coordinate = int8_value * output_scale`입니다. 부팅 시 로드된 모델/PL이 제공한 scale을 보내며 고정 임의 값을 쓰지 않습니다. 좌표계는 model_output이고 화면의 0..1 좌표계라고 보장하지 않습니다.

## STATUS/ACK — types 3/4

checksum-valid TX USB payload를 그대로 전달합니다. STATUS 고정 header는 `<8B7I6s2s`(44 bytes), node는 `<4B6sIII`(22 bytes), ACK는 `<4BII64s`(76 bytes)입니다.

STATUS의 8개 byte는 mode, Wi-Fi channel, secondary channel, protocol bitmap, connected/active/saved node count, node entry count입니다. 7개 uint32는 timeout_us, udp_slot_gap_us, generation, next_trigger_seq, uart_seq, trigger_sent_count, cycle_timeout_count입니다. 이후 TX MAC 6 bytes와 예약 2 bytes가 옵니다. Node에는 slot/saved/connect order, flags(connected=1, saved=2, live=4), MAC, last_seen_ms, rx_ok, rx_timeout이 들어갑니다.

ACK는 ok, mode, Wi-Fi channel, secondary channel 4 bytes, timeout_us/udp_slot_gap_us uint32, NUL 종료 ASCII message 64 bytes입니다. mode=1이 running, secondary channel=1/2가 above/below입니다.

## 실시간성·재접속

두 포트는 별도 송신 스레드와 64-frame 유한 큐를 사용합니다. USB/CNN 호출은 큐 복사만 수행하며 네트워크 수신을 기다리지 않습니다. 큐가 넘치거나 송신 대기/프레임 나이가 250ms를 넘으면 해당 TCP 연결을 끊고 큐를 비웁니다. 중간 바이트/프레임 일부를 버린 채 같은 스트림을 계속 보내지 않습니다. TCP_NODELAY를 사용하고 Linux가 지원하면 TCP_NOTSENT_LOWAT도 설정합니다.

재접속 시 5초 이내의 cached STATUS를 먼저 보내고 이후 새 데이터를 보냅니다. cached STATUS가 오래되었으면 PS의 다음 STATUS 응답을 기다립니다. PC는 연결 종료에 기존 위치 윈도우/상태를 지우고 새 STATUS로 다시 준비합니다. Pose 수신기는 연결 종료 시 최신 Pose를 지웁니다. 미수신 상태를 사람 없음으로 표시하지 않습니다.

250ms는 사용자 공간 송신 큐/송신 제한이며 물리 네트워크 전체의 최대 지연 보장은 아닙니다. PC는 위치/Pose의 2초 stale 조건도 따로 적용합니다.
