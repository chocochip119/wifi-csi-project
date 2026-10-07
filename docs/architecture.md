# System Architecture

ESP32 RX 5대의 CSI를 TX Coordinator가 모아 USB로 PS에 전달합니다. PS는 같은 cycle을 두 경로에 사용합니다.

- 자세: PS 전처리 → DDR의 INT8 `[15,128,10]` → FPGA CNN → PS에서 24좌표와 scale 읽기 → TCP 5001 → PC.
- 위치: PS에서 원본 CSI cycle/STATUS/ACK를 TCP 5000으로 전달 → PC의 11클래스 Portable Ridge 실시간 엔진.

PC Backend는 두 입력을 최신 스냅샷으로 합쳐 HTTP/WebSocket으로 제공합니다. 위치/Pose의 유효성은 각각 관리하며 누락·연결 종료·오래된 결과는 unavailable입니다. 프런트엔드와 호흡 통합은 현재 구현에 포함되지 않습니다.

학습/실험은 `ml/`, PC 실행은 `pc/backend/`, 보드 프로그램은 `ps/`, 하드웨어는 `pl/`과 `integration/`에서 관리합니다. 세부 인터페이스는 [interface.md](interface.md)를 참조합니다.

FPGA FC·Encoder·Pool·패키지 IP 소스와 팀 Python의 정수 반올림 계약을 통일했습니다. [INT8 계약과 golden 비교](../ml/pose/INT8.md)를 따라 최종 학습 가중치의 golden을 생성하고, Vivado IP/bitstream을 재빌드한 뒤 실제 보드 출력을 확인해야 합니다. [점검 기록](reviews/2026-10-07-pc-integration.md)에 검증 범위를 기록합니다.
