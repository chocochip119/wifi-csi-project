# pose_cnn_ctrl 목표 FSM / ASM 도면 작성 기록

날짜: 2026-09-24. 사용자 승인 보정 [1]–[5]를 반영한 설계 문서 작업이다.

> 아래 최초 작성 기록은 당시 상태를 보존한다. Claude 검수 이후의 문구 보완·미리보기 갱신 결과와 Notion 추가 기록 초안은 문서 마지막의 「검수 보완 반영」을 참조한다.

## 산출물과 범위

- [편집 가능한 draw.io 파일](D:/2609_final_project/cnn_rtl/doc/pose_cnn_ctrl_fsm.drawio)
- [XML 검증 출력](D:/2609_final_project/cnn_rtl/doc/pose_cnn_ctrl_fsm_validation.txt)
- [XML 검증 스크립트](D:/2609_final_project/cnn_rtl/doc/validate_pose_cnn_ctrl_drawio.py)

`<mxfile>` 아래 각 `<diagram>`에 평문 `<mxGraphModel>`을 넣었다. UTF-8, 줄바꿈 `&#10;`, XML 특수문자 escaping을 사용하며 base64/deflate는 없다. 상태·조건·동작·라벨·선은 모두 개별 편집 가능한 벡터 요소다. 상태명과 출력 라벨은 상태 도형의 자식으로 두어 함께 이동한다.

RTL/TB, 명세 XLSX, `PROJECT_CONTEXT.md`는 수정하지 않았다. 모든 페이지에 다음 범례를 넣었다.

> 목표 설계 도면. 현재 RTL 구현 범위는 PROJECT_CONTEXT.md 8절 참조.

## 페이지 구성과 수량

| 페이지 | 상태 | 상태 간 논리 전이 | 그려진 선분 연결(edge) 수 |
| --- | --- | --- | --- |
| FSM 상태도 | 13개 전체 | 20 | 21 = 상태 전이 20 + reset 진입 화살표 1 |
| ASM - 공통 | IDLE / DECODE / FINISH / ERR_DRAIN: 4 | 7 | 19 |
| ASM - LOAD | LD_RD1 / LD_RD2 / LD_WAIT: 3 | 5 | 19 |
| ASM - INFER | IN_RD / ENC / FC1 / FC2 / FC3 / WR: 6 | 8 | 38 |

ASM의 논리 전이는 **출발 상태가 있는 페이지** 기준이다. IDLE의 `!reg_start` 자기 전이는 공통 ASM에 별도로 표시했으며, FSM 20개에는 포함하지 않는다. 다른 대기 상태의 F 복귀, 조건부 동작으로 이어지는 선, T/F 분기 등은 ASM의 edge 수에 포함된다. 작은 원은 다른 상태로 가는 연결자이며 상태 수에 중복 계산하지 않는다.

상태 코드는 요청 순서대로 `IDLE=0000`부터 `FINISH=1100`까지 4비트를 배정했다. FSM 페이지 아래에 T-01–T-05 매핑을 적었다.

## 보정 반영과 읽는 방법

1. FC1 상태 박스에 `fifo_we = mem_rd_valid && !fifo_full`, `mem_rd_ready = !fifo_full`, `fifo_wdata = mem_rd_data`를 표기했다. IN_RD의 `in_we = mem_rd_valid`와 LOAD의 `ld_valid = mem_rd_valid`는 유지했다.
2. 상태 박스에는 유지되는 레벨·등식을 두었다. snapshot과 1-cycle 시작 펄스는 전이의 둥근 조건 출력 박스에 배치했다. 입력·출력 beat 카운터 초기화와 증가도 조건 동작으로 표현했다.
3. 공통 페이지 오른쪽 아래에 done/error 갱신을 독립 블록으로 두었다. START 해제, CLEAR 해제, FINISH 이탈 에지의 결과 기록, `기록 > 해제`, 이벤트가 없을 때 sticky 유지를 설명했다. R1과 R2가 서로 다른 에지라는 근거도 적었다.
4. read 오류의 ERR_DRAIN 진입은 LD_RD1 / LD_RD2 / IN_RD / FC1 네 곳뿐이다. WR의 write 오류는 완료 후 FINISH로 가며, ENC / FC2 / FC3에는 오류 경로를 추가하지 않았다.
5. D06은 FC1 read 주소 옆과 주석 박스에, D08은 ERR_DRAIN 및 해당 판정·동작·경로에 주황색/점선으로 표시했다. 미결 항목을 확정하지 않았다.

예: 공통 ASM에서 `reg_start`가 참이면 snapshot과 `err_code ← 0`을 수행하며 DECODE로 들어간다. `cmd == 1`이면 Loader/read 시작 펄스를 내고 LD_RD1으로 간다. LOAD 페이지에서 read 완료를 기다리고 두 번째 구간으로 이동한다. 최종 결과는 FINISH를 떠나는 에지에 독립 상태 갱신 블록이 기록한다.

근거는 사용자 제공 원래 작업 명세와 승인 보정, `00_개요` r35–37/r41–46, `04_pose_cnn` r44–49/r91–92, `PROJECT_CONTEXT.md` 5.1절 D02/D03이다. 이번 도면은 전체 목표 설계이며 이전 T-01 임시 동작을 나타내지 않는다.

## 예시 이미지 스타일 반영

- 흰 배경, 가는 검은 윤곽선·화살표, 과도한 면 채움 없이 텍스트 중심으로 구성했다.
- FSM은 원형 상태를 상태명·코드/출력 구역으로 나누고, 전이 조건은 화살표에 적었다.
- ASM은 직사각형 상태, 마름모 판정, 둥근 조건 출력, 원형 연결자, T/F 분기를 사용했다. 상태명은 왼쪽 위, 코드는 오른쪽 위에 있다.
- 예시의 단순한 좌우/상하 흐름을 유지하되, 13개 상태와 오류 경로를 읽을 수 있도록 페이지 크기와 열 배치를 확장했다. 6개 상태가 있는 INFER는 3열 × 2단으로 배치했다.
- FSM 예시의 곡선 화살표를 완전히 복제하지는 않았다. 복잡한 분기와 오류 경로를 구분하기 위해 직선·꺾은선을 사용했다. 단계별 다색 채움보다 예시의 흑백 스타일을 우선했고, D06/D08만 주황색으로 구분했다.
- 상태 박스의 입력 의존 등식은 사용자가 승인한 표기 규칙을 따른다. 이를 모두 순수 Moore 출력이라고 부르지는 않는다.

## 자체 검증 명령과 실제 출력

작업 위치: `D:\2609_final_project`.

```powershell
& 'C:\Users\kccistc\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' 'D:\2609_final_project\cnn_rtl\doc\validate_pose_cnn_ctrl_drawio.py'
```

```text
File: D:\2609_final_project\cnn_rtl\doc\pose_cnn_ctrl_fsm.drawio
Page | states | drawn edge segments | logical inter-state transitions
fsm (FSM 상태도) | 13 | 21 | 20
common (ASM - 공통) | 4 | 19 | 7
load (ASM - LOAD) | 3 | 19 | 5
infer (ASM - INFER) | 6 | 38 | 8
FSM logical transitions: 20 (original numbered items 1, 3-18; item 16 expanded into four arrows; item 2 self-loop omitted).
FSM drawn segments: 21 = 20 inter-state arrows + 1 reset annotation arrow.
ASM logical counts are assigned by source-state ownership; drawn segments include decisions, conditional outputs, and wait paths.
RESULT: PASS (497 checks)
Scope: XML structure and selected content contracts only; visual layout and RTL behavior are reviewed separately.
```

검사 범위: XML 파싱, 비압축 모델, ID 중복, 모든 edge source/target 존재, 상태 수·코드, 20개 전이의 정확한 양 끝점, 고아 상태 없음, D08 점선, 보정된 식, 상태 박스 내부의 시작 펄스/snapshot 부재, 상태 갱신 설명·범례.

별도 좌표 검토에서는 부모-자식 라벨을 제외한 최상위 도형 겹침, 페이지 밖 도형, 관련 없는 상태 박스를 가로지르는 연결을 찾지 못했다. 자체 좌표 미리보기에서 줄바꿈·화살표 공유 구간을 확인하고 일부 글자 크기·경로를 조정했다.

## 시각 확인의 한계

설치된 `C:\Program Files\draw.io\draw.io.exe`의 CLI export를 시도했으나 GPU 초기화와 cache 오류로 PNG가 생성되지 않았다. 숨김으로 실행한 작업용 export 프로세스는 종료했다. **draw.io 앱에서 실제 열기·렌더링에 성공했다고 주장하지 않는다.** 사용자 요청의 XML 수준 확인은 완료했다.

`preview/layout_p1.png`부터 `layout_p4.png`는 XML 좌표를 직접 그린 **배치 점검용 미리보기**다. 실제 draw.io 스크린샷이 아니며, 폰트 줄바꿈·점선 렌더링은 앱과 차이가 있을 수 있다. 편집 원본은 `.drawio` 파일이다.

## 기존 파일 보존

다음 SHA-256은 작업 전후 동일했다.

| 파일 | SHA-256 |
| --- | --- |
| `PROJECT_CONTEXT.md` | `7D664E9E099E5ED071F2E69C616A13D2C7F20D9D8DEE6179188F57627DC3A3D9` |
| `cnn_rtl/rtl/pose_cnn_ctrl.v` | `F208E7654C61C68B455FFAF4F1CA0BBF83CB85A621D5892E95DF2837B448F451` |

## Notion 복사용 요약

```text
단계 / 날짜: Top FSM 목표 ASM·FSM 도면 / 2026-09-24
목표: RTL 상세 구현 전에 13상태의 전체 제어 흐름을 정리.
산출물: cnn_rtl/doc/pose_cnn_ctrl_fsm.drawio, 비압축 XML 4페이지.
핵심: 레벨·등식은 상태 박스, 펄스·레지스터 적재는 전이의 조건 출력 박스.
동작 예: START 수락 → snapshot → DECODE → LOAD/INFER 경로 → FINISH 이탈 시 결과 기록.
보정: FC1 fifo_we에 !fifo_full 반영, START 에지 snapshot, D02는 독립 갱신 표.
검증: XML 497개 조건 통과, 13상태·20전이·참조·고아 상태 검사 완료.
한계: 실제 draw.io 앱 렌더링은 GPU/cache 오류로 미확인; 자체 좌표 미리보기 점검.
미결: D06 FC1 read base, D08 drain/오류 진입. 주황 점선으로 표시.
보존: RTL/TB, XLSX, PROJECT_CONTEXT.md 수정 없음.
상태: 도면 작성·자체 검증 완료. 사용자 확인·Claude 검수 대기. Notion 직접 기록 없음.
추가 정리: 상태 유지 등식과 전이 펄스, 내부 err_code와 표시 status_error의 구분.
다음 후보: 목표 도면 검수 후 T-01을 목표 상태 구조에 맞춰 재작성(별도 요청 시).
```

## 검수 보완 반영 — 2026-09-24

사용자의 수정 요청에 따라 검토에서 확인한 두 문서 항목을 보완했다.

- `PROJECT_CONTEXT.md`와 `build_pose_cnn_ctrl_drawio.py`의 `fc_sel` 설명을 수정하고 `pose_cnn_ctrl_fsm.drawio`를 재생성했다. `08_FC` r12·r45의 원문은 "fc_start에서 latch"다. 시작을 샘플링할 때 올바른 값이 필요하며 이후 값을 유지해도 된다. 예를 들어 FC1 → FC2 전이에서는 `fc_start=1`을 샘플링할 때 `fc_sel=1`이어야 한다. 도면의 전이 박스 표기는 유지한다.
- `PROJECT_CONTEXT.md`의 다음 소단계 후보를 T-01의 13상태 4-bit 골격 재작성으로 맞췄다. T-02는 그 이후의 후보로 남겼다.
- `render_layout_preview.py`로 `preview/layout_p1.png`–`layout_p4.png`를 갱신했다. 오래된 PNG에 대한 `preview/STALE.txt`는 제거하고 현재 생성 방식과 한계를 `preview/README.md`에 기록했다.
- 재생성한 XML은 기존 검증기 497건을 통과했다. 4페이지·13상태·20전이를 유지하며, 변경 영향이 있는 1·4페이지의 좌표 미리보기를 시각 확인했다. 실제 draw.io 앱 렌더링 확인을 뜻하지 않는다.
- 이번 변경은 문서·도면 보완이다. RTL/TB 구현은 진행하지 않았으며 D06·D08은 미결로 유지한다.

Notion에 복사할 추가 기록 초안(직접 기록하지 않음):

```text
단계 ID / 제목 / 날짜: T-00 검수 보완 / 2026-09-24
목표: fc_sel 계약 설명과 다음 작업 안내의 혼동 해소.
핵심 신호: fc_sel은 fc_start 샘플링 시점에 유효해야 하며 이후 값 유지도 허용.
동작 예: FC2 시작을 샘플링할 때 fc_start=1, fc_sel=1.
변경: PROJECT_CONTEXT.md, 도면 생성기·draw.io, PNG 미리보기·안내, 검증 기록.
확인: XML 497건 통과, 4페이지·13상태·20전이 유지, 1·4페이지 좌표 미리보기 확인.
남은 범위: D06·D08 미결, 실제 draw.io 렌더링 미확인. RTL/TB 구현은 별도 단계.
다음 후보: T-01의 13상태 4-bit 골격 재작성(별도 진행 요청 시).
```
