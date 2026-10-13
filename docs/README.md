# WiSensing 상세 문서 안내

처음 방문했다면 **[메인 README](../README.md)**에서 구현 기능과 전체 시스템을 먼저 확인하세요. 이 폴더에는 **전체 연결 구조, 인터페이스, 실행·검증 절차, 발표 근거**를 주제별로 정리했습니다.

## 어떤 내용을 찾고 있나요?

| 궁금한 내용 | 문서 |
|---|---|
| **전체 시스템에서 CSI가 이동하는 과정** | [시스템 구조](architecture.md) |
| 하드웨어·소프트웨어의 폴더/대표 파일 위치 | [저장소 구조](repository_structure.md) |
| TX/PS/PL/PC 사이 입출력 규격과 AXI CSR | [인터페이스](interface.md) |
| PS ↔ PC TCP 패킷 헤더·페이로드와 재접속 | [PS↔PC 프로토콜](ps_pc_protocol.md) |
| 학습 모델 준비 → FPGA 빌드 → PS → PC 실행 | [통합 실행 순서](bringup.md) |
| Windows에서 Backend·Frontend 함께 실행하기 | [원클릭 실행기](oneclick_launcher.md) |
| 처음 설치한 PC의 구동·RX 배치·관리자 확인 | [운영 가이드](wisensing_live_v18_operator.md) |
| 수행한 시험과 추가 확인 항목 | [통합 점검 기록](reviews/2026-10-07-pc-integration.md) |
| 팀 협업 및 Git 브랜치/PR 사용 방법 | [Git 작업 가이드](git_guide.md) · [팀 기록](members/README.md) |

## 영역별 구현 설명

| 구현 영역 | 상세 README |
|---|---|
| CSI 송신/수집 | [ESP32](../esp32/README.md) · [TX](../esp32/ESP-TX/README.md) · [RX](../esp32/ESP-RX/README.md) |
| FPGA/RTL | [PL](../pl/README.md) · [Pose CNN](../pl/cnn/README.md) · [Ridge IP](../pl/localization/README.md) |
| PS와 소프트웨어 비교판 | [PS](../ps/README.md) · [PS 위치 시험판](../ps_location/README.md) · [PS-only CNN](../ps_onlysw/README.md) |
| AI 학습 | [ML](../ml/README.md) · [Pose](../ml/pose/README.md) · [Location](../ml/localization/README.md) |
| PC 프로그램 | [PC](../pc/README.md) · [Backend](../pc/backend/README.md) · [Frontend](../pc/frontend/README.md) |
| Vivado 하드웨어 패키지 | [Integration](../integration/README.md) |

점검 기록은 **그 날짜·해당 모델/비트스트림 기준의 검증 범위**를 보존합니다. 저장소에서 소스가 변경됐다는 사실과 실제 보드에서 새 버전을 테스트했다는 사실을 혼동하지 마세요.
