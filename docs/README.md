# 문서 안내

이 문서는 main에 병합된 RX5·PS↔PC TCP·INT8 구성의 탐색 시작점입니다. 프로젝트 개요는 [루트 README](../README.md)를 먼저 읽으세요.

## 용도별 문서

| 확인할 내용 | 문서 |
|---|---|
| 실제 폴더/파일 위치, 원본 RTL과 패키지 IP 관계 | [저장소 구조](repository_structure.md) |
| 수집 → PS/PL → 위치/Pose → PC 흐름 | [시스템 구조](architecture.md) |
| 구간별 인터페이스, tensor/채널 순서, CSR | [인터페이스](interface.md) |
| TCP 헤더·페이로드·송신 큐·재접속 | [PS↔PC 규격 v1.1 / wire v2](ps_pc_protocol.md) |
| 학습/export → FPGA 빌드 → PS → Backend 실행 순서 | [통합 실행](bringup.md) |
| 브랜치·commit·push·PR·main 반영 | [Git 작업 가이드](git_guide.md) |
| 실제로 실행한 테스트와 미검증 항목 | [2026-10-07 점검](reviews/2026-10-07-pc-integration.md) |
| 팀원별 기록 템플릿 | [팀원 기록](members/README.md) |

## 영역별 안내

[ESP32](../esp32/README.md) · [PL](../pl/README.md) · [PS](../ps/README.md) · [ML](../ml/README.md) · [PC](../pc/README.md) · [Integration](../integration/README.md)

날짜가 붙은 점검 기록과 2026-09-30 보드 기록은 당시 검증 범위를 보존합니다. 최신 소스가 과거 XSA/bitstream·시험용 기대 출력에 적용됐다는 뜻은 아닙니다. 현재 동작 계약은 코드와 최신 규격 문서를 함께 확인하세요.
