# cnn 브랜치 업로드 범위 — 2026-09-27

핵심 RTL, 수정 Encoder, FC 개발분, TB/모형, draw.io, 인터페이스 명세, 합성 Tcl/XDC,
golden/참고 blob, 인계 설명과 단계별 텍스트 검증 근거를 포함한다.
원본 작업 폴더와 인계 폴더는 수정하지 않는다. 기존 팀 Encoder의 변경 전 상태는 Git 이력과 별도 diff/hash에 남긴다.

## 경로 대응

| 인계본 경로 | 팀 저장소 경로(pl/cnn 기준) |
|---|---|
| project/cnn_rtl/rtl/encoder | rtl/CNN_Encoder — 사용자 승인으로 기존 팀 버전 갱신 |
| project/cnn_rtl/rtl/fc | rtl/fc_work — 팀원 FC 작업과 구분 |
| project/cnn_rtl/rtl 나머지 | rtl |
| project/cnn_rtl/tb | testbench |
| project/cnn_rtl/others/CNN_Encoder | reference/CNN_Encoder |
| project/cnn_rtl/doc, docs, golden, syn | 같은 이름의 폴더 |
| 인계 설명 01/02/03 | docs/handover |
| 원문 인터페이스 XLSX | spec |
| reference HLS/pl_accel_v6 | reference/pl_accel_v6 |

RTL/TB는 인계본과 byte 동일하게 복사한다. 문서 상대 링크와 실행 wrapper의 경로만 이식한다.
검증된 파일 바이트를 유지하기 위해 이 CNN 경로에만 .gitattributes의 -text를 적용했다.
공통 .gitignore는 수정하지 않으며 CNN 하위 규칙에서 필요한 blob/golden 입력과 역사적 텍스트 로그만 예외로 포함한다.
기존 PNG는 팀 문서 이미지 경로 docs/images/cnn/archive로 이동했다. 새 시각화를 만들거나 수정한 작업은 아니다.

## 제외한 생성물

Vivado 캐시/파형/구현 checkpoint, routed_netlist.v, 중복 후보 ZIP 및 중첩 Vitis HLS 자동 생성 프로젝트/export는 Git 업로드에서 제외했다.
[제외 목록](UPLOAD_EXCLUDED.json)에 경로·크기·이유를 남겼다. 전체 산출물은 로컬 인계 폴더에 보존된다.
과거 보고서의 해당 파일 링크 및 절대 PC 경로는 당시 실행 기록이다. 해당 생성물은 필요하면 Tcl로 재생성한다.

## 브랜치 경계

작업 시작 시 cnn HEAD는 ee3a531이고 origin/cnn보다 기존 6개 커밋이 앞서 있었다. 이 이력은 보존한다.
fetch로 확인한 main의 신규 FC FIFO/Flatten 변경은 이번 업로드에서 임의로 병합하지 않는다.
기존 Encoder TB도 수정하지 않는다. main 병합/PR/팀원 최종 채택은 이 업로드와 별도다.
