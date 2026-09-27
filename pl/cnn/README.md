# CNN IP RTL — 인계 및 개발 기준

2026-09-27 / 대상 브랜치 `cnn` / Vivado 2020.2 / xc7z020clg400-1.

**S00_AXI·Top FSM·Loader와 수정 M00_AXI, 수정 Encoder, 개발 중 FC 및 검증 자료를 옮긴 상태다.**
현재 코어는 **실물 Top/Loader/Encoder + FC 검증 모형**이며 전체 실물 CNN IP 완성본이 아니다.

먼저 [인계 범위와 모듈 의존관계](docs/handover/01_핵심인계/인계범위와모듈의존관계.md)를 읽는다.
담당 파일만 가져가면 RAM 배치·읽기 지연·START/DONE·FIFO·오류 복구 조건이 빠질 수 있다.

| 경로 | 현재 역할 |
|---|---|
| [rtl](rtl) | S00_AXI, M00_AXI, 13상태 ctrl, Loader/decoder/RAM 4종, pose_cnn 배선 |
| [rtl/CNN_Encoder](rtl/CNN_Encoder) | 사용자 승인으로 반영한 수정 Encoder. 팀 저장소 기존 버전 대비 패치 제공 |
| [rtl/fc_work](rtl/fc_work) | 추가 개발한 FIFO·hidden/pose 버퍼·MAC. 아직 pose_cnn에 결합되지 않음 |
| [testbench](testbench) | 기존 검증 TB·AXI 메모리 모형·FC/Encoder/Loader 모형 |
| [doc/pose_cnn_ctrl_fsm.drawio](doc/pose_cnn_ctrl_fsm.drawio) | 편집 가능한 FSM/ASM 목표 도면 |
| [docs/handover](docs/handover) | 담당 범위·의존관계·Encoder/FC 전달 자료 |
| [docs](docs) | 단계별 기능·타이밍 기록과 텍스트 검증 근거. 과거 절대 경로는 당시 PC 기준 |
| [golden](golden) | 참고 C++ golden 생성 도구 및 현재 기준값 |
| [reference](reference) | Encoder 원본·참고 C++/blob·옛 wrapper 템플릿 |
| [spec](spec) | 원문 인터페이스 명세 XLSX |
| [syn](syn) | 합성/P&R Tcl 및 제약. 기존 구현 결과 기록 |
| [tools](tools/README.md) | 이 저장소 경로에서 실행하는 핵심 회귀/해시 검사 |

## Encoder 반영 및 FC 구분

기존 `rtl/CNN_Encoder`에 우리 검증 수정본을 반영하는 것은 이번 `cnn` 브랜치 업로드에 대해 사용자가 승인했다.
담당 팀원의 최종 채택이나 `main` 병합 완료를 뜻하지 않는다.
[팀 저장소 직전 버전 대비 diff](docs/handover/team_encoder_before_vs_uploaded.diff)와
[수정 이유·검증 범위](docs/handover/02_Encoder_전달자료/전달요약.md)를 함께 검토한다.

`pose_cnn.v`의 `u_fc`는 **testbench/fc_stub.v**다. 실제 FC 연산은 하지 않는다.
`rtl/fc_work`는 이 모형과 별개이며, 팀원의 `rtl/FC` 작업과도 구분한다.
FC 후처리·제어 결합, 전체 pose golden 대조와 실물 통합은 남아 있다.
`reference/CNN_Encoder`와 작업본을 같은 라이브러리로 중복 컴파일하지 않는다.
전체 `rtl` 폴더를 무조건 합성하기보다 tools의 소스 목록과 사용할 top을 명시한다.

## 검증과 남은 조건

- 수정 Encoder: 제공 blob의 샘플/zero 입력에서 flat 384 word 전량 golden 일치 기록(G-02).
- FC MAC/requant: 별도 TB 검증. F-03a는 기능 통과지만 타이밍 기준 미달로 단계 전체 완료가 아님.
- 100 MHz: 측정한 OOC P&R에서 Encoder/FC 모두 미달. 최종 클록·파이프라인·BD/reset 범위는 미확정.
- 이전 문서의 고정/모형 pose와 전체 INFER cycle을 실물 FC 정확도·성능으로 해석하지 않는다.

[확정 계약과 남은 일](docs/handover/01_핵심인계/확정계약과남은일.md),
[업로드 범위·경로 변경](docs/UPLOAD_SCOPE.md), [이번 업로드 검증](docs/UPLOAD_VERIFICATION.md)을 참고한다.

## 재현 시작

저장소 루트에서 Python 3와 Vivado 2020.2로 실행한다.

```powershell
python pl/cnn/tools/verify_sources.py
python pl/cnn/tools/run_checks.py --vivado-bin C:/Xilinx/Vivado/2020.2/bin --suite smoke
```

실행 결과는 `pl/cnn/runs/`에 생성하며 Git에 올리지 않는다. 심화 검증 준비 조건은 [tools 안내](tools/README.md)를 따른다.
