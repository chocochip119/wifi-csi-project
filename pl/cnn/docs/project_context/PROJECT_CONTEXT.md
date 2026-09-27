# CNN RTL 공통 작업 기준

갱신: 2026-09-25. **Claude의 전체 설계·통합 관리 + Codex의 소단계 구현 + 사용자 이해·확인·Notion 기록 후 다음 단계 진행**을 사용자 확정 작업 방식으로 유지한다. **T-05 FC1 및 D06 load_base_reg 구현, P7/P9 보정 답변 대기 — 단계 전체 완료 아님.** 신규 통합 11조건·14 INFER 및 기존 회귀 12 TB 통과. 별도 무수정 `tb_top_infer`는 FC 출력 0 가정과 충돌해 실패했다. 오류 뒤 FC 재START 복구 방식도 미결이다. **WNS +1.408 ns로 T-04보다 0.326 ns 감소**. D06 확정, D08 미결, T-06 미착수(8절).

## 1. 문서의 우선순위와 현재 상태

- 최신 사용자 지시를 우선한다. 아래 **사용자 확정**, **명세 기준**, **권장안·미결**을 구분한다. 권장안을 팀 합의나 구현 완료로 취급하지 않는다.
- **시각화 산출물 형식 — 2026-09-27 사용자 확정:** 앞으로 이 프로젝트의 시각화는 GIF 파일을 해당 작업 결과 폴더에 별도 저장하고 링크 또는 미리보기를 제공한다. 새 대화에도 적용하며, 대화 시각화·HTML만으로 대체하지 않는다. 상세는 `AGENTS.md`의 시각화 산출물 규칙을 따른다.
- 착수 조사와 배경은 [CNN_RTL_착수_인계.md](CNN_RTL_착수_인계.md)를 재사용한다. 전체 자료를 반복 분석하지 않고 변경에 필요한 원문만 확인한다.
- 이번 상세 설계는 [S00_AXI_CSR_DESIGN.md](S00_AXI_CSR_DESIGN.md)에 있다. 결정 항목 ID는 본 문서 5절을 기준으로 추적한다.
- 작업 루트는 `D:\2609_final_project`. 최초 착수 때 없었던 `AGENTS.md`, `CLAUDE.md`, `PROJECT_CONTEXT.md`와 CSR 상세 설계 문서가 이후 작성되어 현재 존재한다.
- 최초 조사 당시 Git 메타데이터가 없었다. 현재 변경 관리 상태는 실제 착수 시 확인하고 기존 사용자 변경을 보존한다. 이번에는 기존 작업 지침·인계·CSR 설계 문서의 역할 및 진행 규칙만 갱신하고, 명세 XLSX·wrapper·참고 원본과 D01–D10의 기술 결정은 바꾸지 않는다.
- 자체 IP 자료 경로: `D:\2609_final_project\IP_v1_0\IP_v1_0`. 명세·블록도·기존 `rtl_template\pose_cnn_v1_0.v` wrapper를 참조하는 위치이며, 신규 RTL/TB 작업은 이 폴더 안에서 하지 않는다.
- 통합 개발 폴더(2026-09-24 사용자 지시): `D:\2609_final_project\cnn_rtl`. 내부 `rtl\`에는 합성 RTL, `tb\`에는 testbench, `vivado\`에는 향후 Vivado 프로젝트와 생성 파일을 둔다. 기존 S00-02 두 파일은 각각 `cnn_rtl\rtl\pose_cnn_v1_0_S00_AXI.v`, `cnn_rtl\tb\tb_s00_axi_write.v`로 내용 변경 없이 이동했다. 현재 `vivado\`는 빈 폴더이며 Vivado 프로젝트 생성이나 다음 단계 구현은 하지 않았다.

## 2. 사용자 확정 방향과 역할

- 기존 HLS CNN 가속기를 직접 작성한 Verilog RTL로 대체한다.
- `D:\2609_final_project\wifi-csi-pose-main`은 다운로드한 GitHub 참고 원본이다. **직접 수정하지 않는다.** PS 담당이 새 작업 경로에서 참고 흐름을 재사용한다.
- PS의 수집·전처리·실행 흐름은 최대한 유지한다. 새 CSR, DDR 출력 형식 등 변경 접점은 한림/민영이 협의한다.
- 다른 담당자의 내부 구현이나 공통 인터페이스를 임의로 바꾸지 않는다.

| 담당 | 범위 |
| --- | --- |
| 동우 | Encoder, 입력/fmap 버퍼, Conv MAC, Pool |
| 지원 | FC, Flatten, FIFO/Hidden/pose 버퍼, 공통 Requant/GELU 모듈 |
| 한림 | S00_AXI CSR, Top FSM, Weight/Param Loader와 상주 RAM, 코어 연결 |
| 민영 | M00_AXI burst 엔진, IP 패키징, Vivado BD, PS, Python golden |
| 사용자·담당 팀원 | 목표·공통 인터페이스 최종 결정, 현재 단계 이해·확인, 다음 단계 진행 요청 |
| Claude Code | 전체 설계 방향·통합 기준 관리, 작은 단계 분할과 작업 명세, 변경분 검수 |
| Codex/Work | 합의된 소단계의 상세 구현·필요한 최소 검증, 코드 설명·Notion 요약, 검수 반영 |

같은 파일을 두 도구가 동시에 수정하지 않는다. 설계 결정의 공통 기준은 이 문서이며 구체적인 CSR 동작은 상세 설계 문서를 함께 참조한다. Claude의 제안을 자동 확정하지 않고, Codex도 구현 중 합성·자원·타이밍·인터페이스 문제를 발견하면 근거와 대안을 제시한다. 검수 결과는 파일·위치·원인·영향 중심으로 기록하고, 수정 뒤에는 영향받은 부분만 재검사한다.

기본 작업 단위는 사용자가 설명을 듣고 판단할 수 있는 소단계 하나다. 그 단계의 구현·설명·확인·Notion 정리 후 사용자의 다음 단계 요청을 기다린다. 전체 모듈이나 전체 IP 완성을 한 번에 자동 진행하지 않는다. 세부 진행 규칙은 7절을 따른다.

## 3. 현재 명세 기준 — 변경 합의 전 유지

원문: `IP_v1_0\IP_v1_0\interface_spec\Pose_CNN_IP_Interface_Spec.xlsx`, v2.2, 2026-09-23.

- CSR는 32-bit 데이터, 5-bit byte offset, 8개 word다. COMMAND=0 INFER, 1 LOAD, 그 밖의 값은 START 시 BAD_CMD다.
- START/CLEAR_STATUS는 1-cycle pulse다. busy 중 START 및 COMMAND/주소 쓰기는 SLVERR, CLEAR 단독은 허용한다. RO 쓰기는 무시하고 OKAY다.
- Top FSM이 busy와 sticky done/error를 제공하고, Loader가 cfg_ok와 output_scale_bits를 제공한다. S00는 상태 저장소를 중복으로 만들지 않는다.
- done은 CLEAR_STATUS 또는 새 START에서 해제한다. error의 새 START 처리 및 같은 cycle 이벤트 우선순위는 5절의 미결 항목이다.
- 입력 `9×128×10 = 11,520 B`, 출력 **현재 기준** INT8 pose 24개 = 24 B다. 위치 2출력 제안은 채택된 것으로 기록하지 않는다.
- INPUT/WEIGHT_ADDR는 8 B 정렬, OUTPUT_ADDR는 32 B 정렬이다. 실제 정렬 위반을 어느 시점에 어떤 응답으로 거부할지는 미결이다.
- OUTPUT_SCALE_BITS는 blob header word4의 float32 비트다. cfg_ok=0 읽기는 0 + SLVERR다. STATUS 읽기에는 clear 부작용이 없다.
- 단일 `s00_axi_aclk`, **동기식 active-low reset**을 공통 기준으로 한다(2026-09-25 사용자 확정, 기존 비동기 assert 계약 대체). wrapper의 M00도 S00 clock/reset에 연결된다. 공통 reset 생성·공급 조건과 기존 구현 반영 상태는 5.2절을 따른다.
- 내부 RAM 읽기는 고정 1-cycle, 쓰기는 we/addr/data 계약이다. 전체 RAM을 reset으로 지우지 않는다.
- LOAD는 상주 구간만 두 번 읽는다: 상대 offset 0에서 5,936 B, 399,152에서 23,840 B. FC1 weight 393,216 B는 INFER마다 공급한다. 상세 주소 분석은 인계 문서를 재사용한다.
- INFER 성공 done은 출력의 마지막 AXI B 응답까지 완료된 뒤에만 발생한다. 오류가 난 메모리 명령도 끝까지 처리한 뒤 idle로 복귀한다. drain/재시작 세부 계약은 미결이다.

## 4. 코드 작성·검증 규칙

- 수업 스타일 근거: `D:\잡다한거\ondeviceAI2\ondeviceAI2\UART\UART.srcs\sources_1\new\uart.v:73–108`, `20260504_Project2_uart_fifo_sensor_timer\source\top_control_unit.v:25–60,154–161`, 같은 폴더 `stopwatch_datapath.v:101–119`.
- 상태는 폭을 명시한 localparam, 현재/다음은 `*_reg/*_next`로 분리한다.
- 순차 블록은 상승 에지와 nonblocking `<=`, 조합 블록은 `always @(*)`와 blocking `=`를 사용한다. 조합 시작에 유지값/출력 기본값을 두고 불법 상태 복구를 명시한다.
- reset은 **동기식 active-low**로 작성한다(2026-09-25 사용자 확정). 순차 sensitivity는 `always @(posedge clk)`이며, 그 안에서 `if (!rst_n)`으로 초기화한다. S00/M00에서는 해당 `*_ACLK`와 `*_ARESETN` 이름을 사용하며 원리는 같다. reset 공급원의 동기화·유지 시간은 공통 경계에서 보장한다(5.2절). RAM 전체 reset은 하지 않는다.
- **코드 구분과 문법 규칙 (2026-09-24 사용자 갱신).** 이전의 "합성 RTL에서 `for/task/function` 일괄 금지"를 아래로 대체한다.
  - **템플릿 인프라 코드**: Xilinx AXI 템플릿에서 온 부분(`pose_cnn_v1_0_S00_AXI` / `pose_cnn_v1_0_M00_AXI`의 AXI 채널 handshake·응답·byte lane 처리 등)은 템플릿을 **최대한 그대로 활용한다**. 템플릿 안의 `for`/`genvar`/`generate`를 일부러 풀어쓰지 않는다.
  - **직접 설계 RTL**: 템플릿 안에 새로 넣는 사용자 로직(CSR 사용자 영역, Loader/Blob Decoder, 상주 RAM, Top FSM, 코어 연결)은 **합성 불가능한 문법을 쓰지 않는 것**이 기준이다. 금지 예: 지연(`#`), 합성 대상 모듈의 `initial`, 가변/비정적 루프 경계, 동적 배열, 합성 불가 시스템 태스크, 내부 tri-state, 래치를 만드는 불완전 조합 대입, RAM 배열 전체 reset.
  - **testbench**: 문법 제약 없음.
  - **직접 설계 RTL의 반복 표현 (2026-09-24 사용자 확정)**: 상수 경계 `for`도 **쓰지 않는다**. 합성은 가능하지만, 스타일 혼재를 막고 생성되는 회로가 코드에 그대로 보이도록 **명시적 나열**로 작성한다. 예: WSTRB byte lane은 `[7:0]`, `[15:8]`, `[23:16]`, `[31:24]`를 각각 적는다. `task`/`function`도 기존 규칙대로 직접 설계 RTL에서는 쓰지 않는다(이번에 별도로 완화하지 않음).
- signedness, 중간 연산 폭, RAM 읽기 지연을 명시하고 래치·내부 tri-state·RAM 전체 reset을 피한다.
- 변경에 필요한 최소 검증만 한다. CSR에는 소형 TB, Loader에는 blob 경계/내용/오류 확인, Top에는 모형 블록 기반 흐름 검증을 사용한다. 작은 편집마다 전체 합성·전체 회귀를 반복하지 않는다.

## 5. 권장안과 미결 결정 목록

**D01–D05는 2026-09-24 확정되었다** (사용자 위임으로 Claude 작성 → Codex 보완 → 사용자 승인). 확정 동작은 5.1절에 있다. **D06은 2026-09-25 LOAD base 보관으로 확정**(5.3절), **D07의 reset 방식은 동기식 active-low로 확정**했으며 생성·공급 구현 책임은 미결이다. D08·D09 및 D10의 클록·최종 출력은 미합의다. 이미 명세에 있는 주소·비트·RO 쓰기·busy 거부·정렬 요구는 재결정 대상이 아니다.

| ID | 결정할 내용 | 권장안 | 협의/시점 |
| --- | --- | --- | --- |
| D01 | START+CLEAR 동시 쓰기 | **확정** — idle은 두 pulse, busy는 쓰기 전체 SLVERR + 두 pulse 모두 억제 (원자성) | 2026-09-24 확정. 5.1절 |
| D02 | CLEAR/새 START와 완료·오류 경합, 새 START의 error 해제 | **확정** — 수락된 START이 이전 done/error 해제. 같은 START의 새 오류는 해제에 덮이지 않음(해제→기록). 경합은 새 오류 > 새 완료 > 해제 | 2026-09-24 확정. 5.1절 |
| D03 | 쓰기 판정과 읽기 관찰 시점, START 전달 공백 | **확정** — commit cycle에 판정 확정·저장(B 대기 중 BRESP 불변). 읽기는 AR 수락 시 snapshot. Top은 reg_start 다음 에지에 설정 저장+busy=1, 즉시 종료도 busy 최소 1 cycle | 2026-09-24 확정. 5.1절 |
| D04 | CSR 주소 및 DDR 주소 값의 정렬 위반 처리 | **확정** — CSR 접근은 AWADDR/ARADDR 하위 2비트를 **무시**(SLVERR 아님, 초안 권장안 반전). DDR 주소 값은 병합 후보 검사 후 위반 시 쓰기 전체 취소+SLVERR | 2026-09-24 확정. 5.1절 |
| D05 | 0 WSTRB, CONTROL 예약 bit, 거부 조건 우선순위 | **확정** — idle의 0 strobe는 무변화+OKAY, busy의 설정 쓰기는 strobe 무관 SLVERR, 예약 bit 무시. 판정 순서는 5.1절 7줄 표 | 2026-09-24 확정. 5.1절 |
| D06 | LOAD 후 WEIGHT_ADDR 변경과 모델 일관성 | **2026-09-25 사용자 확정: loaded-base 보관(옵션 B).** Top FSM이 `load_base_reg`를 두고 FC1 read에 쓴다. 5.3절 참조 | **확정** |
| D07 | reset 방식 및 공통 생성·공급 책임 | **방식 확정: 동기식 active-low**(2026-09-25 사용자 결정). BD 공통 reset에서 클록에 맞춘 공급과 유지 시간을 보장하는 안을 권장. wrapper에 동기화 회로가 있다고 가정하지 않음 | 생성 위치·유지 시간·담당 구현은 한림/민영이 BD/통합 전 결정. 5.2절 |
| D08 | 오류 drain, cfg_ok 무효화, FIFO 복구, 복수 오류 우선순위 | **2026-09-26 사용자 확정 (Codex 보완 반영).** ERR_DRAIN 별도 상태 / RD_FAULT 갇힘 인정 · PS 타임아웃 · **reset 범위는 BD 통합에서 검증** / **복구는 실행 오류(3·4·5)에만 reset, 요청 거부(1·2)는 재요청**. 5.4절 참조 | **확정** |
| D09 | Param/LUT 공유 읽기 포트 선택 | **2026-09-26 사용자 확정 (안 C).** Top FSM 이 `param_sel_fc` / `lut_sel_fc` 를 만들어 Loader 에 준다. 5.5절 참조 | **확정** |
| D10 | 실제 보드·목표 클록·최종 출력 | **보드 확정 (2026-09-25 사용자): Zybo Z7-20 = XC7Z020-1CLG400C.** 합성 파트는 `xc7z020clg400-1`. 명세의 XC7Z010 기재는 이 결정으로 대체된다. 클록·최종 출력은 여전히 미결이며 pose 24개 기준 유지 | 전원, 자원 검토/출력 변경 전 |

### 5.1 D01–D05 확정 동작 (2026-09-24)

PS 작업 착수 전이므로 한림이 동작을 정하고 PS가 이에 맞춘다. 민영에게는 질의가 아니라 **구현 규격**으로 전달한다. 명세 XLSX와 CSR 선 11개·주소 맵은 바꾸지 않는다.

**원칙.** SLVERR는 명세(`02_S00_AXI` r48/r65)대로 구현하되, 정상 PS 흐름에서는 발생하지 않도록 PS 시퀀스를 규격으로 정한다. SLVERR는 PS에게 상황을 알리는 수단이 아니라 비상 정지다. PS에게 알릴 실행 결과는 `STATUS`의 `error_code`로 간다.

**D02 — 상태 해제와 경합**

- R1. 수락된 START는 그 시점의 `status_done` / `status_error`를 0으로 만든다.
- R2. 같은 START이 즉시 오류를 내면(BAD_CMD / NO_CFG) 그 새 오류를 기록한다. R1의 해제가 R2의 기록을 덮지 않는다. 순서는 해제 → 기록이다.
- R3. `CLEAR_STATUS`는 표시만 0으로 만든다. 실행을 중단하지 않고 내부 실패 기록을 없애지 않는다. 진행 중이던 실행이 끝나면 그 결과가 다시 기록된다.
- R4. 같은 cycle 경합 우선순위: 새 오류 > 새 완료 > 해제(START/CLEAR).
- 근거: 새 실행 결과를 이전 실행과 구분하는 가장 단순한 방법이다. 명시적 CLEAR 방식도 가능하나 PS 코드가 복잡해진다.

**D03 — 저장 시점과 busy 발생 시점**

두 기능의 목적을 구분한다. START 때 command/주소를 저장하는 것은 실행 중 사용할 설정을 고정하기 위함이고, busy 중 거부는 실행 중 PS의 설정 변경·재시작을 차단하기 위함이다. 후자는 전자를 보호하려는 것이 아니다.

- R1. Top FSM은 수락된 `reg_start`의 다음 상승 에지에 `reg_cmd`/`reg_*_addr`를 저장하고 `status_busy`=1로 만든다.
- R2. BAD_CMD / NO_CFG처럼 즉시 종료하는 경우에도 busy를 최소 1 cycle 유지한다. Top FSM의 상태 전이를 일정하게 만들고 CSR이 일관된 신호를 보게 하려는 것이며, PS가 이 짧은 busy를 관찰해야 한다는 뜻이 아니다.
- R2-1. **이중 START을 막는 것은 R2가 아니라 R1이다** (2026-09-24 정정). 판정은 commit cycle의 busy를 본다. 실행이 2 cycle 이상 지속되면 가장 빠른 두 번째 commit이 busy=1을 보고 거부된다(파형으로 확인). 실행이 1 cycle로 끝나면 두 번째 commit 시점에 이미 busy=0이고, 이때 수락하는 것이 맞다 — 이전 실행이 이미 끝났으므로 새 실행이다. 검증할 성질은 "가장 빠른 두 번째 START은 항상 거부된다"가 아니라 **"busy=1인 상태에서 commit되는 START은 예외 없이 거부된다"** 이다.
- R3. CSR 쓰기 판정(busy·정렬·펄스·BRESP)은 commit cycle 한 점에서 하고 결과를 레지스터에 저장한다. B 응답 대기 중 busy가 바뀌어도 BRESP는 변하지 않는다.
- R4. 읽기는 AR 수락 cycle에 RDATA/RRESP를 레지스터에 넣는다. 같은 edge에 상태가 바뀌면 갱신 전 값을 반환한다.

**D01 / D04 / D05**

- D01: idle이면 START·CLEAR 두 pulse 모두 발생. busy이면 쓰기 전체 SLVERR이고 두 pulse 모두 억제한다(원자성).
- D04(a): 쓰기 `AWADDR[1:0]`과 읽기 `ARADDR[1:0]`을 **모두 무시**하고 `addr[4:2]`로 word를 고른다. SLVERR가 아니다. AXI4-Lite에서 주소는 word를 가리키고 byte 선택은 WSTRB가 하므로, 마스터가 byte 주소를 보내든 word 주소를 보내든 같은 결과가 되는 것이 올바른 해석이다. 읽기는 byte 선택 개념이 없어 항상 32bit 전체를 반환한다. (설계 초안의 SLVERR 권장안을 반전한 항목이다.)
- D04(b): DDR 주소 값은 기존값과 WSTRB를 병합한 **후보**를 검사한다. `0x0C`/`0x10`은 후보`[2:0]`, `0x14`는 후보`[4:0]`가 0이 아니면 쓰기 전체 취소 + SLVERR. `0x08`은 검사하지 않는다. 하위 비트를 강제로 0으로 만들지 않는다.
- D05: `WSTRB=0`은 idle에서 무변화 + OKAY. busy 중 `0x08~0x14`는 strobe와 무관하게 SLVERR. CONTROL은 `wstrb[0]=0`이면 펄스 없음 + OKAY. CONTROL 예약 bit `[31:2]`는 무시한다.

**쓰기 응답 판정 순서** (위에서부터 먼저 맞는 줄이 이긴다. 결과는 commit cycle에 확정·저장한다.)

| # | 조건 | 결과 |
| :-: | --- | --- |
| 1 | 0x04 / 0x18 / 0x1C | 무시 + OKAY. busy·WSTRB 무관 |
| 2 | 0x00, `wstrb[0]=0` | 펄스 없음 + OKAY. busy 무관 |
| 3 | 0x00, `wstrb[0]=1 && wdata[0]=1 && busy=1` | SLVERR. 두 pulse 모두 억제 |
| 4 | 0x00, 그 외 | 유효 pulse + OKAY |
| 5 | 0x08~0x14, busy=1 | SLVERR. 값 미반영. WSTRB 무관 |
| 6 | 0x0C / 0x10 / 0x14, busy=0, 병합 후보 정렬 위반 | SLVERR. 값 전체 보존 |
| 7 | 0x08~0x14, busy=0, 그 외 | 병합 반영 + OKAY |

**읽기 응답** (AR 수락 cycle에 확정·저장)

| `addr[4:2]` | 반환값 | RRESP |
| :-: | --- | --- |
| 0 (0x00) | 0 | OKAY |
| 1 (0x04) | `{24'b0, status_error[3:0], cfg_ok, \|status_error, status_done, status_busy}` | OKAY |
| 2~5 (0x08~0x14) | 저장된 값 | OKAY |
| 6 (0x18) | `cfg_ok=1`이면 `output_scale_bits`, `cfg_ok=0`이면 0 | OKAY / SLVERR |
| 7 (0x1C) | 0 | OKAY |

**PS 시퀀스 규격 (민영 전달용)**

1. 모든 CSR 접근은 32bit 단위. byte/half 접근 금지. `reg_write_u64`는 사용하지 않는다.
2. COMMAND / 주소 쓰기는 `busy==0`일 때만.
3. START 쓰기도 `busy==0`일 때만.
4. CLEAR_STATUS도 `busy==0`일 때만.
5. START과 CLEAR를 한 번의 쓰기에 섞지 않는다.
6. DDR 주소는 INPUT/WEIGHT 8 B, OUTPUT 32 B 정렬. 현재 기본값(`0x1E000000` / `0x1E020000` / `0x1E090000`)은 16 KB 정렬이라 이미 충족한다.
7. `OUTPUT_SCALE_BITS`(0x18)는 `cfg_ok==1`을 확인한 뒤에만 읽는다.
8. 표준 시퀀스: (오류 복구 시에만) CLEAR → COMMAND·주소 쓰기 → START → STATUS 폴링. **종료 조건은 `busy==0 && (done==1 || error==1)`이며 timeout을 둔다.** 다음 START는 `busy==0` 이후에만 한다. 오류를 표시한 뒤에도 남은 AXI 응답 처리 동안 busy가 유지될 수 있으므로 done/error만 보고 다음 START를 내면 안 된다.

**남은 위험(기록만).** `cfg_ok=0`에서 0x18 읽기 SLVERR는 PS에서 SIGBUS로 나타날 수 있다. PS 규칙 7로 막는다. 민영이 SLVERR를 쓸 수 없다고 판단하면 0x18을 0 + OKAY로 바꾸는 대안이 있으나 이는 **명세 변경**이므로 그때 팀 협의를 거친다.


### 5.2 동기식 active-low reset 확정 (2026-09-25)

- **사용자 결정:** 동우의 Encoder 방식에 맞춰 공통 reset을 동기식 active-low로 통일한다. `rst_n=0`인 상승 에지에 제어 상태·카운터·valid를 초기화하고, `rst_n=1`인 상승 에지부터 정상 동작한다. 앞선 Encoder 검토의 "비동기 assert 계약 불일치"는 이 결정으로 해소된다.
- **공급 조건:** 동기식 reset에는 동작 중인 클록이 필요하다. reset 입력은 해당 클록의 타이밍을 만족하도록 공급하고, 모든 대상 블록이 reset을 샘플링할 수 있도록 유지한다. 외부 비동기 reset 원천의 동기화, 연결 IP가 요구하는 유지 시간, 생성 위치는 D07의 남은 통합 항목이다.
- **AXI 호환:** AXI는 동기식 active-low 구현과 양립한다. reset 해제는 ACLK에 동기화하고, reset 중 master의 ARVALID/AWVALID/WVALID 및 slave의 RVALID/BVALID를 0으로 유지해야 한다. master VALID의 재상승은 ARESETn이 HIGH인 뒤의 상승 에지부터 가능하다. 근거: [Arm AXI 규격 A3.1.2](https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/IHI0022H_amba_axi_protocol_spec.pdf). 연결된 AXI 경계의 reset 범위·겹침은 [AMD AXI Interconnect reset 조건](https://docs.amd.com/r/en-US/pg059-axi-interconnect/Resets)을 함께 따른다. 진행 중 전송의 reset 복구는 D08에서 별도로 다룬다.
- **RAM:** 내용 전체를 reset하지 않는 기존 방침은 유지한다.
- **반영 상태:** Encoder와 T-01R Top에 이어 R-01에서 S00/M00도 동기식 active-low로 변경했다. M00 단일 원본은 `cnn_rtl/rtl/pose_cnn_v1_0_M00_AXI.v`이며 루트 사본은 없다. AXI VALID의 reset 중 0을 유지하도록 지정된 게이트 4개만 추가했다. 신규 reset 검사와 기존 6TB가 모두 통과했다. 최초 실패했던 `tb_s00_axi_regs`와 `tb_s00_axi_ctrl`은 사용자 후속 요청에 따라 기대값을 유지하고 초기화 검사만 상승 에지 뒤로 옮겨 재실행했다. 기존 XLSX·CSR 상세 설계·인계 문서 갱신 및 D07 reset 공급 조건은 별도 범위다.

### 5.3 D06 확정 — FC1 weight read base (2026-09-25)

- **사용자 결정:** 옵션 B, **loaded-base 보관**. Top FSM이 32-bit `load_base_reg`를 갖는다.
- **적재 시점:** `DECODE → LD_RD1` 전이에서 `weight_addr_reg`를 적재한다. 같은 전이가 LOAD 첫 read를 `weight_addr_reg` 기준으로 발행하므로, **LOAD에 실제로 쓴 값과 저장값이 구조적으로 같다**.
- **사용:** INFER의 FC1 weight read는 `load_base_reg + 5,936` (393,216 B)를 쓴다. 현재 `reg_weight_addr` / `weight_addr_reg`를 **보지 않는다**. LOAD 자신의 두 read는 종전대로 `weight_addr_reg + 0` / `+ 399,152`를 쓴다(같은 명령 안이라 두 값이 동일하다).
- **무효 상태 보호:** LOAD가 실패하면 `cfg_ok = 0`이고 INFER은 DECODE에서 NO_CFG(2)로 거부된다. 따라서 `load_base_reg`가 무효인 채로 소비되는 경로가 없다. 별도 유효 비트를 두지 않는다.
- **reset:** `load_base_reg <= 32'b0`.
- **PS 계약(완화):** WEIGHT_ADDR은 **LOAD의 START 에지에만** 유효하면 된다. LOAD 이후 값이 바뀌어도 INFER은 영향받지 않는다. 기존 "PS는 주소 변경 뒤 반드시 LOAD 성공을 거쳐 INFER" 규칙은 유지되며, 이제 **하드웨어가 강제한다**. 민영에게는 협의가 아니라 통보한다 — PS 쪽 요구가 줄어드는 방향이다.
- **기각한 안(A, 현재 snapshot 사용)의 근거:** LOAD 후 WEIGHT_ADDR이 바뀌면 상주 RAM과 `cfg_ok`는 유효한데 **FC1 weight만 엉뚱한 주소에서 읽혀 오류 표시 없이 틀린 pose가 나온다**. A가 주는 "유연성"은 blob이 이동하면 어차피 재LOAD가 필요하므로 실효가 없고, 불일치 상태를 만드는 통로로만 작동한다. B의 비용은 32 FF다.
- **도면:** `pose_cnn_ctrl_fsm.drawio`의 D06 확정 표시와 ENC → FC1의 `load_base_reg + 5,936` 반영을 T-05에서 확인했다. 이번 작업에서 도면을 다시 수정하지 않았다.

### 5.4 D08 확정 — 오류 처리와 복구 (2026-09-26)

T-02d·T-03·T-04·T-05·T-06 의 실측(8절 D08 입력 ①–⑦, T-06 Q6)을 근거로 사용자가 확정했다.

**① ERR_DRAIN 을 별도 상태로 둔다.**
현재 `LD_RD1` / `LD_RD2` / `IN_RD` / `FC1` 네 곳에 반복된 제자리 drain 을 도면의 `ERR_DRAIN`(4'b1011) 하나로 모은다. 상태 등식은 `status_busy=1`, `mem_rd_ready=1`(받아서 버림), `ld_valid = in_we = fifo_we = 0`(소비 블록 구동 중지), start 계열 전부 0. 탈출은 `!mem_rd_busy && !mem_wr_busy` → `FINISH`. 진입 시 이미 보관된 `err_code` 를 덮어쓰지 않는다. **`WR` 오류는 ERR_DRAIN 으로 가지 않는다** — write 는 `mem_wr_ready` 가 M00→Top 방향이라 Top 이 멈출 수 있는 것이 없고, M00 이 남은 burst 와 B 를 스스로 끝낸다(T-02d ①). busy 하강 후 `err_code ← 5` 를 기록하고 FINISH 로 간다.

**①-보강 (2026-09-26 Codex 지적 반영):** **오류를 발견한 그 cycle 부터** 소비 블록 쓰기를 차단해야 한다. `ERR_DRAIN` 에 들어간 *다음* cycle 부터 막으면 beat 하나가 더 전달된다. 즉 오류 판정 분기 안에서 `ld_valid`/`in_we`/`fifo_we` 를 0 으로 눌러야 하며, `ERR_DRAIN` 상태 등식만으로는 부족하다. (T-03~T-06 의 제자리 drain 구현은 이미 그렇게 되어 있다. ERR_DRAIN 으로 옮길 때 놓치기 쉬운 지점이다.) 별개로, **오류 beat 자체는 이미 기록된 뒤**라는 점은 그대로다 — `mem_rd_err` 은 M00 에서 등록되어 나쁜 beat 수락 다음 cycle 에 올라간다(T-04 검수 기록).

**② `RD_FAULT` 에 갇히는 것을 인정한다.**
`RLAST` 불일치 시 M00 의 `RD_FAULT`(M00 234행)는 빠져나올 수 없고 `mem_rd_busy` 가 영구히 1 이다(T-02d ③, 2,000 cycle 실측). 따라서 ERR_DRAIN 의 탈출 조건이 영원히 성립하지 않는다. **Top FSM 에 타임아웃을 넣지 않는다** — M00 이 갇혀 있어 어차피 다음 명령이 불가능하므로 실익이 없다. **PS 가 STATUS 의 busy 를 타임아웃으로 판단해 공통 reset 을 건다.** 근거: `RLAST` 불일치는 슬레이브가 AXI 규격을 어겨야 발생하며 Zynq DDR 컨트롤러에서는 사실상 일어나지 않는다. M00 에 탈출구를 추가하는 안은 일어나지 않을 사건에 대한 비용이므로 채택하지 않는다.

**②-보강 (2026-09-26 Codex 지적 반영) — 두 가지를 빠뜨렸었다.**
- **reset 범위가 미정이다.** 시뮬레이션에서 확인한 것은 Top·M00·메모리 모형을 **함께** reset 한 경우다. 실제 보드에서 Top/M00 만 reset 하면 AXI Interconnect 에 이전 거래가 남을 수 있고, AMD 는 Interconnect 의 **부분 reset 을 지원하지 않는다**고 명시한다([PG059 Resets](https://docs.amd.com/r/en-US/pg059-axi-interconnect/Resets)). **PS 가 어떤 신호로 어디까지 reset 하는지는 BD 통합(X-03) 에서 검증해야 할 별도 항목이다.** D07 의 "동기식 active-low" 는 reset 의 *방식*이고 이것은 *범위*의 문제로, 서로 다른 항목이다.
- **`RD_FAULT` 에서는 `STATUS.error` 가 0 이다.** `error_reg` 는 FINISH 를 떠나는 에지에만 기록되는데(D02 R2), `ERR_DRAIN` 에 갇히면 FINISH 에 도달하지 못한다. START 수락 시 표시가 지워졌으므로(D02 R1) PS 는 **busy=1, error=0** 을 보게 된다. **PS 는 error 가 0 이어도 완료 시간이 초과되면 이상으로 판단해야 한다.**

**③ 복구 절차는 오류 종류로 나눈다 (2026-09-26 Codex 지적 반영).**
처음에 Claude 가 권한 "모든 오류에 reset" 은 **과했다**. `BAD_CMD(1)` 과 `NO_CFG(2)` 는 DECODE 에서 거부되어 **메모리 전송도 소비 블록 구동도 시작되지 않은** 요청이다(T-04 case 8 실측: `total_cycles=2`, `AR=0`). 하드웨어가 망가진 것이 아니므로 reset 이 필요 없다. 특히 `NO_CFG` 는 **첫 LOAD 전의 정상 상태**이기도 해서, 그것을 reset 대상으로 만들면 정상 기동 경로가 오류 경로처럼 보인다.

| `STATUS.error` | 상황 | PS 처리 |
| --- | --- | --- |
| `BAD_CMD(1)` | 요청 거부. 아무것도 시작 안 됨 | 명령을 고쳐 다시 실행. **reset 불필요** |
| `NO_CFG(2)` | 요청 거부. 아무것도 시작 안 됨 | LOAD 성공 후 INFER. **reset 불필요** |
| `BLOB_ERR(3)` / `MEM_RD_ERR(4)` / `MEM_WR_ERR(5)` | **실행 오류.** 전송·소비 블록이 진행된 뒤 실패 | 전송 종료 확인 → 실패 결과 폐기 → **공통 reset → 재LOAD → 재INFER** |
| busy 타임아웃 (error 는 0) | `RD_FAULT` 등으로 FINISH 에 도달 못 함 | 검증된 reset 절차로 복구. ② 참조 |

3·4·5 를 한 덩어리로 묶는 이유는 **`error_code` 만으로는 복구 가능 여부를 구분할 수 없기 때문**이다. `MEM_RD_ERR(4)` 는 입력 read 오류(복구 가능)와 FC1 read 오류(복구 불가)를 같은 값으로 보고한다(T-06 Q6). 보수적으로 묶는다.
- **CSR 은 바뀌지 않는다.** PS 가 기존 `error_code` 를 구분해 쓰면 된다. 검증이 끝난 `S00_AXI` 를 다시 건드리지 않는다.
- 기각한 안: error_code 세분화, STATUS 에 "reset 필요" 비트 추가. 둘 다 CSR 변경이고 민영의 PS 계약이 다시 움직인다. 재LOAD 가 4,204 cycle = 42 µs(T-03 실측)라 실익이 없다.

**③-보강 — `cfg_ok` 계약 (기존 명세 `04_pose_cnn` r20, 재확인).**
"LOAD 성공 후 1, **LOAD 시작·실패 시 0**". 이것이 ③ 을 안전하게 만드는 핵심이다 — 부분적으로 적재된 모델이 다음 INFER 에 쓰이지 않는다. 새 결정이 아니라 기존 계약이며, **Loader(L-01~L-07) 구현 시 반드시 지켜야 한다.**

**소비 블록 관련 후속:** Encoder 는 진행 중 `enc_start` 를 무시하고(동우 Q3), FC 는 공급이 끊기면 active 로 남는다. 둘 다 reset 으로만 되돌아간다. 이 성질은 ③ 의 전제이므로, 동우·지원에게 **"오류 복구는 reset 으로 한다"** 를 알려 재시작 지원을 별도로 요구하지 않는다.

**민영 전달(통보):** PS 오류 복구 절차는 `STATUS.error != 0` 또는 busy 타임아웃 → 공통 reset → 재LOAD → 재INFER 다. CSR 맵과 STATUS 비트는 바뀌지 않는다.

### 5.5 D09 확정 — Param / GELU LUT 읽기 포트 선택 (2026-09-26)

**명세가 이미 규정한 절반** (`05_Loader` r86 / r99): Param RAM 과 GELU LUT RAM 의 "읽기 포트는 **물리적으로 1개**이며 `enc_*_raddr` / `fc_*_raddr` 중 **FC 가 동작 중이면 fc 쪽을 선택**한다". 남은 질문은 "FC 동작 중" 을 무슨 신호로 만드느냐였다.

**왜 mux 가 반드시 필요한가 (실측 근거).** Claude 의 Encoder 실측에서 `enc_done` 이후에도 `enc_param_raddr` / `enc_lut_raddr` 이 **잔값으로 계속 구동**된다. 따라서 wired-OR 도, "안 쓰는 쪽은 0" 가정도 성립하지 않는다. 명시적 select 가 유일한 방법이다.

**사용자 결정: 안 C — Top FSM 이 선택 신호를 만들어 준다.**

- Top FSM 에 출력 2개를 추가한다: `param_sel_fc`, `lut_sel_fc` (1 = FC 선택, 0 = Encoder).
- 값은 상태에서 **조합으로** 뽑는다: `(state_reg == FC1) || (state_reg == FC2) || (state_reg == FC3)`. 새 레지스터를 두지 않는다. 그 외 상태(IDLE/DECODE/LD_*/IN_RD/ENC/WR/ERR_DRAIN/FINISH)에서는 0.
- Loader 는 이 두 신호를 **입력**으로 받아 RAM **읽기 주소 쪽에** mux 를 둔다. 데이터 쪽에 두지 않는다 — 그래야 `raddr` 다음 cycle 에 `rdata` 가 유효한 **1-cycle 계약**이 유지된다.
- 물리 포트가 1개이므로 선택되지 않은 쪽 출력 포트는 상대의 데이터를 본다. 이것이 r86 의 구조이며, 소비 블록은 자기 차례에만 읽는다.
- 신호를 하나로 합치지 않는 이유: 지금은 두 값이 같지만 Param 과 LUT 의 소비 시점이 달라질 여지를 남긴다.

**기각한 안.** (A) Loader 가 Top FSM 상태를 직접 본다 — `05_Loader` 포트 목록에 상태 입력이 없어 경계를 새로 뚫어야 하고, Loader 가 남의 내부 상태에 의존하게 되어 Top FSM 을 고칠 때마다 깨질 수 있다. (B) FC 가 `fc_busy` 를 내보낸다 — 블록 경계는 깨끗하지만 `08_FC` 에 없는 포트라 **아직 착수도 안 한 지원의 모듈에 추가를 요구**해야 해서 일정 위험이 있다. C 는 **Top FSM 과 Loader 양쪽 다 한림 담당**이라 협의 없이 지금 닫을 수 있고, Top FSM 변경이 출력 2개와 상태 디코드 한 줄로 끝난다.

**Encoder 와 FC 는 동시에 동작하지 않는다.** Top FSM 이 `ENC → FC1 → FC2 → FC3` 로 순차 진행하므로(T-04~T-06 구현·검증 완료) 선택이 모호한 구간이 없다.

**X-02 영향:** `04_pose_cnn` 의 Top FSM ↔ Loader 경계에 포트 2개가 늘어난다. X-02 배선 목록에 반영한다. 명세 XLSX 원문은 수정하지 않으며, 이 절이 우선한다.

## 6. PS 계약과 다음 작업

민영에게 전달할 **기존 명세 계약**과 **합의할 권장안**은 CSR 상세 설계 8절에 분리했다. 참고 PS의 AP_CTRL clear-on-read 및 float32 96 B 출력 계약을 새 CSR에 그대로 적용하지 않는다.

진행 순서:

1. Claude가 현재 CSR 초안을 바탕으로 다음 소단계 하나의 목적·범위·필요한 결정만 제안한다. D01–D05는 해당 동작을 구현하기 전에 한림/민영의 합의를 기록한다.
2. 사용자가 요청한 소단계에 한해 Codex가 구현·필요한 최소 확인을 수행한다. CSR 전체 RTL/TB를 한꺼번에 만들지 않는다.
3. Codex가 동작과 변경 코드를 설명하고 Notion 기록 초안을 제공한다. Claude 검수가 필요한 단계라면 같은 변경 범위만 검토한다.
4. 사용자의 질문과 필수 수정은 현재 단계에서 해결한다. 이해·확인·Notion 정리를 거쳐 사용자가 다음 단계 진행을 요청하면 다음 소단계를 시작한다.
5. CSR의 소단계들을 완료한 뒤 Loader/RAM, Top FSM/코어 연결도 같은 방식으로 나눈다. D06–D09는 해당 구현 전에 결정한다.
이번 문서의 검수 범위는 원문과 설계의 일치 여부 및 미결 항목 누락이다. RTL 정확성·합성·타이밍·보드 실행이 검증되었다는 뜻은 아니다.

이전 CSR 문서 작성 때의 검사 기록: 문서 내부 링크·텍스트 인코딩과 기존 인계 문서/XLSX/wrapper의 SHA-256 전후 일치를 확인했으며 RTL/TB 추가·시뮬레이션·합성은 하지 않았다고 기록되어 있다. 이번 작업 방식 갱신에서는 문서의 변경 범위와 진행 규칙만 확인한다.


## 7. 사용자 이해·Notion 기록을 포함한 소단계 개발 규칙

### 7.1 작업 단위와 진행 허용 범위

- 기본은 한 번에 학습 주제 하나 또는 관찰 가능한 작은 동작 하나다. “CSR 구현”처럼 큰 제목을 한 단계로 잡지 않는다. 파일 수나 코드 줄 수보다 사용자가 설명을 이해하고 판단할 수 있는 범위를 기준으로 한다.
- 단계 시작 시 ID, 목표, 다룰 개념, 변경 범위, 필요한 결정, 완료 조건, 최소 확인 방법을 짧게 제시한다. 사용자가 이미 그 단계를 요청했으면 승인 범위 안에서 진행하며 같은 승인을 다시 묻지 않는다.
- 승인된 단계 안에서는 필요한 파일 읽기·편집·필수 수정·국소 검사를 완료한다. 작은 편집마다 허락을 묻거나 불필요하게 중단하지 않는다.
- 해당 단계가 끝나면 설명과 기록 초안을 제공하고 멈춘다. 다음 단계의 RTL/TB, 다른 팀원의 모듈, 대규모 기반 코드를 미리 작성하지 않는다. 다음 단계의 제목은 예고할 수 있다.
- 사용자의 질문·“알겠어”·테스트 통과·Claude 검수 통과를 다음 단계 실행 승인으로 해석하지 않는다. “다음 단계 진행해”처럼 범위가 분명한 요청 후에 진행한다. 불명확하면 현재 단계의 설명/수정만 수행한다.
- 사용자의 명시적인 다음 단계 요청은 현재 단계의 이해·확인·기록 절차를 마치고 진행하겠다는 신호로 받아들인다. Notion 기록 증빙이나 반복 확인을 요구하지 않는다. 사용자가 기록을 나중에 하겠다고 정하면 그 예외를 기록하고 따른다.
- 사용자가 명시적으로 여러 단계를 한 번에 요청하면 그 범위로 조정한다. 기본 규칙을 이유로 승인된 일을 불필요하게 지연시키지 않는다.

### 7.2 단계 종료 보고와 Notion 초안

코드·설계를 실제 변경한 단계마다 아래 내용을 짧게 설명한다. 설명만 한 단계는 코드/검사를 해당 없음으로 표시한다.

1. 무엇을 왜 만들었는가: 전체 CNN 경로에서의 위치, 해결하는 문제.
2. 핵심 개념과 신호: 입력/출력, 상태·현재값/다음값의 역할.
3. 동작 예 하나: PS의 쓰기/읽기 또는 몇 clock 동안 어떤 값이 바뀌는지. 필요할 때만 작은 표나 도식을 쓴다.
4. 변경 파일과 핵심 코드 위치: 중요한 부분만 설명하고 전체 코드를 반복 출력하지 않는다.
5. 확인 결과: 실제 실행한 최소 검사와 그 결과. 미실행 검사는 분명히 구분한다.
6. 현재 한계·미결 사항: 이번 단계의 부분 구현 범위와 아직 없는 동작. 부분 구현을 완성 IP로 표현하지 않는다.
7. Notion에 복사할 기록 초안과 다음 소단계 후보 제목.

Notion 기록 초안 형식:

```text
단계 ID / 제목 / 날짜:
이번 목표와 전체 구조에서의 역할:
핵심 개념·신호:
동작 예:
변경 파일·핵심 위치:
확인 방법·실제 결과:
결정 사항 / 미결 사항 / 팀 협의:
내가 추가로 정리할 내용:
다음 단계 후보:
```

- Notion은 사용자 학습·설계 과정 기록으로 활용한다. 구현에 영향을 주는 확정 결정은 로컬 공통 문서에도 남긴다. 두 기록이 충돌하면 관련 항목만 확인하고 임의로 덮어쓰지 않는다.
- 요약 초안 제공과 실제 Notion 기록 완료는 구분한다. 사용자가 완료를 알리거나 실제 쓰기 결과가 확인된 경우에만 기록 완료로 표시한다.
- 사용자가 Notion 직접 작성을 명시적으로 요청하고 대상 페이지가 정해졌을 때만 그 단계의 기록을 작성한다. 그 외에는 복사 가능한 초안을 제공한다. 이 규칙 갱신은 Notion 직접 쓰기 요청이 아니다.

### 7.3 단계 상태와 최소 검증

- 단계 상태는 제안 / 진행 요청 받음 / 구현·설명 완료 / 사용자 확인 대기 / 다음 단계 요청 받음으로 구분한다. 설명 전용 단계에는 구현 대신 설명 완료를 쓴다.
- 사용자 이해·Notion 기록은 관찰된 사실만 기록한다. 응답이 없다는 이유로 완료 처리하지 않는다. 현재 단계의 질문이나 필수 수정은 그 단계에서 이어서 처리한다.
- Claude는 현재 변경분과 관련 설계만 검수한다. Codex의 기존 검사 결과를 활용하고 새 결함·변경·미해결 위험이 있을 때만 관련 검사를 추가한다.
- 같은 문서·소스·테스트를 두 도구가 반복해서 전수 분석하지 않는다. 작은 문서 변경에 RTL 회귀·합성을 실행하지 않는다.
- 부분 RTL은 미완성임을 표시하고 가능한 최소 문법/국소 동작 확인만 한다. 연결이 아직 없는 기능을 검증하려고 나머지 IP까지 자동 작성하지 않는다. 기능 경계가 완성될 때 필요한 통합 검사·합성을 수행한다.

## 8. 현재 진행 위치와 다음 첫 소단계

| 항목 | 현재 상태 |
| --- | --- |
| 작업 방식 | 소단계 구현·이해·확인·Notion 기록 후 진행 |
| **RTL 작업 경로** | **`D:\2609_final_project\cnn_rtl`** (`rtl/`, `tb/`). 사용자가 정한 경로이며 Claude의 초기 제안(`IP_v1_0\IP_v1_0\rtl`)을 대체한다. `IP_v1_0\IP_v1_0\rtl_template\pose_cnn_v1_0.v`는 wrapper 원본으로 그대로 둔다 |
| S00-01 | **완료** (설명·사용자 확인). PS → AXI4-Lite → CSR → Top FSM 관계와 레지스터 맵 |
| S00-02 | **구현·검수 완료**. 쓰기 채널 handshake 골격 (AW/W 독립 수락, commit, B 응답). BRESP 항상 OKAY, 레지스터 저장·읽기·펄스 없음 |
| 기술 결정 | D01–D10 모두 미합의 유지. S00-02는 어느 항목도 선점하지 않았다 |
| 문법 규칙 | 2026-09-24 확정: 템플릿 인프라는 템플릿 활용, 직접 설계 RTL은 명시적 나열(`for`/`task`/`function` 미사용), testbench는 제약 없음. 4절 참조 |
| reset 규칙 | **2026-09-25 사용자 확정: 동기식 active-low로 통일.** Encoder/Top/S00/M00 RTL에 반영. R-01 기존 TB 2곳의 검사 시점 보정·재검증 완료. 구명세 갱신은 남음. 공통 reset 공급 구현은 D07에서 결정. 5.2절 참조 |
| S00-03 | **구현·검수 완료**. 주소 디코드(`awaddr_reg[4:2]`), RW 레지스터 4개, WSTRB byte 병합. `reg_cmd`/`reg_input_addr`/`reg_weight_addr`/`reg_output_addr` 출력 활성 |
| S00-03 임시 동작 | `awaddr_reg[1:0]` 무시(0x0C와 0x0E가 같은 레지스터), WSTRB=0은 병합의 자연스러운 결과로 무변화+OKAY. 둘 다 D04/D05 확정 구현이 아니며 S00-05에서 바뀔 수 있음 |
| S00-04 | **구현·검수 완료**. 읽기 채널(outstanding 1, AR 수락 cycle snapshot), 8 offset 읽기 mux, STATUS 조립, 0x18의 `cfg_ok` 조건부 SLVERR |
| S00-03 임시 동작 해소 | D04(a) 확정으로 `AWADDR`/`ARADDR` 하위 2비트 무시가 **최종 동작**이 되었다. 코드의 TEMPORARY 주석도 갱신됨 |
| S00-05 | **구현·검수 완료**. CONTROL 펄스(등록 1-cycle), busy 거부, DDR 정렬 검사, 쓰기 SLVERR. 5.1절 7줄 표 구현 |
| **S00_AXI 상태** | **기능 완성.** 검사 101건 통과(write 9 / regs 25 / read 14 / ctrl 53) + Claude 독립 shadow 모델·양채널 stress 통과. 합성은 미실행 |
| 남은 작업 | ① CSR 합성 1회 확인(래치·자원·조합 루프) ② `S00_AXI_CSR_DESIGN.md`를 확정 동작에 맞춰 정리(4.4 8줄 표 → 5.1 7줄, `channel_enable_reg` 근거 추가) |
| **진행 순서 변경** | **2026-09-24 사용자 결정: Loader보다 Top FSM을 먼저 구현한다.** 이유 — ① D09(동우·지원)는 답이 늦고 Top FSM 정상 경로는 미결이 없다 ② D02가 아직 어디에도 구현되지 않았고 Top FSM이 유일한 소비자다 ③ CSR과 붙이면 PS 시퀀스가 처음으로 end-to-end로 돈다 |
| **X-01 완료** | **CSR 단독 합성 통과** (xc7z010clg400-1, OOC, 100 MHz 잠정 제약). 래치 **0**, 조합 루프 없음, CRITICAL WARNING·ERROR **0**. 자원 **LUT 182 / FF 208 / BRAM 0 / DSP 0** (XC7Z010의 LUT 1.0%, FF 0.6%). **Setup WNS +3.895 ns** (0 failing) |
| X-01 임계 경로 | `S_AXI_ARESETN`(입력 포트) → `S_AXI_ARREADY`. reset이 READY로 가는 조합 경로이며 AXI 권고(리셋 중 READY=0) 때문에 의도한 것이다. S00-02 검수에서 "100 MHz에서 문제될 경로가 아니다"라고 판단한 것이 수치로 확인됐다 |
| 합성 스크립트 | `cnn_rtl/syn/` 에 재사용 가능한 `syn_check.tcl` + `timing_100mhz.xdc` + `README.md`(결과 기록표) 작성. 이후 기능 경계마다 같은 명령으로 돌린다. 100 MHz는 **잠정값**이며 보드·클록은 D10 미결 |
| **Encoder 도착·검수** | 동우의 `cnn_rtl/CNN_Encoder/`(6파일 778행). 구조·포트가 명세 `06_Encoder`와 **17/17 완전 일치**. Claude가 더미 Loader RAM으로 실측 |
| **동우 Q1 답 (실측)** | `enc_start` → `enc_done` = **1,278,890 cycle** (100 MHz에서 **12.79 ms**). 명세 처리율 주석 기반 추정 1,278,720과 170 cycle 차이. 모형에 이 값을 쓴다 |
| **동우 Q2 답 = D09 (실측)** | **`enc_done` 시점에 Param/LUT 읽기가 끝나 있다.** `enc_done` 이후 `enc_param_raddr`·`enc_lut_raddr` 변화 0회. **단 주소는 잔값으로 계속 구동된다** — 주소를 OR/wired로 공유하면 안 되고 **명시적 선택 신호(mux)가 필요**하다. r86의 전제는 Encoder 쪽에서 성립 |
| **동우 Q3 답 = D08-4 (실측)** | **진행 중 `enc_start`는 무시된다.** `Conv_MAC.v:227` 이 `IDLE`에서만 수락. 재인가 시험(cycle 2443)에서 재시작하지 않고 원래 실행이 계속됨. **오류 복구 시 재시작 불가** → D08-4 결정 후 동우에게 변경 요청 필요 |
| Encoder 발견 (전달) | ① **`Buffer.v` / `Pool.v` / `gelu_stage.v` 에 `` `timescale `` 누락** → 다른 모듈과 섞으면 xsim elaboration 실패(XSIM 43-4099). 한 줄 추가로 해결 ② 전 파일 CRLF 줄바꿈(우리 파일은 LF) |
| **추론 1회 지연 추정** | Encoder 1,278,890 + FC 약 51,600 + 입력 read 1,440 + pose write ≈ **약 1.33 M cycle = 13.3 ms @100 MHz**. **Encoder가 96%를 차지**한다. 초당 최대 약 75회. 앞서 언급한 "0.5 ms"는 FC1 DDR read만 센 것이라 정정한다. 실시간 처리율과 D10(보드·클록) 검토에 이 값을 쓴다 |
| **M00_AXI 도착** | 민영의 `pose_cnn_v1_0_M00_AXI.v`(330행)가 프로젝트 루트에 들어왔다. Claude 검수: 명세 `03_M00_AXI` 계약(busy 시점, err sticky/clear, `mem_wr_ready` 펄스, 16 beat·4 KiB burst 분할, WSTRB 고정)을 모두 지킨다. xvlog/xelab 오류·경고 0, wrapper 포트 54/54 일치 |
| **D08-2 답** | 확인됨 — `mem_rd_err`는 `mem_rd_start`에서 0으로 지워진다(M00 209–211행). LOAD가 read를 2회 하므로 구간1 오류가 구간2 시작에 지워진다. **T-00 도면의 `LD_RD1` → `mem_rd_err?` 선판정이 이 경로를 이미 막는다** |
| **D08-3 답** | 확인됨 — RRESP/RID 오류는 남은 beat를 끝까지 받고 `mem_rd_busy`를 정상적으로 내린다. **예외**: `RLAST` 불일치 시 `RD_FAULT`(M00 234행)는 빠져나올 수 없는 상태라 busy가 영원히 1이다. D08 결정 시 `ERR_DRAIN`이 이 경우 갇힌다는 점을 반영해야 한다 |
| M00 관련 관찰 | ① 명세에 없던 `invalid_command` 방어 추가 — `mem_rd_err`가 "DDR 오류" 외에 "Top FSM의 잘못된 명령"도 뜻하게 됨(디버깅에는 유용) ② `WATCHDOG_CYCLES` 기본 0(비활성) ③ `C_M_TARGET_SLAVE_BASE_ADDR`를 더하지 않음(주석 명시, 계약과 일치) ④ `function` 2개 사용 — 민영 모듈이므로 우리 4절 규칙 적용 대상인지 팀 정리 필요 |
| M00 파일 위치 | R-01에서 프로젝트 루트 → `cnn_rtl/rtl/pose_cnn_v1_0_M00_AXI.v`로 이동. 이동 직후 바이트·SHA-256 일치 확인, 루트 사본 없음. 이후 이 경로가 단일 작업 원본 |
| **T-02 계획 변경** | M00 실물이 있으므로 **M00 모형 대신 실물 M00 + 간단한 AXI4 슬레이브 메모리 모형**을 쓴다. `mem_*` 계약을 모형이 아니라 실제로 검증하게 되고, burst 분할·4 KiB 경계·연속 burst가 실제로 돈다 |
| **T-00** | **완료·Claude 검수 완료.** Top FSM 전체 상태 그래프를 `cnn_rtl/doc/pose_cnn_ctrl_fsm.drawio` 4페이지(FSM 상태도 + ASM 공통/LOAD/INFER)로 확정. 상태 13개, 전이 20개. D06·D08은 주황 점선으로 미결 표시. 압축하지 않은 평문 XML이라 diff 가능 |
| 도면 표기 규칙 | 상태 박스 = 그 상태 동안 유지되는 레벨·등식. 전이 조건 출력 박스 = 1-cycle 펄스·레지스터 적재. **`fc_sel`은 `fc_start`를 샘플링하는 시점에 올바른 값이어야 한다**(`08_FC` r12·r45: `fc_start`에서 latch). 이후 값을 유지해도 되며, 도면에는 시작 전이에 필요한 값으로 표기한다. 2026-09-24 Claude가 상태 박스의 `fc_sel` 표기를 제거하고 생성 스크립트를 함께 수정함 |
| **T-01R** | **구현·시뮬레이션·단독 합성 완료 / Claude 검수·사용자 확인 대기.** 13상태 4-bit 골격, IDLE/DECODE/FINISH 구현. START snapshot 후 DECODE의 `cfg_ok`로 판정, busy 2cycle, FINISH 출구 결과 기록. 내부 결과/표시 분리 및 D02/D03 유지. Top reset은 동기식으로 반영. [구현·검증 기록](cnn_rtl/docs/T-01R_구현_검증기록.md) 참조. Notion 직접 기록은 하지 않음 |
| T-01R 검증 | 기존 CSR TB 4개 무수정 + Top 단독/CSR 통합 TB 모두 통과. 단독 START 14회, 미구현 10상태·불법 3상태 복구, cfg 전환 양방향, 미사용 출력 0 확인. 통합 START 7회/busy 14cycle, 실제 busy COMMAND SLVERR·값 보존 확인. 합성 LUT 19/FF 40/BRAM 0/DSP 0, 래치·조합 루프 0, WNS +4.885 ns(잠정 100 MHz OOC). 실행 환경·OOC 경고와 범위는 보고서에 구분 기록 |
| **T-01R 검수** | **Claude 독립 확인 통과.** 도면 XML의 `fsm_code_*` 13개와 RTL `localparam` **13/13 일치**(직접 파싱). 6개 TB 전부 재실행 PASS(경고 0). 별도 작성한 독립 cycle trace로 ① busy 정확히 2cycle ② `cfg_ok`를 DECODE에서 관찰(START 에지 아님) ③ FINISH 출구 CLEAR 경합에서 기록 우선(D02 R4) ④ busy 중 START·cmd 변경 무시 ⑤ 미사용 출력 19개가 23 cycle 내내 0 확인. 합성 재현: LUT 19 / FF 40 / BRAM 0 / DSP 0, **LATCH count = 0**, 조합 루프 0, WNS +4.885 ns |
| T-01R 검수 관찰 | ① Vivado가 FSM을 **one-hot으로 재인코딩**한다. 4-bit 이진 인코딩은 RTL·도면의 계약이고 실제 구현 인코딩은 아니다(정상) ② 미사용 주소 snapshot 3개(96 FF)는 최적화로 제거되어 FF 40이다. T-03 이후 사용 시 늘어난다 ③ `mem_rd_ready`가 상수 0이다. T-03/T-04에서 상태별 구동으로 바뀐다 |
| **reset 혼재 (RTL 해소)** | R-01에서 S00/M00의 비동기 sensitivity 4곳 제거. 기존 Top/Encoder와 모두 동기식 active-low. reset 입력은 유효한 상승 에지에 샘플링되도록 공급해야 한다. 새 reset 공급 회로·BD 유지 시간은 이번 범위에서 구현·검증하지 않음 |
| **M00 수정 주체 (2026-09-25 사용자 결정)** | **민영에게 요청하지 않고 한림 쪽에서 직접 수정한다.** `pose_cnn_v1_0_M00_AXI.v`를 프로젝트 루트에서 `cnn_rtl/rtl/`로 **옮겨** 우리 쪽 단일 원본으로 삼는다. **통보 시점도 사용자 결정: 지금 따로 알리지 않고, 나중에 팀 git에 올릴 때 사용자가 직접 설명한다.** 그때까지 두 사본이 갈라져 있는 상태를 사용자가 인지하고 감수한다. 기능·포트는 바꾸지 않으므로 갈라지는 범위는 reset 방식 4+4줄로 한정된다 |
| **R-01** | **구현·검증 완료 / Claude 검수·사용자 확인 대기.** M00 이동, sensitivity 4곳 및 VALID 게이트 4곳만 기능 변경. 신규 reset b-1/b-2 PASS. 최초 4PASS/2FAIL 이후 사용자 요청으로 regs/ctrl TB의 검사 시점만 상승 에지 뒤로 보정하여 두 TB 재실행 PASS, 누적 6/6 PASS. regs 쓰기/commit/B 각 49회, ctrl PASS 로그 53줄. 기대값과 RTL 추가 변경 없음. [R-01 검증 기록](cnn_rtl/docs/R-01_구현_검증기록.md) 참조 |
| R-01 합성·정적 확인 | S00 LUT 183/FF 208/WNS +3.895 ns, M00 LUT 364/FF 132/WNS +2.779 ns. 모두 BRAM/DSP 0, 래치·조합 루프 0(잠정 100 MHz OOC). M00 xvlog 오류·경고 0, wrapper 54/54 이름·폭 일치. TB 보정 전후 S00/M00/Top RTL SHA-256 동일, 기존 합성 결과 유지. M00 기능 TB는 아직 없으며 T-02 범위 |
| **R-01 검수** | **Claude 독립 확인 통과.** ① 프로젝트 전체 `negedge.*ARESETN` **0건**, 루트 M00 사본 없음 ② VALID 게이트가 **정확히 지정된 4개**(`S_AXI_RVALID`, `M_AXI_ARVALID/AWVALID/WVALID`)이고 READY·데이터 경로로 번지지 않음 ③ M00 기능 diff는 sensitivity 2줄 + 게이트 3줄 + 주석뿐, 포트·상태기계 무변경 ④ TB 6개 제 환경 재실행 **6/6 PASS**, 컴파일 오류·경고 0 ⑤ 합성 2회 재현 — S00 LUT 183/FF 208, M00 LUT 364/FF 132, 양쪽 **LATCH 0 / 조합 루프 0** ⑥ TB 보정 전후 RTL SHA-256 3개가 Codex 기록과 일치(보정이 RTL을 건드리지 않음) |
| R-01 TB 보정의 성격 | **기대값을 고쳐 통과시킨 것이 아니다.** 원래 `tick`이 검사 *뒤*에 있던 것을 검사 *앞*으로 옮겼을 뿐이고 기대값은 `128'b0`/`4'b0000` 그대로다. 원래 검사는 t=3 ns(첫 상승 에지 이전)에 레지스터가 0이기를 요구했는데 그것은 **비동기 reset의 정의**다. 동기식으로 확정한 이상 그 검사는 옛 계약을 주장하는 것이므로 보정이 맞다. 오히려 신규 b-1이 213비트 전체를 검사해 **커버리지는 늘었다** |
| **R-01 부수 효과 (기록 필요)** | `mem_wr_ready = wr_fire = M_AXI_WVALID && M_AXI_WREADY`이므로 WVALID 게이트가 **`mem_wr_ready`까지 전파**된다. 지정한 4개 게이트 밖의 변화지만 reset 중 Top FSM에 "데이터 수락됨"이 뜨지 않게 하므로 바람직하다. 별도 게이트를 추가한 것은 아니다. **M00의 임계 경로가 바로 이 경로**다. T-02에서 놀라지 않도록 기록해 둔다 |
| **M00 타이밍 = 현재 최빡 (D10 입력)** | M00 WNS **+2.779 ns**가 지금까지 측정값 중 가장 빠듯하다(S00 +3.895, Top +4.885). 100 MHz에서는 여유가 있으나 잠정 I/O 지연 2 ns 가정을 그대로 쓰면 **약 130~140 MHz 부근이 한계**로 추정된다. 경로는 `M_AXI_ARESETN` → 전송 성립 논리 → `mem_wr_ready`. **D10(보드·클록) 결정 시 이 숫자를 먼저 본다.** OOC 추정치이며 배치·배선·hold 미검증 |
| **T-02a** | **AXI4 슬레이브 메모리 모형 완료 / Claude 검수 통과.** `cnn_rtl/tb/axi4_slave_mem_model.v`(395행) + 자체시험 `tb_axi4_slave_mem_model.v`(412행). 연관배열 저장소(미기록 주소는 `DEAD_BEEF_BAD0_0001` 반환), 실행 중 조절 가능한 stall/지연, 다음 1 burst만 적용되고 자동 해제되는 오류 주입, 프로토콜 검사기 C1–C12 |
| **T-02a 검수** | **Claude 독립 확인 통과.** ① xvlog -sv / xelab 오류·경고 **0** ② 자체시험 **전 항목 PASS**(제 환경 재실행) ③ **포트 37/37**, 방향 전부 반대, 한쪽에만 있는 포트 없음 → T-02b에서 직결 가능 ④ **음성시험 13건, 검사기 12개 전부 최소 1회 실제 검출**(명세 요구는 6건) ⑤ 2회 실행 결과 완전 동일(재현성) |
| T-02a 설계 확인 | ① `expect_violation`은 **코드 일치 1건만** 통과시키고 중첩을 `$fatal`로 막는다. 다른 위반은 그대로 죽으므로 실제 버그를 가릴 수 없다 ② `check_quiescent`가 **무장했는데 발생 안 한 기대**를 잡는다(`armed violation was never observed`) ③ `pattern_word`가 주소에 의존하므로 잘못된 주소를 읽으면 값으로 잡힌다. 자체시험이 틀린 seed로 compare=1을 확인해 공허 통과가 아님을 보였다 ④ C10은 "침묵으로 누락을 추론할 수 없다"는 AXI 성질을 인정하고 호출자가 정지를 선언하는 방식 — 올바른 판단 |
| T-02a 관찰 (결함 아님) | ① C12는 `always @(resetn or VALID들)` + `#0`로 에지 사이 위반을 잡는다. M00의 VALID가 `ARESETN &&` 조합이라 정상 동작하며 자체시험이 양·음성 모두 확인했다. **T-02b에서 C12가 예상 밖으로 뜨면 M00을 의심하기 전에 delta 정착 순서를 먼저 본다** ② 모형도 자기 READY를 `resetn &&`로 게이트한다(우리 규약과 일치) ③ T-02b의 FC1 49,152 beat 구동 시 **시뮬레이션 실행 시간**이 처음으로 부담이 된다. 필요하면 처리율 측정만 분리 실행 |
| **T-02b** | **M00 read 경로 검증 완료 / Claude 검수 통과.** `tb_m00_read.v`(421행) + `tb_m00_read_perf.v`(43행, 공용 fixture 재사용). 기능 12/12 PASS, 프로토콜 위반 0. M00·모형 **무변경**(SHA-256 R-01 기록과 동일) |
| **T-02b 검수** | **Claude 독립 확인 통과.** 기능 TB·처리율 TB 모두 제 환경 재실행 동일. burst 수 실측이 예상과 일치 — LOAD 5,936 B=**47 burst**, 23,840 B=**187 burst**, 4 KiB 경계 4,096 B=**33 burst**(경계 분할로 32가 아님). `nonfinal_boundary_short` 카운터가 경계 분할이 실제로 일어났음을 증명(공허 통과 아님). 범위 덮기를 **온라인·오프라인 2중**으로 검증하고 ARLEN을 TB가 독립 계산해 대조. `expect_violation` 미사용 |
| **FC1 처리율 실측 (D10·성능 결정 입력)** | 393,216 B = 49,152 beat = 3,072 burst. **전체 = 49,152 + 3,072 x (DDR지연 + 2)** 로 완전 선형. 1 outstanding AR 이라 **DDR 지연 1 cycle이 3,072번 청구된다.** 지연 0/16/32/64 → cycle 55,296 / 104,448 / 153,600 / 251,904, beat당 1.125 / 2.125 / 3.125 / 5.125, 100 MHz 환산 0.55 / 1.04 / 1.54 / 2.52 ms |
| FC1 처리율 판정 | 사전 기준(beat당 1.5 초과 → 검토)으로는 **지연 16 이상에서 검토 대상**. 다만 **시스템 관점에서는 추론의 약 10%**다(Encoder 1,278,890 cycle = 약 86%). 완전히 고쳐도 추론 단축은 **약 7%**. 실제 Zynq DDR 지연 실측값이 없어 곡선 위 어디인지 모른다. **Claude 권장: 지금 M00을 고치지 않는다.** 근거를 확보했으니 실물 측정 후 재검토한다. 변경 결정은 사용자 몫 |
| T-02b 관찰 | ① 지연 0에서도 burst당 유휴 2 cycle(M00 자체 `RD_IDLE→RD_PLAN→RD_ADDR`)이 있어 beat당 1.125가 하한 ② 처리율 측정은 **128 B 정렬 기준선**이다. 실제 blob offset(base+5,936)은 4 KiB 경계 분할로 **3,073 burst**가 되며 차이는 +1 burst로 무시 가능 ③ 처리율 TB도 매 지연값마다 49,152 word 전량 대조를 수행한다 — 타이밍만 재는 게 아니다 ④ 시뮬레이션 시간 우려는 기우였다. 4점 쓸기 전체 **9초** |
| **타깃 보드 확정 (2026-09-25)** | **Zybo Z7-20 / XC7Z020-1CLG400C.** `xc7z010clg400-1`로 잰 기존 수치를 전부 `xc7z020clg400-1`로 재측정했다. **속도 등급이 -1로 같아 타이밍은 사실상 동일**하다: S00 LUT 183/FF 208/WNS +3.895, M00 LUT 364/FF 132/WNS +2.779, Top LUT 19/FF 40/WNS +4.863(7z010에서 +4.885). 바뀌는 것은 **자원 여유**다 — LUT 17,600→**53,200**, BRAM 60→**140**, DSP 80→**220**. 기존에 적은 "XC7Z010의 1.0%" 같은 비율은 실제로 약 1/3이다 |
| **Encoder 합성 실패 (X-02 차단, 동우 전달 필요)** | **`CNN_Encoder`는 현재 합성되지 않는다.** `Buffer.v`의 **비대칭 폭 인스턴스(W=64 / R=8 / 11,520 B = 92,160 bit)**가 BRAM/분산 RAM으로 추론되지 않는다 — `Synth 8-3391`. 원인: 29행이 한 클록에 `mem[waddr*RATIO + i]` **8개 주소를 동시에 쓴다.** BRAM write 포트는 클록당 1주소만 쓴다. 시뮬레이션은 통과하므로 동우 TB로는 드러나지 않는다 |
| Encoder 합성 실패 — 범위와 해법 | **두 번째 인스턴스(W=8 / R=8 / 20,480 B)는 정상 합성된다** (BRAM36 8개, 오류·경고 0). 즉 `Buffer` 모듈 전체가 아니라 **비대칭 경로만** 문제다. 해법: `mem`을 **넓은 쪽(1,440 x 64-bit)** 으로 선언해 클록당 1주소만 쓰고, 8-bit 읽기는 `raddr` 상위로 64-bit를 읽은 뒤 하위 3비트로 byte를 고르는 구조로 바꾼다. 또는 Xilinx 비대칭 폭 RAM 추론 템플릿을 그대로 쓴다 |
| **Conv_MAC DSP 실측 (동우 참고)** | **Vivado는 DSP를 하나도 쓰지 않았다.** 기본 합성: LUT **2,274** / FF 1,214 / **DSP 0** / WNS **+1.093 ns**. 8x8 곱을 LUT가 더 싸다고 판단한 것이며 자동으로 DSP를 잡아주지 않는다. `(* use_dsp = "yes" *)` 를 강제하면 LUT **260**(-89%) / DSP **35** 로 줄지만 **타이밍이 깨진다(WNS -3.723 ns, 22 failing)** — 134행 `prod`가 조합 wire라 DSP 파이프라인 레지스터를 못 쓴다. **현재 LUT 구현은 100 MHz를 통과하므로 그대로 둬도 된다.** DSP로 옮기려면 곱셈 출력에 파이프라인 단을 넣어야 한다 |
| Conv_MAC 타이밍 주의 | **WNS +1.093 ns로 지금까지 중 가장 빠듯하다**(S00 +3.895 / M00 +2.779 / Top +4.863). 다만 OOC + 잠정 I/O 지연 2 ns 가정이고 Conv_MAC의 실제 경계는 Encoder 내부라 이 값은 비관적이다. X-02 통합 합성에서 다시 본다 |
| **T-02c** | **M00 write 경로 검증 완료 / Claude 검수 통과.** `tb_m00_write.v`(496행). **11 case / 669 word / AW 49개 전량 대조**, readback 전량 일치, 경계 guard 22개 미기록 유지, 프로토콜 위반 0, `check_quiescent` 통과. tb_m00_read 재실행 12/12 유지. M00·모형 **무변경**(SHA-256 동일) |
| **T-02c 검수 — 내 명세가 틀렸다** | 완료 조건에 적은 **"`mem_wr_ready`가 연속 2 cycle 뜨는 구간이 없어야 한다"는 잘못된 요구**였다. 슬레이브가 매 cycle 수락하면 연속 beat가 연속 HIGH로 나타나며 **그게 최고 처리율이고 정상**이다. r22의 "1-cycle pulse"는 **beat 하나당 HIGH 1 cycle**이라는 뜻이지 앞뒤에 빈 cycle이 있어야 한다는 뜻이 아니다. 실제 계약은 `ready_high_cycles == W_beats == producer_advances`이고 전 case에서 **669 == 669**로 통과했다 |
| T-02c Codex 처리 평가 | **모범적.** 내 요구가 틀렸다고 임의로 무시하지 않았고, M00을 고치지도 않았다. **모든 무결성 검사를 끝까지 돌린 뒤** `CONTRACT_FAIL`로 따로 표시하고 `$fatal`로 멈춰 검수에 올렸다(주석: *"Do not silently waive the user's literal W5 requirement"*). 판단이 필요한 지점을 판단자에게 올린 것이 맞다 |
| T-02c 정정 조치 | **Claude가 `tb_m00_write.v`의 W5 최종 판정 2곳을 직접 수정**(내 실수이므로). 연속 HIGH를 실패가 아니라 관측값(`pulse_shape`)으로 보고하도록 바꿨다. 재실행 결과 **PASS: T-02c ALL W1-W8 CHECKS**. RTL·모형은 건드리지 않았다. 관측: back_to_back_pairs=578, full_rate_cases=8/11 |
| T-02c 검증 근거 | busy 종료가 read와 다름을 실증 — `pose_Bdelay12`에서 `b_delay=12`를 주자 마지막 W beat 이후 **busy가 13 cycle 더 유지**되고 B 수락에서 끝났다. AW/W 독립도 실증 — `W_before_AW`에서 **W beat 16개가 AW보다 먼저** 나갔고(first_W=1399 / first_AW=1460) 정상 완료했다. 경계 분할도 실제 발생(`boundary_ff8`, `size_4096`에서 `boundary_shorts=1`) |
| **T-02d / T-02 완료** | **M00 오류·예외 경로 검증 완료 / Claude 검수 통과.** `tb_m00_err.v`(694행), **22 case**. M00 자신의 프로토콜 위반 **0**, C12 위반 **0**, `expect_violation` 결국 **한 번도 필요 없었다**. 회귀 3종(read 12/12, write W1–W8, 모형 자체시험) 전부 유지. M00·모형 **무변경**(SHA-256 동일). **T-02(a/b/c/d) 전체 종료** |
| T-02d 진행 중 도구 문제 | 최초 실행에서 xsim **커널 예외**(`FATAL_ERROR ... exceptional condition`, 시각 0)가 났다. 원인은 문자열 조건식을 task 인자로 넘긴 부분이며 **신규 TB에서만** 상수 문자열 if/case로 바꿔 해결했다. RTL·모형 무변경. 중요한 부수 교훈: **xsim은 runtime fatal에도 exit code 0을 반환할 수 있다** — 성공 표식과 `FAIL`/`Fatal` 출력까지 봐야 한다 |
| **D08 입력 ① 정상 오류는 M00이 스스로 drain한다** | RRESP≠00 / RID≠0 / BRESP≠00 / BID≠0 모두 **남은 beat·burst를 끝까지 처리하고 busy를 정상적으로 0으로 내린다**(r72 충족). 실측: read 48 beat 중 21번째에 주입 → **나머지 27 beat 수신 후 정상 종료**. write도 동일(중간 B 오류 후 남은 16 beat 완료, `mem_mismatches=0`). **T-03 통합 확인으로 해석 보정:** 이는 소비 측 READY가 유지되는 조건이다. READY=0이면 오류 뒤에도 R 수락이 멈춘다. Loader 전달을 중지하려면 Top이 `mem_rd_ready=1`로 남은 데이터를 받아 버리고 busy 하강을 기다려야 한다. T-03에서는 사용자 승인 임시 drain을 적용했으며 ERR_DRAIN 최종 정책은 D08 미결 |
| **D08 입력 ② err sticky/clear 시점 실측** | `mem_*_err`은 sticky이고 **다음 같은 방향 `mem_*_start` 에지에서 지워진다**. read start는 write err을 지우지 않고 그 반대도 같다(실측 `old_err=01 → START rd=1 → err_after=01`). 코드 판독(M00 209–211행)과 일치 |
| **D08 입력 ③ RD_FAULT는 영구 정지 — reset만 탈출구** | `RLAST` 불일치(이른 RLAST / RLAST 누락) 양쪽 모두 `rd_state=4(RD_FAULT)` 진입 후 **2,000 cycle 동안 busy=1, err=1 유지**. `mem_rd_start` 재인가 **무시**, `mem_rd_ready` 토글 **무효**. **coordinated reset으로만 복구**되며 복구 후 정상 read 가능. 코드 판독(M00 234행)이 실측으로 확정됐다 |
| **D08 입력 ④ Watchdog은 알리기만 한다** | `WATCHDOG_CYCLES=8` 인스턴스로 AR/R/AW·W/B 4개 정체 지점을 각각 시험. 타임아웃에 `mem_*_err=1`이 뜨지만 **AXI를 취소하지 않는다**(주석 주장 확인). 24 cycle 유지 후 슬레이브가 응답을 재개하면 **전송이 정상 완료**되고 데이터도 맞는다(`mem_mismatches=0`). **주의: busy는 계속 1이다.** 따라서 watchdog으로 RD_FAULT를 *알 수는* 있어도 *빠져나올 수는* 없다 |
| **D08 입력 ⑤ 전송 중 reset은 깨끗하다** | read/write burst 진행 중 reset(상승 에지 2개) → busy·err 0, `state=IDLE`, **reset 중 VALID 3종 전부 0**(C12 위반 0 = R-01 게이트 정상), 해제 후 새 전송 정상. **단 부분 쓰기는 롤백되지 않는다**(`partial_write_rollback=none`) — 중단된 write가 남긴 DDR 내용은 그대로다 |
| **D08 남은 선택** | RD_FAULT 대응이 핵심이다. (A) 복구 불가를 인정하고 **PS의 reset을 유일한 복구 경로**로 규정 — STATUS busy가 계속 1이므로 PS가 타임아웃 판단 (B) **M00에 RD_FAULT 탈출구를 추가**(모듈을 우리가 소유하므로 가능) (C) Top FSM 자체 타임아웃 — M00이 여전히 갇혀 다음 명령이 불가하므로 **의미 없음**. 현실적으로 RLAST 불일치는 슬레이브가 규격을 어겨야 발생하며 Zynq DDR에서는 사실상 일어나지 않는다. **결정은 사용자·팀 몫** |
| **D08 입력 ⑥ (기존)** | 동우 Q3 실측 — 진행 중 `enc_start`는 무시된다(`Conv_MAC.v:227`). **오류 복구 시 Encoder 재시작이 불가**하므로, 오류 후 재추론은 reset을 거치거나 동우에게 재시작 지원을 요청해야 한다 |
| **T-03** | **Top FSM LOAD 경로 완료 / Claude 검수 통과.** `pose_cnn_ctrl.v` 298행으로 확장, 신규 `loader_stub.v`(107행) + `tb_top_load.v`(411행). **Top FSM + 실물 M00 + AXI 슬레이브 모형 + Loader stub 4개가 처음으로 함께 돌았다.** 10 case 전부 PASS(제 환경 재실행 동일), 회귀 10 TB 전부 통과, S00 4개는 무수정 통과. 보호 대상 12파일 SHA-256 동일, Top 포트 45/45 유지 |
| T-03 실측값 | `AR1=47 / AR2=187`(내 예측과 일치), `R_beats=3722`(742+2980), **수집 word 3,722개 전량 대조**. LOAD 총 소요 — ld_ready 항상 1이면 **4,204 cycle**, 8 cycle 낮추면 **33,505 cycle**. `max_ready_low=8` 실제 도달(r45 최악 조건 실측), `held_valid=29,301` cycle. 프로토콜 위반 0 |
| **T-03 검수 — 내 명세가 또 틀렸다 (2건)** | **① 오류 시 FINISH 직행이 M00을 영구 정지시킨다.** FINISH에는 `mem_rd_ready` 등식이 없어 0이 되고, `M_AXI_RREADY = (rd_state==RD_DATA) && mem_rd_ready` 이므로 **R 채널이 멈춰 `mem_rd_busy`가 영원히 1**이 된다. **② `loader_done`은 1-cycle 펄스**라 LD_RD2에서 도착하면 LD_WAIT이 영영 못 본다. Codex가 둘 다 사전에 지적했고 사용자가 보정을 승인했다 |
| T-03 승인된 보정 | ① **제자리 drain**: LD_RD1/LD_RD2에서 `ld_valid=0`, `mem_rd_ready=1`로 버리며 `mem_rd_busy` 하강까지 기다린 뒤 FINISH. 도면 ERR_DRAIN의 의미를 상태 안에서 구현한 것이며 **T-07에서 ERR_DRAIN으로 교체** 주석이 달려 있다 ② **완료 펄스 보관**: `loader_done_seen_reg` / `loader_error_seen_reg`로 LOAD 중 펄스를 저장하고 LD_WAIT에서 판정. 도면 XML과 명세 원문은 수정하지 않았다 |
| T-03 구현 세부 (좋은 판단) | `mem_rd_busy` **하강 에지**를 `mem_rd_busy_prev_reg`로 검출한다. 단순 `!mem_rd_busy` 레벨 검사였다면 **start 직후 busy가 아직 0인 1 cycle에 즉시 오발화**한다(r11: busy는 start+1에 1). 판정 순서도 도면대로 `mem_rd_err?`가 `mem_rd_busy 1→0?`보다 먼저다 |
| T-03 합성 (xc7z020) | LUT **146** / FF **77** / BRAM 0 / DSP 0, 래치 0, 조합 루프 0, **WNS +1.986 ns**. T-01R의 +4.863에서 줄었다 — FSM이 커지면서 예상된 변화다. 여전히 통과하지만 **Conv_MAC(+1.093) 다음으로 빡빡**해졌으니 T-04 이후 계속 지켜본다 |
| T-03 사용상 주의 | `tb_top_load`는 `+CASE=0~9` plusarg로 **한 번에 한 case만** 돈다. 옵션 없이 `xsim -runall` 하면 **case 0만 실행되고 PASS가 뜬다.** 10개를 다 돌리려면 `-testplusarg "CASE=n"`을 옵션 파일로 넘겨 10회 실행해야 한다 |
| **D06 확정 (2026-09-25)** | **사용자 결정: loaded-base 보관(옵션 B).** `load_base_reg`를 `DECODE → LD_RD1` 전이에서 적재하고 FC1 read가 `load_base_reg + 5,936`을 쓴다. 5.3절 참조. **T-05 착수 전에 도면 ASM-INFER의 D06 주황 점선 갱신 필요.** 민영에게는 통보만 하면 된다(PS 요구가 완화되는 방향) |
| **T-04** | **INFER 입력 단계·Encoder 구동 완료 / Claude 검수 통과.** `pose_cnn_ctrl.v` 328행, 신규 `in_ram_stub.v`(47행)·`enc_stub.v`(52행)·`tb_top_infer.v`(480행). **13 case / 15 run 전부 PASS**(제 환경 재실행 동일), 회귀 10 TB + `tb_top_load` 10 case 전부 유지. 보호 파일 무변경. **T-03의 사용성 문제도 고쳤다 — 옵션 없이 실행하면 전 case가 돈다**(`selector=-1`) |
| T-04 실측값 | `AR=90`(정렬, 예측과 일치) / `AR=91 boundary_shorts=1`(8 B 정렬만 된 base 및 `...ff8` base — 4 KiB 분할 실제 발생). `R=1440 RAM_words=1440` 전량 기록, `enc_start`는 정확히 1회. `no_valid` 181(무정체)~2,890(정체) — **beat 카운터가 `mem_rd_valid`로 제대로 게이팅**됨. 입력 단계 1,621 cycle, enc 지연 0/5/100/1000 모두 선형 반영 |
| T-04 오류 경로 | `RRESP_middle`: `RAM_words=21`에서 기록 중단, `drain_cycles=1596`·`discarded=1419`로 끝까지 받아 버리고 error=4. `RRESP_last`: 전량 기록 후 error=4. **두 경우 모두 `enc_start=0`** — 오류인데 Encoder를 돌리지 않는다 ✓. `error_then_restart`는 오류 후 재START가 완전히 정상 복구됨을 2 leg로 확인 |
| T-04 기록해 둘 동작 | **오류 시 입력 RAM에 나쁜 word가 1개 남을 수 있다.** `mem_rd_err`은 M00에서 등록되어 나쁜 beat를 수락한 *다음* cycle에 올라가므로, 그 beat 자체는 `in_we=mem_rd_valid`로 이미 기록된다. 이후 쓰기만 막힌다. `enc_start`가 안 나가고 다음 INFER이 덮어쓰므로 무해하지만, **"오류면 입력 RAM이 깨끗하다"고 가정하면 안 된다.** RTL 주석에 명시돼 있다 |
| **T-04 미반영 (T-05로 이월)** | 제가 D06 확정 후 추가한 수정분 2건이 Codex에 전달되지 않았다 — ① **`load_base_reg` 미구현**(`grep` 결과 0건) ② ENC 주석이 `T-05: ... D06 required`로 **낡았다**. 전달된 원문 명세 기준으로는 완전하므로 T-04의 결함이 아니다. **`load_base_reg`는 소비처(FC1)와 함께 T-05에서 만드는 편이 오히려 낫다** — 쓰지 않는 레지스터를 한 단계 동안 들고 있을 이유가 없다 |
| **Top FSM 타이밍 추이 (주시)** | WNS **+4.863(T-01R) → +1.986(T-03) → +1.734(T-04)**. LUT 19 → 146 → **239**, FF 40 → 77 → **120**. 아직 통과하지만 계속 줄고 있다. T-04 임계 경로는 **`cmd_reg_reg[30]` → `mem_rd_addr[10]`** — 32-bit `cmd_reg` 전폭 비교가 주소 mux로 이어진다. **줄일 여지**: `cmd_reg`를 START 에지에 2-bit 종류로 미리 디코드하거나 `mem_rd_addr`를 등록한다. **지금은 하지 않는다.** T-05/T-06에서 여유가 더 줄면 그때 쓴다 |
| **T-05** | **FC1 단계·`load_base_reg` 완료 / Claude 검수 통과 (조건 2건은 내 명세 오류로 무효).** `pose_cnn_ctrl.v` 363행, 신규 `fc_stub.v`(146행)·`tb_top_fc1.v`(501행). **11 case / 14 INFER run 전부 PASS**(제 환경 15.6초 재실행 동일), 보호 회귀 10 TB + `tb_top_load` 10 case 전부 유지. 보호 파일 무변경 |
| **T-05 D06 실증** | case 9 leg 1에서 `loaded=1c100050 / current=1c000050`으로 **두 값을 서로 바꿔** 주고 발행 주소가 **`1c101780` = loaded + 5,936** 임을 확인했다. 현재 `reg_weight_addr`을 쓰지 않는다는 D06 확정 동작이 실증됐다. 재LOAD 시 `load_base_reg`가 갱신되는 것도 같은 case로 확인 |
| T-05 backpressure 실측 | `fifo_full`이 실제로 동작했다 — full cycle 최대 **142,828**, 최대 연속 full **1,427**(pause_resume) / 37(random) / 3(slow). **`fifo_we && fifo_full` 는 전 case 0건**(`overflow=0`) — full 중 push 로 데이터가 사라지는 일이 없다. `pushes=pops=49,152` 전량 일치 |
| T-05 `fc_done` 3종 타이밍 | `after` / `same` / **`before`** 전부 통과. `done_before` case 는 done 이 read 완료보다 **54,143 cycle 먼저** 왔고 정상 종료했다 — `fc_done_seen_reg` 의 존재 이유가 실증됐다. Codex 가 정확히 짚었듯 **정상 완료로는 조기 done 이 물리적으로 불가능**(모든 word 를 소비해야 하므로)하여 명시적 주입 모드로 분리했다 |
| T-05 burst 정렬 관찰 (Codex) | 정렬 기준은 LOAD base 가 아니라 **FC1 read 주소(base+5,936)** 다. base 가 128 B 정렬이면 FC1 주소는 +48 B 비정렬이라 **3,073 burst**, base 하위가 `0x50` 이면 FC1 주소가 정렬되어 **3,072 burst**. 양쪽 모두 시험했다. T-02b 에서 예측한 +1 burst 가 실제로 확인된 것 |
| **T-05 내 명세 오류 ① (P9, 충족 불가)** | "`tb_top_infer` 13 case 를 **수정 없이** 통과"는 **구조적으로 불가능**했다. 그 TB 는 T-04 시점에 작성돼 `fc_done=0` 고정 + "FC 출력이 항상 0" + ENC→FINISH 를 검사한다. T-05 에서 ENC→FC1 이 되면 FC 출력이 0 이 아니고 `fc_done=0` 이면 FC1 에서 영원히 못 나온다. **판정: 내 조건이 무효.** `tb_top_infer` 에 fc_stub 을 붙이고 FC1 완료까지 허용하는 **최소 수정을 승인한다** (입력 단계 13조건은 그대로 유지). T-06 의 첫 항목으로 넣는다 |
| **T-05 내 명세 오류 ② (P7) = D08 입력 ⑦** | "오류 뒤 재START 로 완전 복구"와 "진행 중 FC 를 강제 중단하지 않는다"가 **서로 모순**이다. FC1 read 오류로 공급이 끊기면 FC 는 예상 49,152 word 를 못 채워 **active 에 남고**, 다음 `fc_start` 는 "idle 일 때만"(08_FC r10/r43) 계약을 어긴다. **판정: `공통 reset → 재LOAD → 재INFER` 를 T-05 의 복구 경로로 인정한다.** Codex 가 FC 를 몰래 중단하거나 stub 을 자동 복구시키지 않은 것이 옳다 |
| **D08 입력 ⑦ — 소비 블록 2개가 오류 후 재시작 불가** | Encoder(동우 Q3: 진행 중 `enc_start` 무시)와 **FC(공급 중단 시 active 고착)** 둘 다 중간 오류에서 되돌릴 수 없다. **T-04 와의 차이가 핵심**: 입력 read 오류는 `enc_start` 가 *아직 안 나갔으므로* 완전 복구됐지만, FC1 read 오류는 `fc_start` 가 *이미 나간 뒤*라 복구가 안 된다. **D08 은 "어느 시점 이후의 오류는 reset 없이 복구 불가인가"를 정해야 한다** |
| **Top FSM 타이밍 — 완화 시점 도달** | WNS +4.863 → +1.986 → +1.734 → **+1.408 ns**(T-05). LUT 239→**362**, FF 120→**158**. 내가 정한 하한 1.0 ns 는 아직 안 넘었다. 임계 경로가 `cmd_reg` 비교에서 **`weight_addr_reg[6]` → `mem_rd_addr[28]`(주소 덧셈기)** 로 옮겨갔다. **완화안 확정: `load_base_reg + 5,936` 과 `weight_addr_reg + 399,152` 를 미리 계산해 레지스터에 담고 출력 mux 는 등록된 값만 고른다**(64 FF). 덧셈기가 경로에서 빠지고 타이밍 계약은 안 바뀐다. `mem_rd_addr` 자체를 등록하는 안은 **쓰지 않는다** — M00 이 addr 을 start cycle 에 latch 하므로(r8/r9) start 도 함께 밀어야 해서 계약이 깨진다 |
| **T-06** | **INFER 정상 경로 완성 (FC2/FC3/WR) / Claude 검수 통과 (조건 1건은 내 명세 오류로 무효).** `pose_cnn_ctrl.v` 407행, 신규 `tb_top_full.v`(537행), `fc_stub` 확장, `tb_top_infer` 보정. **10 case / 15 INFER run 전부 PASS**, `tb_top_infer` 13 case 보정 후 통과, 보호 회귀 10 TB + `tb_top_load` 10 case 유지. **남은 미구현 상태는 ERR_DRAIN 하나뿐** |
| **추론 1회 실측 (stub 기준)** | Encoder 실측 지연(1,278,890)을 넣은 case 에서 **총 1,335,832 cycle = 100 MHz 에서 13.36 ms**. 내부: 입력 1,621 + Encoder 1,278,890 + FC1 스트리밍 55,303 + FC2 4 + FC3 5 + WR 3. **Encoder 가 95.7%.** 주의 — FC2/FC3 연산 시간이 stub 값(4/5 cycle)이고 DDR 지연 0 가정이므로 **하한값**이다. 실물 FC·실제 DDR 지연이 붙으면 늘어난다 |
| T-06 WR 실측 | `AW=1 W=3 B=1`, `mem_wr_ready` 펄스 **정확히 3회·각 1 cycle**(`ready_max_run=1`), pose 24 B byte 단위 전량 일치. busy 가 마지막 W 이후 B 까지 유지되는 것도 확인(`B_after_last_W`=1 정상 / 21 stall / 13 오류). WR 오류는 도면대로 **ERR_DRAIN 없이 FINISH 직행**, err_code 5 |
| **T-06 Q6 = D08 의 답** | 오류 지점별 **재START 복구 가능성 실측**: 입력 read 오류 → **복구 O** · write 오류 → **복구 O** · **FC1 read 오류 → 복구 X**(`restart_contract=REJECTED active=1 consumed=1285 expected=49152 rejected_starts=1`), `공통 reset → 재LOAD → 재INFER` 로만 복구. **경계는 `fc_start`/`enc_start` 발행 시점이 아니라 "소비 블록이 작업 도중에 남는가"다** — write 오류는 FC3 까지 이미 끝나 FC 가 idle 이므로 복구된다 |
| **T-06 타이밍 완화 성공** | 완화 전 LUT 475 / FF 191 / WNS **+1.406 ns** → 완화 후 LUT **471** / FF **220** / WNS **+1.728 ns**. 주소 덧셈기를 `ld2_addr_reg`·`fc1_addr_reg` 로 미리 계산해 등록. **LUT 는 오히려 4 줄고 FF 29 증가, 여유 +0.32 ns 회복.** 임계 경로가 덧셈기에서 **`cmd_reg_reg[15]` → `mem_rd_addr[0]`(32-bit 명령 비교)** 로 되돌아갔다 — 다음에 여유가 필요하면 **`cmd_reg` 2-bit 선디코드**가 남은 카드다 |
| T-06 완화 검증 방식 (좋은 설계) | 완화가 동작을 바꾸지 않음을 **T-05 구조에 완화만 얹어** 확인했다 — `tb_top_fc1` 11조건/14회가 수정 없이 통과하고 관측 줄이 전부 동일했다. FC2/FC3/WR 변경과 섞지 않고 분리 검증한 것이며, 이것을 최종 회귀로 대신하지 않는다고 명시했다 |
| **T-06 내 명세 오류 (T-05 와 같은 실수 반복)** | "`tb_top_fc1` 수정 금지"는 또 **충족 불가능**이었다. 그 TB 는 T-05 시점 기준이라 FC1→FINISH · FC START 총 1회 · write 출력 항상 0 을 검사한다. T-06 은 FC1→FC2→FC3→WR 이므로 양립할 수 없고, 확장된 stub 의 `pose_data` 미연결로 `VRFC 10-3645` 경고도 난다. **판정: 내 조건 무효. 최소 보정을 승인한다** (FC1 관측 조건은 유지, FC2 이후 구간만 허용). T-07 첫 항목으로 넣는다 |
| **[규칙] 경로를 늘리는 단계는 직전 통합 TB 를 함께 고친다** | T-05 의 `tb_top_infer`, T-06 의 `tb_top_fc1` 로 **같은 실수를 두 번** 했다. FSM 경로를 연장하면 **직전 단계의 같은 경로 통합 TB 는 구조적으로 낡는다.** 앞으로 그런 TB 는 보호 대상이 아니라 **수정 범위**에 넣는다. 보호 대상은 다른 경로의 통합 TB(`tb_top_load` 등)와 S00/M00/모형 TB 로 한정한다. **T-07(ERR_DRAIN)은 오류 분기를 바꾸므로 오류 case 를 가진 통합 TB 4개가 전부 영향을 받는다** |
| **D08 확정 (2026-09-26, Codex 보완 반영)** | ① ERR_DRAIN 별도 상태 — **오류 발견 cycle 부터** 소비 쓰기 차단 ② RD_FAULT 갇힘 인정 — **reset 범위는 X-03 에서 검증**, `RD_FAULT` 시 `STATUS.error=0` 이므로 PS 는 **시간 초과로** 판단 ③ **실행 오류(3·4·5)만 reset 복구**, 요청 거부(1·2)는 재요청. 5.4절 참조. **어느 보완도 Top FSM RTL 을 바꾸지 않는다** — ①은 T-03~T-06 구현에 이미 반영, ②③은 PS·BD 계약 |
| **T-07 / Top FSM 완성** | **ERR_DRAIN 구현 완료 / Claude 검수 통과. 13상태 전부 구현됐다.** 제자리 drain 4벌 삭제, `default` 는 불법 인코딩 복구 전용만 남음(`미구현` 0건). 통합 TB 4개 전부 통과 — `tb_top_full` 13 case/18 run, `tb_top_infer` 13/15, **`tb_top_fc1` 11/14 (보정 후, elab 경고 0)**, `tb_top_load` 10 case. 보호 회귀 10 TB 유지, 보호 파일 무변경 |
| T-07 ①-보강 이행 | 오류 판정 **그 cycle 에** 소비 쓰기를 눌렀다 — 예: `IN_RD` 에서 `if (mem_rd_err) begin ... in_we = 1'b0; state_next = ERR_DRAIN; end`. ERR_DRAIN 상태 등식에만 의존하지 않는다. R4 동등성표의 `consumer_words` 가 T-04/T-06 과 동일한 것이 그 증거다(오류 시 21, 정상 시 1440) |
| **T-07 R4 동등성 (핵심 검증)** | 전 case `data_and_M00_timing_equal=True`. `read_fall_before == read_fall_after` 로 **M00 타이밍이 하나도 안 바뀌었다.** 정상 case 는 `delta_cycle=0`. **유일한 차이: LOAD case 8(마지막 beat 오류)에서 `delta_cycle=1`** — 상태를 하나 거치느라 1 cycle 늘었다. 숨기지 않고 표에 남겼다. ERR_DRAIN 체류는 case 별로 1~53,849 cycle, 폐기 beat 0~47,867 |
| **T-07 R5 = D08 ②-보강 근거** | 이른/누락 RLAST 양쪽 모두 **2,000 cycle 고착**. 관측: Top 상태 11(ERR_DRAIN) / M00 상태 4(RD_FAULT), **`status_busy=1` · `status_error=0` · `run_error=4`**. FINISH 에 도달하지 못해 표시가 기록되지 않는다는 것이 실측으로 확인됐다. **PS 는 error 표시를 기다리면 안 되고 busy 시간 초과로 판단해야 한다.** 공통 reset 후 LOAD→INFER 정상. Codex 가 "무한 시간을 시뮬레이션한 것은 아니다"를 명시한 것도 정확하다 |
| T-07 합성 (xc7z020) | LUT **457**(T-06 471 에서 **-14**, drain 중복 제거 효과) / FF **225** / BRAM 0 / DSP 0, 래치 0, 조합 루프 0, **WNS +1.741 ns**(T-06 +1.728 에서 소폭 개선). 임계 경로 `cmd_reg_reg[30]` → `mem_rd_bytes[11]`. 남은 완화 카드는 여전히 `cmd_reg` 2-bit 선디코드 |
| **Top FSM 전체 요약** | T-00 도면 → T-01R 골격 → T-02(M00 단독 검증 a/b/c/d) → T-03 LOAD → T-04 IN_RD/ENC → T-05 FC1 → T-06 FC2/FC3/WR → T-07 ERR_DRAIN. **13상태 20전이 전부 구현·검증.** 최종 `pose_cnn_ctrl.v` 407행, LUT 457 / FF 225 / WNS +1.741 ns. 추론 1회 **1,335,832 cycle = 13.36 ms @100 MHz**(stub 기준 하한) |
| **D09 — 명세에 이미 답이 있다** | `05_Loader` r86: Param RAM 의 "**읽기 포트는 물리적으로 1개이며 `enc_param_raddr`/`fc_param_raddr` 중 FC 가 동작 중이면 fc 쪽을 선택한다**". r99: GELU LUT 도 동일. **즉 명시적 select mux 가 이미 규정돼 있다** — Claude 가 Encoder 실측(주소가 done 이후에도 잔값으로 계속 구동됨)으로 도달한 결론과 일치한다. 남은 것은 **"FC 가 동작 중" 을 무슨 신호로 판정하는가** 뿐이며 L-07 에서 정한다 |
| **L-01** | **Blob Decoder 골격 완료 / Claude 검수 통과.** 신규 `rtl/blob_decoder.v`(238행) + `tb/tb_blob_decoder.v`(341행). 3,722 beat 수락, **11구간 판별**, 8/2/1 처리 주기, header 검사. 상주 RAM 쓰기는 전부 0(L-02 범위). **완전 LOAD 25회 실행 전부 PASS**(제 환경 재실행 동일). 기존 15 TB 전부 **수정 없이** 통과, 기존 RTL 3개 무변경 |
| **L-01 — 내 명세의 산술 오류** | 완료 조건에 "총 9,388 cycle" 을 적었는데 **덧셈을 틀렸다.** 내가 쓴 식 `4+720+48+4608+96+384+2048+384+384+72+1024` 는 **9,772** 다 — 384 짜리 항 하나를 합산에서 빠뜨렸다. **Codex 가 잡았고 "숫자 9,388 에 맞추려고 타이밍을 줄이지 않았다" 고 명시**한 뒤 9,772 를 그대로 보고했다. 올바른 처리다. 실측 9,772, 구간별 값은 내 지도와 **11/11 일치**. 최종 PASS 줄에 `ideal_cycles=9772 specification_9388_delta=384` 로 남겼다 |
| **L-01 blob 상수 확정** | Codex 가 참고 원본 `wifi-csi-pose-main/HLS/pl_accel_v6/full_pose.h:25~27` 에서 직접 확인: `WEIGHT_MAGIC=0x36574C50`, **`WEIGHT_VERSION=2`**, `WEIGHT_WORDS=105,748`. 실제 reference blob 422,992 byte(=105,748×4)와도 일치. 원본은 읽기만 하고 수정하지 않았다. **판정: `version=2` 를 확정으로 본다.** 소스와 실제 blob 양쪽이 2 이고, 검사를 꺼 두면 포맷이 바뀐 blob 이 조용히 로드돼 엉뚱한 결과가 나온다 → **`CHECK_VERSION` 기본값을 1 로 켠다**(L-02 에서 반영) |
| L-01 무교착 확인 | header 오류 case(`bad_magic`/`bad_total_words`/`shift` 범위 밖)에서 **`ld_ready=1` 로 남은 beat 를 전부 받아 버리고**(work=3,722, ready_low=0) 스트림 끝에서 done+err 을 낸다. 내가 우려한 교착이 실제로 없다. `busy_START` 3회 무시, 초과 beat 2 case 모두 오류로 검출 |
| L-01 합성 (xc7z020) | LUT **135** / FF **117** / BRAM 0 / DSP 0, 래치 0, 조합 루프 0, **WNS +3.760 ns**(여유 충분). 직접 설계 RTL 에 `for`/`task`/`function`/`initial` **0건**(4절 규칙 준수) |
| **Codex 가 내 명세 오류를 잡은 5번째** | S00-05 조건 15(충족 불가) → T-05 P9(충족 불가) → T-06 `tb_top_fc1`(충족 불가) → T-07 D08 보완 3건 → **L-01 산술 오류.** 전부 구현 전에 지적했고 전부 옳았다. 명세에 "문제가 있으면 구현 전에 지적한다" 를 계속 넣는 것이 실제로 작동하고 있다 |
| **L-02** | **상주 RAM 4종 + Param/FCW/GELU 쓰기 경로 완료 / Claude 검수 통과.** 신규 `conv_weight_ram.v`(37행)·`param_ram.v`(32행)·`gelu_lut_ram.v`(29행)·`fcw_ram.v`(21행), `blob_decoder.v` 238→359행. **완전 LOAD 38회 + RAM 단독 TB 통과**(제 환경 재실행 동일), 기존 15 TB 전부 수정 없이 통과, 보호 23파일 무변경 |
| **L-02 — BRAM 추론 성공 (핵심 위험 해소)** | 동우 `Buffer.v` 가 실패했던 바로 그 지점이다. **4종 전부 LUT 0 / FF 0 으로 BRAM 추론**: `conv_weight_ram` RAMB36 **2**, `param_ram` RAMB36 1 + RAMB18 1, `gelu_lut_ram` RAMB18 **1**, `fcw_ram` RAMB36 **7** + RAMB18 1. 제가 `param_ram` 을 따로 재합성해 동일 확인. 결합 합성 LUT 437 / FF 199 / **RAMB36 10 + RAMB18 3** / WNS +1.801 ns, 래치·조합 루프 0. Z7-20 의 RAMB36 140 개 중 10 개라 여유 충분 |
| L-02 쓰기 검증 | 정상 LOAD 에서 **Param 984 (=328 주소 x 3 필드) / FCW 2,432 word / GELU LUT 1,024 byte** 전량 대조 통과. 5개 레이어 shift 범위 오류 10 case 에서 **오류 시점 이후 쓰기가 전부 차단**되고(`no_write_after_error=PASS`) drain·cfg_ok=0 확인. 부분 쓰기 개수가 오류 위치와 산술적으로 일치(예: FC2 shift 오류 → param 784 = 48+96+384+256) |
| **L-02 N3 음성 시험 (잘 설계됨)** | payload 의 32-bit 상하위 word 를 뒤집어 넣었더니 **header 검사는 통과하고 RAM 대조가 4,440건 불일치를 검출**했다(984+2432+1024). **header 가 아니라 payload 만 뒤집은 것이 핵심** — header 를 뒤집었으면 header 검사에 걸려 주소 대조가 검증되지 않았을 것이다 |
| L-02 기타 | `CHECK_VERSION` 기본값을 **1 로 변경**(L-01 검수 판정 이행). parameter override 없는 실제 기본값에서 version=3 blob 이 거부됨을 확인. `ld_ready` 타이밍은 L-01 과 동일(9,772 cycle, READY low 6,050, 11구간 값 동일) — 쓰기를 채워도 Top FSM 계약이 안 흔들렸다. Conv Weight RAM 은 미기록 유지(L-03 범위) |
| **L-03 / Loader 데이터 경로 완성** | **Conv Weight byte scatter 완료 / Claude 검수 통과.** `blob_decoder.v` 359→421행. **상주 RAM 4종이 전부 채워졌다.** 32 run 전부 PASS(제 환경 재실행 동일), RAM 단독 TB 통과, 기존 15 TB 수정 없이 통과, RAM 4종 RTL 무변경 |
| **L-03 핵심 검사 — 전체 채움** | `bytes=5328 writes=5328 **missing=0 duplicates=0**` 가 전 정상 case 에서 성립. 내 계산(333 word x 16 lane = Conv1 720 + Conv2 4,608 = 5,328)과 정확히 일치한다. **빈 칸도 중복도 없이 RAM 전체가 딱 채워진다** — 주소식 전체를 하나의 불변식으로 검산한 것 |
| **L-03 Conv1 lane 경계 (최대 함정) 확인** | 45 가 8 의 배수가 아니라 oc 경계가 beat 중간에 떨어진다. 실측 byte 단위 기록 — `beat 9`: `n=40~44 → word 40~44, lane 0` / `n=45~47 → word 0~2, **lane 1**`. `beat 15`, `beat 20` 도 동일 패턴. **내가 명세에 적은 예시와 정확히 일치.** 음성 시험("beat 하나는 같은 lane" 가정의 틀린 golden)이 **5,328건 전부 불일치로 검출** |
| L-03 경계 5지점 | Conv1 `n=719 → word 44, lane 15` / Conv2 `n=0 → word 45, lane 0` / `n=2303 → word 188, lane 15` / `n=2304 → word 189, lane 0`(oc 15→16 전환) / `n=4607 → word 332, lane 15`. 전부 명시 확인 |
| **L-03 초기 구현이 타이밍 실패 → 수정** | 첫 결합 합성이 **WNS -0.016 ns, 2 failing** 이었다. Codex 가 수정 후 재합성해 **+1.365 ns / 0 failing** (LUT 645→**631**). 그리고 **수정이 동작을 안 바꿨음을 561줄 PASS 관측이 전부 동일함으로 증명**했다. 숨기지 않고 초기 실패 로그도 보존 |
| **L-03 합성 — 결합으로 봐야 한다** | 결합(`loader_l02_synth` = decoder + RAM 4종): LUT **631** / FF 212 / **RAMB36 10 + RAMB18 3** / **WNS +1.365 ns**, 래치·조합 루프 0. 제가 그대로 재현했다. **주의: `blob_decoder` 를 단독 합성하면 WNS -0.919 ns 로 실패한다** — 128/96/16-bit 쓰기 버스가 OOC 에서 칩 핀으로 나가며 2 ns 출력 지연을 무는 탓이다. 실제로는 내부 BRAM 입력이므로 **결합 수치가 의미 있는 값**이다. 임계 경로는 `beat_count_reg[1]` → `conv_weight_ram/ADDRBWRADDR[13]` |
| L-03 검증 방법론 (좋은 설계) | **TB 의 golden 은 `/` 와 `%` 를 쓰고 RTL 은 카운터를 쓴다.** 구현 방식을 일부러 다르게 해서 공통 버그로 양쪽이 같이 틀리는 것을 막았다. 합성 RTL 에는 나눗셈·나머지·`for`/`task`/`function`/`initial`/`generate`/`genvar` 가 0건 |
| **L-04 / Loader 경계 확정** | **상위 모듈 완료 / Claude 검수 통과.** 신규 `rtl/weight_param_loader.v`(95행) + `tb/tb_weight_param_loader.v`(294행). blob_decoder 와 RAM 4종은 **무변경**(mtime L-03 그대로), 기존 17 TB 수정 없이 통과. `syn/loader_l02_synth.v` 는 첫 주석만 바꿔 "L-03 까지의 임시 fixture, 이후 미사용" 으로 표시하고 재현용 보존 |
| **L-04 포트 24/24 일치 (X-02 배선 근거)** | 제가 명세 XLSX `05_Loader` r8~r31 과 RTL 포트를 **각각 파싱해 독립 대조**했다 — **이름·방향·폭 전부 일치, 한쪽에만 있는 포트 없음.** X-02 는 이 경계를 그대로 꽂으면 된다. 쓰기 신호(conv/param/lut/fcw_we·waddr·wdata·wstrb)는 상위 모듈 밖으로 나오지 않는다 |
| L-04 검증 | `hierarchy_reads=0` — **계층 참조 없이 포트로만** RAM 4종 전량 대조(완료 조건 3 이행). 6개 읽기 포트 전부 1-cycle 지연, 완전 LOAD 6회 + 중단 1회, 오류·reset 통과. `nominal_cycles=9772 ready_low=6050` 로 L-03 과 타이밍 동일 |
| L-04 합성 | `weight_param_loader` 단독: LUT **631** / FF **212** / **RAMB36 10 + RAMB18 3** / **WNS +1.365 ns**, 래치·조합 루프 0. 임계 경로 `u_blob_decoder/beat_count_reg[1]` → `u_conv_weight_ram/ADDRBWRADDR[13]`. **L-03 결합과 완전히 동일** — 순수 배선임을 수치가 증명한다. 제가 그대로 재현 확인. 단 `fc_active=0` 상수라 선택 mux 가 최적화돼 사라진 상태이며, **D09 가 실제로 움직이는 구성의 수치는 아니다** |
| **L-04 — 내 명세의 잘못된 근거 2건 (Codex 지적)** | ① "기존 fixture 의 포트가 명세와 일치하지 않는다" → **틀렸다.** `loader_l02_synth.v` 도 이미 외부 24포트가 명세와 같았다 ② "K7 이 L-03 의 단독 합성 문제를 해소한다" → **틀렸다.** 기존 fixture 도 쓰기 버스가 이미 내부였으므로 L-04 가 새로 얻는 타이밍 이득은 없다(합성 수치가 완전히 같은 것이 증거). **L-04 의 실제 가치는 "정식 RTL 경계 모듈 + 명시적 D09 mux 자리"** 이며 타이밍이 아니다. 결론(단계를 하는 것)은 유지되지만 내가 댄 이유가 틀렸다 |
| L-04 관찰 | 명세 XLSX `05_Loader` r9 에 **옛 "비동기 assert / 동기 release" 문구가 남아 있다.** Codex 는 공통 문서 5.2절(동기식 active-low 확정)을 따르고 원문은 수정하지 않았다 — 올바른 처리다. R-01 때 기록한 "구명세 갱신 미완" 항목이 여기서 또 드러났다 |
| **L-05 / 실제 blob 검증 — 가정이 맞았다** | **참고 원본의 진짜 blob 으로 LOAD 성공.** `wifi-csi-pose-main/HLS/pl_accel_v6/pl_accel_v6_weights.bin` 422,992 byte (SHA-256 `063d01b8…`). 결과 `done=1 err=0 cfg=1`, `cycles=9,772 / ready_low=6,050` 로 합성 패턴과 **완전히 동일**, RAM 4종 포트 readback **불일치 0/0/0/0**(`hierarchy_reads=0`). 참고 저장소 **무변경 확인**(mtime 2026-07-11, 해시 일치). RTL 도 무변경. 기존 17 TB 통과 |
| **L-05 구간 경계 가정 확인** | blob 안 실제 오프셋이 명세 주소맵과 **전부 일치**: Conv1 @32(720 B) / Conv2 @944(4,608) / **FC1 @5,936(393,216)** / FC2 @400,688(16,384) / FC3 @418,608(3,072). LOAD 가 **건너뛰는 393,216 B 가 정확히 FC1 weight** 임이 확인됐다 — 구간 경계 가정의 직접 증거 |
| **L-05 header 실측값** | word0 magic `0x36574C50` / word1 version **2** / word2 `105,748` / word3 input_scale **0.022390** / word4 output_scale **0.006640** / word5 pool_mult **2,017,158,836** / word6 pool_shift **31** / word7 `0`. `pool_mult/2^31 = 0.939` 로 requant 배율이 상식적이다. **pool_shift 31 은 [-31,63] 안** |
| **L-05 shift 범위 — 우리 검사가 실제 모델을 거부하지 않는다** | 5개 레이어 shift 배열 전부 유효(`shift_invalid: []`). 실측 범위 Conv1 39~40 / Conv2 39~40 / FC1 40~44 / FC2 39~41 / FC3 42~43. 내가 B3 에서 우려한 "우리 검사가 실제 blob 을 거부" 는 발생하지 않았다 |
| **L-05 GELU LUT — 진짜 GELU 곡선이다** | 표본: index 0→0, 96→-4, 127→-1, **128→0**, 129→1, 192→73, 255→127. 인덱스 매핑이 `q XOR 0x80` 이므로 **index 128 = q 0** 이고 값 0 이다. 그리고 작은 하강 구간(5~32 step, max_drop 1)이 **GELU 가 0 아래로 내려갔다 올라오는 최소점**과 일치한다. 단조 증가가 아니라는 점이 오히려 GELU 임을 뒷받침한다. **4개 테이블이 전부 서로 다르다**(차이 118~238 byte). LUT 배치 가정이 옳다는 강한 증거 |
| L-05 weight 분포 | 5개 레이어 전부 INT8 범위 **[-127, 127]**, 부호 분포도 균형적(예: FC1 음 203,377 / 양 182,527 / 0 7,312). 값이 뭉개지거나 한쪽으로 쏠린 흔적이 없다 |
| **L-05 판정** | 명세 09 r44 의 "확인 필요"(weight 내부 순서 가정) 중 **구간 경계·LUT 배치·값 범위는 실제 데이터로 검증됐다.** 남은 것은 Conv 의 `[oc][ic][kh][kw]` 와 FC 의 `[출력][입력]` **내부 순서**뿐이며, 이것은 값이 맞는 자리에 있는지의 문제라 **X-04 golden 추론에서만 최종 판정된다** |
| **D09 확정 (2026-09-26)** | **사용자 확정: 안 C.** Top FSM 이 `param_sel_fc` / `lut_sel_fc`(상태 조합, FC1/FC2/FC3 에서 1)를 만들어 Loader 에 주고, Loader 는 **읽기 주소 쪽에** mux 를 둔다. 5.5절 참조. **L-07 이 구현한다.** `04_pose_cnn` 의 Top↔Loader 경계에 포트 2개 증가 → **X-02 배선 목록에 반영 필요**. 이로써 **D01~D09 가 전부 닫힌다** — 남은 미결은 D10 의 클록뿐이며 X-03 에서 정한다 |
| **L-07 / Loader 완성 · D09 닫힘** | **읽기 포트 선택 연결 완료 / Claude 검수 통과.** `pose_cnn_ctrl.v` 에 `param_sel_fc`/`lut_sel_fc` 출력 2개(108~109행, 상태 조합), `weight_param_loader.v` 에 입력 2개 + **읽기 주소 mux**(53~54행). §5.5 안 C 그대로다. `blob_decoder`·RAM 4종 **무변경**. 기존 18 TB 전부 통과 |
| **L-07 S3 — D09 의 존재 이유가 실증됐다** | `tb_top_full` 에 **stub 이 아니라 실제 `weight_param_loader`** 를 넣고 전체 INFER 경로를 돌렸다. Encoder 가 `enc_done` 이후에도 **잔값 주소를 계속 구동**(param 17 / lut 73)하는 상황에서, FC 구간 읽기 **1,026,456회 / 불일치 0**. FC 진입 16 · 중간 전환 32 · 탈출 16 전부 정상, `read_latency=1` 유지. **잔값이 실제로 무시된다** — 이게 검증되지 않았으면 mux 를 넣은 의미가 없었다 |
| L-07 S1/S2/S4 | S1: 선택쌍 **00/01/10/11 네 조합 전부**, enc·fc 에 서로 다른 주소 64개, 불일치 0, **읽기 지연 1 유지**. S2: **13상태 전부** 확인 — FC1/FC2/FC3 만 1, 나머지(IDLE/DECODE/LD_*/IN_RD/ENC/WR/ERR_DRAIN/FINISH)는 0 |
| **L-07 합성 — 비용이 정확히 예상대로** | Top FSM LUT 457 → **455**(-2, sel 은 기존 상태 디코드 재사용), FF 225 불변, **WNS +1.741 ns 불변**. Loader LUT 631 → **650**(+19), FF 212 불변, **WNS +1.365 ns 불변**. **+19 는 9-bit + 10-bit 2:1 mux = 19 bit 그대로다.** 제가 양쪽 다 재현 확인. 래치·조합 루프 0. 타이밍이 하나도 안 줄었다 |
| **한림 담당 RTL 전부 완성** | S00_AXI(CSR) · M00_AXI(reset 전환 후 인수) · pose_cnn_ctrl(13상태) · weight_param_loader(blob_decoder + RAM 4종). **LOAD 도 INFER 도 전 경로가 구현·검증됐다.** 남은 것은 X-02(코어 배선, **동우·지원 선행 필요**), X-03(BD 통합·D10 클록), X-04(golden 대조) |
| L-07 X-02 인계 | `cnn_rtl/docs/L-07_X-02_추가배선.md` 에 Top↔Loader 추가 포트 2개가 정리돼 있다. `04_pose_cnn` 명세 원문은 수정하지 않았고 5.5절이 우선한다 |
| **E-01 / Encoder 합성 가능해짐 — 그리고 더 큰 문제가 드러났다** | **`Buffer.v` 저장소 재작성 완료, 등가성 증명 완료, `CNN_Encoder` 합성 성공.** 동시에 **Encoder 가 100 MHz 를 못 맞춘다**는 것이 처음 확인됐다 — 합성이 안 되던 동안 가려져 있던 성질이다. 변경 파일은 `Buffer.v`(저장소) + `Pool.v`/`gelu_stage.v`(timescale) **3개뿐**이고 `CNN_Encoder.v`/`Conv_MAC.v`/`requant_stage.v` 는 무변경. 동우 원본 **14파일 SHA-256 무변경** |
| **E-01 등가성 증명 (Claude 독립 재현)** | 제가 원본을 직접 rename 해 reference 를 새로 만들어 돌렸고 **결과가 완전히 같았다**. Encoder 레벨: 2개 입력 패턴 x 전 구간 = **2,557,780 cycle 비교, 출력 5신호 93비트, 불일치 0**, `original_and_new_finish_together=1`. Buffer 레벨: 5가지 파라미터 조합에서 **119,312건 검사, 불일치 0**, `latency=1`, `lane_order=LSB_at_low_address`, read-first 충돌 동작 일치. 실행 1분 17초 |
| E-01 구현이 잘 된 지점 | ① **읽기 지연 1 cycle 유지** — word 와 lane 을 **같은 에지에** 등록한다. 살아있는 `raddr` 하위 비트로 고르면 lane 이 한 cycle 빨라져 깨지는데, 코드 주석이 그 함정을 명시한다 ② **read-first 충돌 의미 보존** — 원본의 `rdata <= mem[raddr]` 와 같은 nonblocking 구조라 쓰기 전 값을 반환한다 ③ **little-endian lane 대응 보존** ④ 대칭 인스턴스(`u_fmap1_buf`, W=R=8)는 `gen_legacy` 로 빠져 **원본 코드 그대로** 돈다 — 한 모듈을 고쳐 두 인스턴스가 다 정상이 됐다 |
| **E-01 — Encoder 타이밍 실패 (새 발견, 우리 변경 탓 아님)** | `CNN_Encoder` 합성: LUT **6,490** / FF **3,530** / **RAMB36 13**(입력 4 · fmap 8 · Pool 1) / DSP **10**, 래치 0 / 조합 루프 0. 그런데 **WNS −3.641 ns, failing endpoint 684, TNS −447.829 ns.** 임계 경로는 **`u_enc_rq`(requant_stage) 내부**: `param3_reg[69]` → `rq_reg[*]/R`, **logic level 31, CARRY4 23개 직렬**. **출발·도착이 모두 `u_enc_rq` 안이라 우리 Buffer 와 무관하다.** 환산 최대 약 **73 MHz** |
| E-01 부차 경로 | `입력 Buffer BRAM → lane_acc` 경로도 **−0.798 ns**(10.823 ns / 13 level). 이쪽은 우리 byte-select mux 가 1~2 level 포함된다. 다만 나머지는 MAC 누산 논리이고, **비교할 이전 수치가 없다**(원본은 합성이 안 됐다). 개선안: 7-series BRAM 은 포트별 폭이 다른 **native 비대칭 폭**을 지원하므로, fabric mux 대신 BRAM primitive 안에서 byte 선택을 하게 만들면 이 level 이 사라진다. 지금 binding 제약이 아니므로 보류 |
| **Encoder 타이밍은 팀 결정 사항 (D10 입력)** | 선택지 ① `requant_stage` 파이프라인 추가(포화 판정이 reset 핀으로 들어가는 31-level 경로를 끊는다) ② 클록을 약 70 MHz 로 낮춘다 — 추론이 13.36 → 약 19 ms 로 늘어난다 ③ 포화 논리 재구성. **`requant_stage` 는 Encoder 와 FC 가 공유한다**(`06_Encoder` u_enc_rq / `08_FC` u_fc_rq)는 점이 중요하다 — 고치면 양쪽에 영향이 간다. 동우·지원·사용자 결정 |
| E-01 내 명세 정정 3건 (Codex 지적) | ① **`enc_done` 1,278,890 은 에지 포함 관측 개수**이고 수락 START→완료까지 **경과는 1,278,889** 다. 원본·후보 모두 같다 ② `feat_raddr` 은 9-bit 이지만 `Pool.v:140` 저장소는 `res_mem[0:383]` 이라 **유효 384 word + 범위 밖 128 X** 다. "0~511 전량"이라고 쓴 내 표현이 부정확했다 ③ "기존 18 TB" 는 실제 **19개** 다 |
| **E-01 작업 충돌 — 내 실수** | Codex 가 9파일을 복사해 작업을 시작한 뒤, **내가 같은 시점에 6파일로 다시 복사하고 TB 3개를 지웠다.** Codex 는 규칙("같은 파일을 두 도구가 동시에 수정하지 않는다")대로 `rtl/encoder` 덮어쓰기를 **보류**하고 후보를 ZIP+패치로 보존했다 — 올바른 처리다. **검수 후 Claude 가 후보를 `rtl/encoder/` 에 반영했다.** 원본 14파일 무변경 재확인 |
| **X-02a / 코어 통합 — 실물끼리 처음 만났다** | **`pose_cnn.v`(191행) 완료 / Claude 검수 통과.** Top FSM + Loader + **실물 Encoder** + FC stub 네 인스턴스 배선. 6 case / 실물 Encoder **6회 완주** / 정상 INFER 4회, 기존 20 TB 통과. **보호 파일 50개 무변경**(동우 원본 14개 포함), 기존 54파일 중 승인된 TB 4개만 변경. 실행 2분 17초 |
| **X-02a 포트 28/28** | 제가 명세 XLSX `04_pose_cnn` A8:F37 과 `pose_cnn.v` 포트를 **각각 파싱해 독립 대조** — 이름·방향·폭 전부 일치, 한쪽에만 있는 포트 없음, **AXI 신호 0개**. X-03 은 이 경계를 그대로 wrapper 에 꽂으면 된다 |
| **추론 1회 = 1,338,265 cycle (실물 기준 최초 수치)** | stub 기준 1,335,832 에서 **+2,433**. 내부: 입력 1,440 word(AR 90) + Encoder **1,278,889 경과** + FC1 49,152 word(**AR 3,073**) + pose 24 B(AW 1). 100 MHz 환산 **13.38 ms**. **주의: FC 는 여전히 stub 이므로 FC2/FC3 연산 시간이 빠져 있다** — 실물 FC 도착 시 늘어난다 |
| **X-02a — 예측했던 +1 burst 가 실물에서 확인** | `AR_FC1 = 3,073`(3,072 아님). FC1 read 주소가 `load_base_reg + 5,936` 이고 5,936 은 128 B 정렬이 아니라 4 KiB 경계에서 한 번 갈라진다. T-02b 처리율 측정과 L-05 에서 예측했던 값이 전체 시스템에서 그대로 나왔다 |
| X-02a LOAD 실측 | **10,114 cycle**. Loader 단독 9,772 에 **M00 DDR read 오버헤드 342** 가 붙는다. `AR = 47 + 187`, `output_scale_bits = 0x3BD997A8`(L-05 실측 blob word4 와 일치), `cfg_ok = 1` |
| **X-02a W4 — D09 실물 검증 완료 (이번 단계의 핵심)** | 실물 Encoder 의 잔값 주소는 **param 32 / lut 424** 다. L-07 stub 의 17/73 과 **다르다** — 명세에 "실물 값은 다를 수 있다"고 써 둔 것이 맞았다. FC 구간에서 `revoked_param_reads=117` / `revoked_lut_reads=245`, `addresses_continue=1`, `selected_data_checker_continues=1` — **Encoder 가 계속 구동하는 잔값이 실제로 무시된다.** RAM 1-cycle 검사 8,029,596회 통과 |
| X-02a W6 오류 4곳 | LOAD read 오류 → err 4 · cfg **0** · ERR_DRAIN 826 / 입력 read 오류 → err 4 · cfg 1 유지 · **enc_starts=0** / FC1 read 오류 → err 4 · ERR_DRAIN 55,288 · FC1_pushes 8 / pose write 오류 → err **5** · **ERR_DRAIN 0**(도면대로 직행). 네 경우 모두 `rd_busy=0 wr_busy=0` 으로 정상 종료 |
| X-02a W7 비공허 확인 | 입력 패턴을 바꾸면 `feature_changes=384`, **pose digest 가 달라진다**(`967591aa…` vs `d740b1dc…`). fc_stub 이 `flat_rdata` 를 굴려 digest 를 만들므로 **Encoder 출력 변화가 pose 까지 전파**된다. 값이 맞는지는 golden 이 필요하다(G-01) |
| X-02a 블록 합성 무변경 | ctrl LUT 455/WNS +1.741 · loader LUT 650/WNS +1.365 · Encoder LUT 6,490/WNS **−3.641** — 세 블록 전부 이전과 동일. 통합 과정에서 아무것도 안 바뀌었다. `pose_cnn.v` 는 `u_fc` 가 TB 모형이라 합성 대상이 아니다 |
| X-02a 내 명세 누락 (7번째) | `fc_stub` 을 쓰는 TB 가 `tb_top_fc1`/`tb_top_full` 둘이라고 적었는데 **`tb_top_infer` 도 쓴다.** Codex 가 잡고 사용자 승인 후 보정했다 |
| **G-01 / golden 생성 도구 완료 — 재사용 가능** | **Claude 검수 통과.** `cnn_rtl/golden/` 에 `build_golden.py`(`--blob`/`--input-bin`/`--output` 인자) + 관측 사본 + 형식 문서. **제가 직접 실행해 재현했고 덤프 7종이 Codex 결과와 byte 동일.** `baseline_bits_equal=24 max_abs_err=0.0`. 참고 저장소·RTL·기존 21 TB **전부 무변경** |
| G-01 산출 golden | `encoder_flat_u64.hex` **384 word**(우리 `feat_rdata` 대조용) · `encoder_flat_i8.hex` 3,072 B · `fc1/fc2_requant_i8`·`gelu_i8` 각 128 · `fc3_i8` 24 · **`fc1/fc2_acc_i32` 128 + `fc3_acc_i32` 24**(requant 전 누산값 — 내가 "어려우면 건너뛰라"고 한 것을 확보) · `pose_f32` 24 · `input_i8.bin`. 형식·순서·크기는 `golden/dump_hooks.md` 에 |
| G-01 instrument 안전성 | 추가된 줄이 **12줄뿐**이고 전부 `g01_capture_acc` / `g01_dump_*` 호출이다 — **알고리즘 무변경**. 원본 4파일 사본이 참고 저장소와 byte 동일. 최종 pose 가 `test_expected_pose[24]` 와 **비트 일치**하는 것이 instrument 가 안전했다는 증거 |
| G-01 도구 검증 | **반복**(같은 blob → 동일 재현) · **다른 blob**(FC3 weight 0 → 기대값 비교 자동 해제) · **다른 입력**(zero → Encoder 출력 3,072 중 2,957 byte 변화) 3종. 실행 5~7초. 재학습 후에도 그대로 쓸 수 있다 |
| **G-01 r44 확정 — 우리 주소식이 맞다** | 참고 C++ 코드를 직접 인용해 확정했고 **제가 원문을 대조 검증**했다. Conv1 `index=((oc*3+ch)*5+kh)*3+kw` = **`oc*45 + tap`** ✓ 09 r25 일치. Conv2 `index=((oc*16+ic)*3+kh)*3+kw` = **`oc*144 + tap`** ✓ 09 r29 일치. FC 3종 전부 `[출력][입력]`. **`FC1_PACK=4` 는 "32-bit word 에 연속 입력 weight 4개"** 이며 출력 채널 묶음이 아니다 — `unpack_i8` 이 낮은 byte 부터 읽으므로 우리 64-bit FIFO beat 와 순서가 맞는다. 독립 Python dot product 로 누산값 280개 교차 확인까지 했다 |
| G-01 Flatten 순서 확정 | `full_pose.cpp:470` → `byte n = ((rx*32+oc)*8+oh)*4+ow`, `word = rx*128 + oc*4 + oh/2`, `lane = (oh%2)*4 + ow`. 명세 07_Flatten r12 와 **`Pool.v:135`/`:146`** 의 대응이 같다. G-02 대조의 전제 조건이 확인된 것 |
| **G-01 재학습 영향 경계 (사용자 요청 항목)** | 안전(blob 교체만): weight 값·bias·requant_mult·GELU LUT 내용·input/output scale·pool_mult/shift. **주의: requant_shift 328개가 전부 [−31, 63] 안이어야 하며 벗어나면 Loader 가 거부**(검사 완화 안 함). 실측 여유 — Conv1/Conv2 23, **FC1 19(가장 빡빡)**, FC2·FC3 그 이상. shift 는 대략 `log2(1/scale)` 이라 **여유 19 는 활성 scale 이 2^19 ≈ 50만배 작아져야 소진**된다 → 현실적으로 안전. **재설계 필요: 채널 수·입력 크기·레이어 구조** |
| G-01 blob 출처 판단 | `ML/outputs/` 가 **없다**. HLS blob = `petalinux/tools/.../pl_accel_v6_weights.bin` = `test_vectors.h:test_weights` 가 **422,992 byte 전체 동일**. 수정 시각 2026-07-11, 로컬 복사 2026-09-24. → **참고 저장소에 함께 배포된 샘플 모델로 보인다.** 다만 timestamp 는 복사로 바뀔 수 있어 단정하지 않는다고 명시 — 올바른 태도. **즉 지금 golden 은 "RTL 이 맞는지" 확인용이고, 사용자 모델은 나중에 갈아끼운다** |
| **G-02 / ★ Encoder 출력이 golden 과 비트 일치 — 기반이 확정됐다** | **H4 전량 일치. Claude 독립 재현.** 3회 실행(현재 샘플 / 같은 입력 재실행 / **zero 입력**) 전부 `words_equal=384 words_mismatch=0 bytes_equal=3072 bytes_mismatch=0`. 합계 **1,152 word / 9,216 byte 대조, 불일치 0**. RTL 무변경, 기존 21 TB 관측값 X-02a 와 동일 |
| **G-02 로 동시에 확정된 것 7가지** | ① Loader 의 Conv weight byte scatter(5,328 B) ② Param RAM 주소·필드 배치 ③ GELU LUT table·`q XOR 0x80` 매핑 ④ `pool_mult`/`pool_shift` 전달 ⑤ D09 읽기 선택(ENC 구간) ⑥ Flatten 순서(`word = rx*128 + oc*4 + oh/2`) ⑦ **동우 Encoder RTL 이 참고 C++ 와 같은 함수를 계산한다** — ⑦ 은 아무도 확인한 적이 없던 항목이고 이번에 처음 확인됐다 |
| G-02 H6 비공허 확인 | zero 입력으로 golden 을 새로 뽑아 대조했더니 **우리 RTL 과 golden 이 똑같이 2,957 byte 변했다**(`changed_input_RTL_words=384 bytes=2957 / golden bytes=2957`). 한쪽만 안 바뀌면 배선·읽기가 끊긴 것인데 그런 일이 없었다. 같은 입력 재실행은 **0 word 차이** |
| G-02 실측 대조 | LOAD **10,114 cycle (X-02a 대비 delta 0)**, `enc_elapsed` **1,278,889 (delta 0)**, `infer_cycles` 1,335,832(이 TB 는 FC 가 flat sweep 만 하므로 FC1 DDR read 가 없다). `output_scale_bits=0x3BD997A8` |
| G-02 접근 범위 관측 | ENC 구간에 Encoder 가 건드리는 범위가 **Param 0~47**(Conv1 0~15 + Conv2 16~47)과 **LUT 1~497**(table 0·1)로 정확히 제한된다. `param_outside=0 lut_outside=0 D09_bad=0 pool_param_bad=0`, 런타임 동기응답 검사 각 1,278,889회 `bad=0`. zero 입력에서는 LUT 범위가 **92~431** 로 달라진다 — 활성값이 바뀌면 읽는 주소도 바뀐다는 뜻 |
| G-02 TB 설계 (좋은 장치) | **`h1_verified.txt` preflight 가드** — blob·입력 SHA-256 을 호스트가 먼저 기록해야 TB 가 돌아간다. 없으면 `host SHA preflight record required` 로 즉시 멈춘다. golden 과 다른 blob 으로 비교해 **의미 없는 실패/성공**이 나오는 것을 구조로 막았다. 제가 재현할 때 이 가드에 먼저 걸렸다 |
| **남은 미확인은 FC 뿐** | Loader·Encoder·weight 주소식·Flatten 이 전부 확정됐다. F-01~F-03 은 이제 **확정된 기반 위에** 쌓는다. FC 검증 기준도 이미 있다 — `fc1/fc2_acc_i32`(128+128) · `fc3_acc_i32`(24) · `requant_i8`·`gelu_i8` · `pose_f32`(24, 허용오차 1e-5) |
| **F-01 부분 완료** | `rtl/fc/hidden_buffer.v`(56행) · `pose_buffer.v`(25행) 구현·검증 완료, 기존 22 TB 회귀 통과, 기존 RTL 무변경. **FC1 weight FIFO 는 내 명세의 모순 때문에 미구현** — 아래 판정으로 해소. Y4/Y5 215건 검사 통과 |
| **F-01 — 내 명세 모순 (8번째 지적)** | Y2 에 "full 상태에서 write·read 를 같은 cycle 에 해도 **512개 유지**" 라고 썼는데, Y3 의 "`fifo_we && fifo_full` 이면 데이터가 사라진다" 와 **동시에 만족할 수 없다.** full 에서 동시 push/pop 이면 write 를 버려 511 이 되거나, write 를 받아 512 를 유지하는 대신 r33 계약을 깨는 수밖에 없다. **판정: Codex 권장안 채택 — full 이면 write 를 버리고 pop 만 수행(→511), full 미만에서만 동시 push/pop 이 점유량을 유지한다.** 근거: 08_FC r33 "레벨; **1이면 push 금지**" 이고 T-05 에서 Top FSM 이 `overflow=0` 으로 실제로 안 밀어넣는 것이 확인됐다. **full+pop 예외는 도달하지 않는 경우라 로직을 추가하지 않는다** |
| **F-01 — 내 명세 누락 (hidden 읽기 폭)** | 내 명세는 hidden 버퍼를 "bank 당 128 x 8 bit" 로만 적고 **읽기 폭을 쓰지 않았다.** 실제 XLSX `08_FC` r98/r99 는 **`hidden_raddr` 5-bit / `hidden_rdata` 64-bit** 다 — byte 쓰기 / **8-byte 읽기**. FC MAC 이 64-bit weight word 에 맞춰 활성값 8개를 한 번에 읽어야 하므로 당연한 구조인데 내가 빠뜨렸다. Codex 가 원문을 찾아 올바르게 구현했다(제가 r98/r99 를 직접 대조 확인) |
| F-01 구현 확인 | `hidden_buffer`: 쓰기 `waddr[7:0]`/`wdata[7:0]`, 읽기 `raddr[4:0]`/`rdata[63:0]`, bank 선택 입력 2개. **256 byte / 32 word 전량 일치, 낮은 주소가 word 하위 byte, 읽기 지연 1 cycle.** `pose_buffer`: 24 byte, `pose_data[191:0]` 에서 **byte k 가 [8k+:8]**, 부분 쓰기 시 나머지 유지. **reset 이 내용을 지우지 않는다**(hidden 256 + pose 24 byte 보존) |
| **F-01 F-03 전제 기록** | ① hidden 같은 word 동시 읽기·쓰기는 **8개 lane 전부 read-first**, 새 값은 다음 read 에서 나온다 ② 미사용 상위 주소 비트가 1 이면 **쓰기 무시 / 읽기 0** — 유효 주소로 alias 되지 않게 했다(Codex 추가, 좋은 판단) ③ `pose_data` 는 레지스터 배열의 조합 출력이라 **clocked read 포트가 없다** — 쓰기 edge 전에는 이전 값, 후에는 새 값 |
| **F-01 완료** | `fc1_weight_fifo.v`(85행) 추가로 FC 저장소 3종 완성 / Claude 검수 통과. **검사 80,662건 / 10,990 cycle**, 기존 22 TB 회귀 통과(runner 8개 전부 exit 0). `hidden_buffer`·`pose_buffer` **무변경**이고 Y4/Y5 관측값이 `checks=215 cycles=663` 로 동일 — 코드 블록 단위 해시까지 남겼다 |
| **F-01 내 판정이 검증됨** | full 동시 write+read → **점유량 512→511**, 버려진 word(`deadf011bad00001`)가 **나중에 나오지 않고**(`dropped_word_seen=0`) **기존 512 word 는 온전**(`all_512_valid_words_preserved=1`). full+write 만 → 512 유지, 역시 유실 word 미출현. 내가 요구하지 않은 `all_512_valid_words_preserved` 까지 확인한 것이 좋다 |
| F-01 FIFO 추가 검증 (요구 밖) | **empty 에서 동시 push+pop 64회** — `occupancy 0→1`, `FWFT_no_bubble=1`(내가 안 물어본 코너) · 랩어라운드 **4바퀴**(요구 3) 2,559 word 순서 일치 · **난수 stall 4,096 cycle**(seed `F0015128`, 재현 가능) · 동기 reset 이 **포인터만 0, 저장 내용 유지** |
| F-01 합성 | FIFO 단독 LUT **104** / FF 93 / **RAMB36 1** / WNS **+2.641 ns**(제가 재현). 3종 묶음 LUT 170(Logic 106 + **LUTRAM 64**) / FF 349 / RAMB36 1 / WNS +2.615. 래치 0 / 조합 루프 0. **FIFO→BRAM36 1, hidden→LUTRAM 64, pose→레지스터** 로 각각 적절한 자원에 들어갔다 |
| **⚠️ F-03 을 위한 발견 — 내 이전 주장이 틀렸다** | 내가 "`requant_stage`/`gelu_stage` 는 동우 것을 그대로 쓴다"고 여러 번 말했는데 **그대로는 못 쓴다.** 동우 `requant_stage.v` 는 `acc_tag` 가 **19-bit** `{rx,layer,oc[4:0],h,w}` 이고 param 주소를 **`layer ? 16+oc : oc`** 로 만든다 — **Encoder 전용 base(0/16)** 다. 명세 08_FC 는 `acc_tag` **9-bit** `{fc_sel[1:0], out_idx[6:0]}`, param 주소 **base(FC1 48 / FC2 176 / FC3 304) + out_idx**(r75) 다. `out_idx` 는 0~127 인데 `tag0_oc` 는 5-bit 라 **어댑터로도 못 맞춘다** |
| **F-03 requant 처리 방향 — 2026-09-26 사용자 확정 (A)** | `requant_stage.v` 를 **파라미터화**한다. tag 폭·tag 안의 필드 위치·param base 만 파라미터로 빼고, 기본값을 현재 Encoder 동작으로 두어 Encoder 경로는 무변경으로 만든다. 산술(bias 덧셈 → mult → 라운딩 shift → ±127 saturate)은 **Encoder 와 FC 가 완전히 동일**하므로 한 곳에 둔다(`full_pose.cpp:81` `requant_acc_int` 가 Conv·FC 공용인 것으로 확인). 안전망은 **`tb_golden_encoder`(G-02)** 의 비트 일치다 |
| **⚠️ F-03 — `gelu_stage` 는 파라미터화 대상이 아니다 (Claude 가 원문·구현 직접 확인)** | requant 와 달리 `gelu_stage.v` 는 **출력측이 전부 Encoder 전용**이다 — `fmap1_we`/`fmap1_waddr[14:0]`(`row1*10 + w` Conv1 전용 주소식)/`fmap1_last`(`oc==15 && h==127 && w==9`)/`pool_q`/`pool_valid`/`pool_tag`. 명세 08_FC r87~r89 의 FC 측 출력은 **`hidden_we`/`hidden_waddr[7:0]`/`hidden_wdata[7:0]`** 뿐이라 겹치는 신호가 없다. 공유되는 것은 **LUT 2-cycle 조회 3행**(`{table[1:0], ~rq[7], rq[6:0]}`)뿐이다. **판정: `fc_gelu_stage.v` 를 별도로 만든다.** 이것은 (A) 결정과 모순되지 않는다 — (A) 는 requant 에 대한 결정이고, gelu 는 파라미터화할 공통부가 없다 |
| F-03 GELU LUT table 배정 (확정, blob 원문 근거) | LUT RAM 1024 byte = 256-byte table 4개이고 blob 적재 순서가 그대로 주소다: word **105,492** `lut.encoder.gelu1` → **table 0**, 105,556 `lut.encoder.gelu2` → **table 1**, 105,620 `lut.head.gelu1` → **table 2 = FC1**, 105,684 `lut.head.gelu2` → **table 3 = FC2**. Encoder `gelu_stage.v:47` 이 `{1'b0, layer, ...}` 로 table 0/1 을 쓰는 것과 일치한다. 따라서 **`fc_lut_raddr = {1'b1, (fc_sel==2'd1), ~rq[7], rq[6:0]}`** 다(FC1→2, FC2→3). `full_pose.cpp` 가 FC1 에 `g_lut_head_gelu1_int8`, FC2 에 `g_lut_head_gelu2_int8` 를 쓰는 것으로 교차 확인했다. **FC3 는 GELU 를 통과하지 않는다**(r72~r75) |
| F-03 Param base 확정 (구현 교차 확인) | `blob_decoder.v:100/109/118` 이 실제로 **FC1 48 / FC2 176 / FC3 304** 에 적재한다 — 원문 r75 와 일치. 48+128+128+24 = **328** = `param_ram` 깊이와 정확히 맞는다. Encoder 는 0~15(Conv1) / 16~47(Conv2) 를 쓴다. `fc_param_rdata` 96-bit = **{shift[31:0], mult[31:0], bias[31:0]}** (r67/r68, `requant_stage.v:28~30` 과 동일 배치) |
| **F-03a 기능 완료 / 타이밍 기준으로 중단 (Claude 검수 통과)** | `requant_stage.v` 파라미터화 완료. **FC golden 280개(128+128+24) 전량 일치, 불일치 0**. 27 case / 결과 1,135개 / 검사 208,354건 / 222,847 cycle. 제가 시뮬레이션을 재현했다(같은 수치, `$finish` 도달). 기존 24 TB 무수정 통과, 보호 **390 파일 무변경**(변경은 승인된 `requant_stage.v` 1개뿐). **판정: F-03a 의 RTL·TB 산출물은 그대로 인수한다.** 미달한 것은 제가 넣은 +1.0 ns 중단 게이트이고, 그 원인은 F-03a 가 만든 것이 아니다 |
| **F-03a — Encoder 무변경이 netlist 수준에서 증명됐다** | `CNN_Encoder` OOC 합성 전/후가 **LUT 6490(27) / FF 3530 / BRAM 13 / DSP 10 / WNS −3.641 / TNS −447.829 / 실패 endpoint 684 / logic level 31 (CARRY4=23 …) / 임계 경로 `u_enc_rq/param3_reg[69]/C → u_enc_rq/rq_reg[1]/R` 까지 전부 동일**(제가 두 로그를 직접 대조). `tb_golden_encoder` flat 384 word 비트 일치, `tb_encoder_equiv` 2,557,780 에지 불일치 0, Encoder 5개 파일 SHA-256 무변경. `// stage 1, acc + bias` ~ `endmodule` **1,707 byte byte 일치**(제가 `others/CNN_Encoder/requant_stage.v` 원본과 직접 비교). **(A) 파라미터화는 위험이 없었다** |
| **⚠️ F-03a 핵심 발견 — requant stage 3 이 100 MHz 단일 병목이다 (Encoder·FC 공통)** | FC requant 단독 **WNS −3.494 ns / 실패 endpoint 15**, MAC+RQ 묶음도 **−3.494 ns**. 임계 경로가 Encoder 와 **구조까지 같다** — `u_rq/param3_reg[69]/C`(= **shift[5]**) → `u_rq/rq_reg[1]/R`, data path **12.886 ns**(logic 5.885 / route **7.001 = 54%**), logic level **31**, **CARRY4 23개**. 즉 제한하는 것은 tag·주소 변경이나 MAC 이 아니라 **기존 stage 3 의 가변 shift·라운딩·포화 한 단**이다. **따라서 한 곳을 고치면 Encoder(−3.641)와 FC(−3.494)가 동시에 풀린다** — E-02 는 이제 선택 최적화가 아니라 **D10 클록과 X-03b 를 막는 항목**이다 |
| F-03a 타이밍 해석 (미확정) | 위 수치는 **합성 단계 추정**이고 route 가 54% 를 차지한다. 임계 경로는 모듈 내부 reg→reg 이라 OOC 의 I/O delay 2 ns 가정과 무관하다. logic 5.885 ns 는 고정이지만 route 7.001 ns 는 P&R 에서 크게 줄 수 있다 → **P&R 1회면 실제 값이 나온다.** 현재 수치만으로 최대 주파수를 73~74 MHz 로 확정하지 않는다. `rq_reg[1]/R` 로 끝나는 것은 Vivado 가 음수 포화(−127 의 bit1 = 0)를 FF 동기 reset 핀으로 매핑한 결과로 보이며 비정상이 아니다 |
| F-03a 검증 충실도 | **saturation 은 실측 golden 으로 0/280** 이라 전혀 안 걸린다 — 합성 acc 로 15 case 시험, **하한이 −128 이 아니라 −127**(`sat_int8` 일치) 확인. 라운딩은 양수 `+half` / 음수 `−half` 후 산술 shift 를 부호별로 확인(`acc=−2, shift=1 → −2`. 대칭 반올림과 다르지만 `full_pose.cpp:48` 과 일치). **이 blob 에 없는 `shift <= 0` 분기도 합성값 4개로 시험**해 통과. TB 기대값은 RTL 식을 복사하지 않고 독립 계산했다. Param 변형 9 case(bias/mult/shift × 3 레이어) 각각 **해당 출력 1개만** 변화 |
| F-03a — Codex 의 11번째 지적 (옳다) | 제 명세의 "`acc × mult` 최대 **50 bit**"는 **magnitude 기준**일 때만 맞다. 실제 최대 곱은 FC3 **840,429,470,483,895** 이고 **signed 최소 폭은 51-bit**다(FC1 50 / FC2 48). 제가 독립 계산해 확인했다. 기존 산술이 signed 64-bit 이므로 수정은 불필요하다 |
| F-03a pose 최종값 확정 | FC3 requant 출력 24개가 `fc3_i8.hex` 와 일치하므로 **pose 정수값은 이제 RTL 에서 맞게 나온다**(저장·완료 제어만 남았다). PS 변환식은 **`pose_f32[o] = float32(int8(rq[o]) × output_scale)`**, `output_scale` = blob **word 4** = `0x3BD997A8` = **0.006640393286943436**. Codex 가 float32 비트까지 **24/24 개 `pose_f32.hex` 와 일치**시켰다(제가 Python 으로 비율 0.006640393 을 교차 확인). **RTL 에 float 곱셈은 넣지 않는다** |
| F-03a 자원 | FC requant 단독 LUT **966**(LUTRAM 9) / FF 157 / **DSP 7** / BRAM 0. MAC+RQ 묶음 LUT 1742 / FF 773 / DSP 7. 래치 0 / 조합 루프 0. **DSP 를 강제하지 않았다** — 곱셈은 signed 64-bit × signed 32-bit 이라 "32×32 하나"라는 제 예상과 달리 7개가 추론됐다(Codex 가 예상값으로 수를 정하지 않고 실측 보고). F-02 의 INT8 MAC 곱은 계속 LUT 다. 합성 fixture 의 RAM 은 외부 포트여서 **BRAM 0 을 FC 전체 저장소 자원으로 읽으면 안 된다** |
| **E-02a 완료 (측정 전용, RTL 무변경) / Claude 검수 통과** | P&R post-route 실측. **보호 394 파일 변경·추가·삭제 0**, 기존 `syn_check.tcl`·`timing_100mhz.xdc` 무변경. 신규 `syn/impl_check.tcl`. 모든 실행의 exit code·wall-clock·전문 보존(실패 시도도 숨기지 않았다). 제가 7개 실행의 `post_route_summary.rpt` 를 직접 열어 WNS·TNS·실패 endpoint·WHS 를 전부 대조했다. `rtl/pose_cnn_v1_0_{S00,M00}_AXI.v` 의 mtime 이 20:24 로 감사 이후인 것을 발견해 내용 해시를 F-03a 기록과 비교했다 — **내용 동일, mtime 만 변한 것**이다(E5 의 `read_verilog` 때문). 문제 없다 |
| **⚠️ E-02a 최대 발견 — 내 전제가 틀렸다. requant 는 단일 병목이 아니다** | 제가 "requant stage 3 이 100 MHz 단일 병목이고 한 곳을 고치면 Encoder·FC 가 동시에 풀린다"고 했는데 **Encoder 에서는 틀렸다.** 실패 endpoint 분해(제가 합계를 검산: 15+571+899 = **1,485** = 보고서 값): **`u_conv_mac` 899개 (최악 −3.028)** · **`u_pool` 571개 (−3.488)** · **`u_enc_rq` 15개 (−3.562)**. 즉 requant 를 고쳐도 Encoder 는 **−3.562 → −3.488(Pool)** 로 **0.074 ns** 밖에 안 좋아진다. **100 MHz 는 서로 다른 3개 경로를 다 고쳐야 한다.** 반면 **FC 묶음은 실패 endpoint 15개 전부가 requant** 라 FC 만은 requant 수정으로 해결된다 |
| **E-02a 판정 — 71.43 MHz 는 오늘 통과한다** | `CNN_Encoder` OOC P&R, **14.000 ns 에서 WNS +0.182 / WHS +0.082 / 실패 endpoint 0 / 8,782 net 완전 배선 / 배선 오류 0 / 래치 0 / 조합 루프 0**(제가 `clocks.rpt` 로 주기 14.000 적용까지 확인). 13.500 ns 는 −0.052 로 사실상 문턱. 100 MHz 는 Encoder **−3.562(기본) / −3.160(성능 directive)**, FC **−2.413 / −2.133**. 추론 시간: 100 MHz 13.383 ms → **71.43 MHz 18.736 ms (1.40×)**, 74.07 MHz 18.067 ms. cycle 은 기존 실측 1,338,265 를 사용한 계산값이다 |
| E-02a — 내가 틀린 것 3가지 더 (Codex 12번째 지적 포함, 전부 옳다) | ① **"route 7.001 ns 는 합성 추정이라 P&R 에서 줄 여지가 있다"** → 반대였다. post-route 에서 **7.733 ns (59.7%)** 로 **늘었다** ② **"logic 5.885 ns 는 고정"** → 배치·pin mapping 에 따라 바뀐다(실측 5.221~5.501) ③ **E6 의 구간 순서가 틀렸다** — RTL 은 `half` 를 만들어 **더한 뒤에** 오른쪽 shift 를 하므로 내 ㄱ(Q→shift 진입)과 ㄷ(half 가감)은 **겹친다**. 더하면 중복이다 ④ "동일한 한 핀이 항상 최악"도 아니다 — 기본 Encoder 는 `param3[68]`(**shift[4]**), 성능 Encoder 는 **Pool**, 성능 FC 는 곱셈 결과 FF 가 최악이 됐다 |
| E-02a 구간별 지연 (post-route, 기본 10 ns) | 발사 FF C→Q / half 디코드 / half 가감 carry / 가변 shift·부호 mux / 포화 비교→도착 FF = Encoder **0.419 / 1.899 / 2.486 / 4.329 / 3.821 = 12.954**, FC **0.518 / 1.869 / 2.328 / 3.234 / 3.856 = 11.805**(보고서 Data Path Delay 와 0.001 ns 해상도 일치). **가장 긴 구간이 Encoder 는 가변 shift, FC 는 포화 비교로 서로 다르다.** 한 곳만 잘랐을 때 남는 최장 구간: **Encoder 8.150 ns / FC 7.090 ns** → **FC 는 1회 분할로 가능성이 있지만 Encoder requant 는 1회로 부족하다**(새 FF·배선·setup 미포함 산술값) |
| **E-02a → Claude 가 검수 중 찾은 지렛대: `pool_shift`/`pool_mult` 는 LOAD 후 상수다** | Pool 의 최악 경로 571개는 시작점이 **`pool_shift[5]` = OOC 입력 포트**이고 **인위적 `set_input_delay` 2 ns** 를 그대로 받는다(Codex 도 OOC 한계로 지적). 더 중요한 것: `blob_decoder.v:270/272` 가 **헤더 beat 에서만** `pool_mult_reg`/`pool_shift_reg` 를 쓰고 이후 유지하며, Top FSM 은 LOAD 완료 후에야 ENC 로 간다. 즉 **INFER 동안 완전히 정적**이다 → **`set_multicycle_path` 가 정당하다.** 실패 endpoint 의 **38%(571/1,485)가 RTL 없이 제약만으로 사라질 수 있다.** 통합 설계에서 확인 필요 |
| E-02a 남은 미지 — Conv MAC | `u_conv_mac` 899개, 최악 **−3.028**, 경로 `u_input_buf/gen_word_write.mem_reg_*/CLKBWRCLK → u_conv_mac/g_lane[*].lane_out_reg[29]/D` 로 **모듈 내부**다(OOC 인공물 아님). 단독 `Conv_MAC` 합성의 +1.093 ns 를 통합 배치의 보장값으로 쓰면 안 된다. **이것이 logic depth 문제인지 배치·배선 문제인지는 아직 모른다** — 내 명세가 `-max_paths 3` 만 요구해 전문이 requant 3개로 채워졌기 때문이다(내 범위 설정 한계). 100 MHz 로 가려면 이 구분이 첫 질문이고, **Conv MAC 은 동우의 핵심 연산 블록**이다 |
| E-02a E5 실패 (전체 코어 수치 없음) | `pose_cnn` + `tb/fc_stub.v` 합성이 `fc_stub.v:76` 문자열 처리에서 `Synth 8-281` 로 실패(exit 1, 18.05 s). Codex 가 실행 전에 이 위험을 밝혔고 모형을 합성용으로 고치지 않았다(올바른 판단). **따라서 전체 코어 배치가 더 나빠지는지는 여전히 미측정**이다. 실물 FC 통합(X-02b) 후에 측정해야 한다 |
| E-02a OOC 한계 (판정에 반영할 것) | 제약에 `HD.CLK_SRC`·`HD.PARTPIN_LOCS` 가 없어 `Timing 38-242`·`Route 35-198` 경고가 있고 clock 및 일부 입력 net 이 `unset` 이다. 따라서 **clock insertion/skew 와 외부 포트 경로는 실제 BD/보드 값이 아니다.** 특히 Pool 입력 경로와 그로 계산한 Fmax 가 직접 영향을 받는다. **71.43 MHz 는 "측정한 OOC 조건에서의 통과점"이고 보드 보증값이 아니다** |
| **F-02 를 위한 발견 — bias 위치** | golden `fc1_acc_i32` 는 **bias 포함**이다(`full_pose.cpp:559` `acc = bias + acc0..3`). 반면 RTL `requant_stage.v` 는 **stage 1 에서 `acc + bias`** 를 하므로 **MAC 의 `acc` 출력은 bias 없는 순수 Σ(a·w)** 다. 따라서 F-02 대조는 **`MAC.acc + blob 의 bias`** 대 golden 이어야 한다. 이걸 놓치면 128+128+24 전부 불일치로 나온다 |
| **F-02 완료** | `rtl/fc/fc_mac.v`(203행) 신규 / Claude 검수 통과. golden 누산 **280개(128+128+24) 전량 일치, 불일치 0**. 실제 F-01 FIFO·hidden 버퍼·Loader `fcw_ram` 을 붙여 검증했고 bias 는 TB 에서만 더했다. **12 case / 결과 1,224개 / assertion 2,128,172건 / 320,872 cycle**. 기존 23 TB 무수정 통과, 보호 **389 파일 SHA-256 무변경**. 제가 시뮬레이션을 재현했다(같은 수치, `$finish` 도달) |
| **F-02 — Codex 가 내 명세의 산술을 고쳤다 (9·10번째 지적, 둘 다 옳다)** | ① 내가 "int8×int8 최대 **16,129**(127²)" 라고 썼는데 **(−128)² = 16,384** 가 더 크다. 따라서 FC1 최대 순수 합은 내가 쓴 ~49.5 M 이 아니라 **50,331,648**, 최소는 **−49,938,432** 다 ② 8개 곱의 합 최댓값 **131,072** 는 signed 18-bit 최대 **131,071** 을 **1 만큼 넘는다** — group sum 은 **19-bit** 여야 한다. 제가 Python 으로 독립 검산해 둘 다 확인했다. `sum_reg` 는 signed 19-bit 로 구현됐다 |
| **F-02 — 내 명세 표기 오류** | Z3 에 FC3 tag 를 `{2'b10, o[4:0]}`(7-bit) 로 썼는데 같은 명세의 완료 조건 #4 와 원문 r57 은 **9-bit `{fc_sel[1:0], out_idx[6:0]}`** 다. Codex 가 9-bit 로 구현했다(FC3 유효 tag `0x100~0x117`). **같은 명세 안에서 내가 두 가지로 적은 것이다** |
| F-02 파이프라인 | 입력 발행 edge **E** 기준 E+1 operand / E+2 곱 8개(16-bit) / E+3 pair(17-bit) / E+4 quad(18-bit) / E+5 group sum(**19-bit**) / E+6 누산(32-bit). `{first,last,last_layer,tag[8:0]}` 12-bit 메타데이터를 같은 단계로 이동시킨다. **`acc_valid` 간격 384/16/16 cycle**, `mac_done` 은 마지막 `acc_valid` **다음 cycle 1-cycle**. FIFO empty 면 새 발행만 멈추고 이미 받은 데이터는 계산을 끝낸다 |
| F-02 추가 검증 (요구 밖 포함) | FIFO empty **7,351 cycle** 정체 후에도 weight 49,152개 순서대로 소비·golden 128개 재일치(완료가 정확히 7,351 cycle 증가) · empty 중 read 자극 **7,358회**에 읽기 포인터 불변 · 활성/weight 한 byte 변형을 **레이어별로 각각** 수행하고 `변화량 × 대응 계수` 독립 기대값과 전량 대조(단순히 "달라졌다"로 넘기지 않았다) · 활성 −128 / weight −128·+127 극값으로 **+50,331,648 / −49,938,432** 이론값 일치 · case 사이 reset 없이 재시작해 파이프라인 잔류 없음 확인 |
| F-02 음수 검증 | 실제 데이터에서 FC1 **95/128**, FC2 **81/128** 이 음수 누산(합계 176개). **FC3 는 24개 전부 양수** 임을 숨기지 않고 보고했다. 제가 blob·golden 으로 독립 계산해 `pure_min/max`·음수 개수·bias 범위가 전부 일치함을 확인했다 |
| F-02 합성 | `fc_mac` 단독 LUT **799** / FF 616 / BRAM 0 / **DSP 0** / WNS **+3.895 ns**. MAC+저장소 묶음 LUT 955(LUTRAM 64) / FF 965 / RAMB36 1 / DSP 0 / WNS **+3.857 ns**. 래치 0 / 조합 루프 0(제가 보고서에서 재확인). **DSP 를 강제하지 않았고 Vivado 는 8개 INT8 곱을 LUT 로 구현했다** — Conv_MAC 의 use_dsp 강제 사례를 고려한 판단이다. 두 WNS 모두 중단 기준 +1.0 ns 이상 |
| **F-02 → F-03 인계: hidden 버퍼 어댑터 (내 F-01 명세의 이탈)** | 원문 08_FC 는 hidden 주소를 **packed** 로 정의한다 — 쓰기 `hidden_waddr` **8-bit `{bank, idx[6:0]}`**(r96), 읽기 `hidden_raddr` **5-bit `{bank, word[3:0]}`**(r98). 그런데 내가 F-01 에서 **별도 `hidden_wbank`/`hidden_rbank` 포트**로 명세했고 구현은 `waddr[7]`/`raddr[4]` 를 **쓰지 않는다**. 더구나 `write_enable = ... && !hidden_waddr[7]` 이라 **packed 주소를 그대로 주면 bank1 쓰기가 조용히 무시된다**(= FC2 출력 소실 → FC3 가 0 을 읽음). **F-03 은 `.hidden_wbank(waddr[7]), .hidden_waddr({1'b0,waddr[6:0]})` / `.hidden_rbank(raddr[4]), .hidden_raddr({1'b0,raddr[3:0]})` 로 분해해 연결해야 한다.** Codex 가 F-02 TB 에서 읽기측을 이렇게 연결하고 명시적으로 알려왔다 |
| **T-01 (이전 단계)** | 기존 1클록 BUSY 구현 및 검증 기록은 [이전 보고서](cnn_rtl/docs/T-01_구현_검증기록.md)에 보존. 당시 busy COMMAND commit 도달 불가 제약은 T-01R의 2cycle busy에서 해소됨 |
| **T-02a** | **구현·자체 검증 완료 / Claude 검수·사용자 확인 대기.** `tb/axi4_slave_mem_model.v`·`tb/tb_axi4_slave_mem_model.v` 신규. AXI 37포트 이름·폭·반대 방향 일치, clock/reset 별도 2포트 대응. 희소 메모리·AW/W 독립 수락·지연/난수 stall·1회 오류 주입·C1~C12 구현. A/B/C/D 전부 PASS, 필수 음성 6/6·전체 13/13 각각 카운터 +1. xvlog -sv/xelab 오류·경고 0. [T-02a 검증 기록](cnn_rtl/docs/T-02a_구현_검증기록.md) 참조 |
| T-02a 검증 범위 | 같은 seed의 WREADY 44관측/28stall 반복 일치, 전체 재실행 PASS/위반 기록 49줄 동일. 미허용 위반 및 1회 허용 뒤 재발 모두 별도 fatal 실행 확인. C10 부족 판정은 시험 종료 선언 또는 명시한 deadline 사용(기본 timeout 0). 기존 RTL 3개/기존 TB 6개 해시 보존. 실물 M00 include/instantiate·합성·FC1 처리율 측정 없음. DDR 지연값 미확정 |
| **T-02b** | **TB 구현·실행 완료 / 명세 문구·구현 차이 검수 필요.** `tb_m00_read.v`·`tb_m00_read_perf.v` 신규. 실물 M00 ↔ 모형 AXI 37선 직결, C11 활성. 기능 12건/4,511 word/289 AR 전량 대조 PASS, LOAD 47/187 burst. 프로토콜 위반 0. RTL·모형·기존 TB 11파일 해시 보존. [T-02b 검증 기록](cnn_rtl/docs/T-02b_구현_검증기록.md) 참조 |
| T-02b 처리율 | 정렬 주소 0x1E100000, 393,216 B/49,152 beat/3,072 burst, ready=1. DDR 지연 0/16/32/64에서 평균 **1.125/2.125/3.125/5.125 cycle/beat**. 총 55,296/104,448/153,600/251,904 cycle, 100 MHz 환산 552.96/1,044.48/1,536.00/2,519.04 µs. 0 조건만 <1.2; 나머지는 >1.5로 다중 outstanding 검토 근거. 실제 DDR 지연·변경 여부 미확정. xsim 4회 wall-clock 합계 18.948 s |
| T-02b 검수 항목 | ① R3 “마지막만 짧음”은 4 KiB 경계에서 중간 burst가 짧아지는 예외가 필요(원문 r70 준수) ② M00 145행 RREADY는 RD_DATA 상태에서만 mem_rd_ready와 같아 r14/r70의 무조건 직결 문구와 다름. 유효 데이터 전달·stall 기능은 PASS. **전체 문자 계약 PASS로 처리하지 않음** ③ 실제 FC1 base+5,936은 독립 계산상 3,073 burst; 위 표는 정렬 기준선이며 실제 offset 실측이 아님. RTL/모형 수정 없음 |
| **T-02c** | **TB 구현·실행 완료 / W5 문구 불일치 검수 필요.** `tb_m00_write.v` 신규. 11조건·669 word/49 AW, 실제 M00 read-back 및 mem_compare 전량 일치, 앞뒤 guard 22 word 미기록 유지. B delay=12에서 마지막 W 이후 busy 13 cycle 유지. 기존 read 12/12 재통과(판정·관측 53줄 동일). 컴파일·elaboration 오류·경고 0, 모형 위반 0, 최종 quiescent 통과. 기존 RTL/TB/모형 13파일 해시 보존. [T-02c 검증 기록](cnn_rtl/docs/T-02c_구현_검증기록.md) 참조 |
| T-02c W5 관측 | ready HIGH 샘플 669 = W 수락 669 = producer 증가 669. 그러나 HIGH 구간은 91개, 최장 16 cycle로 **‘연속 2 cycle 금지’는 8조건에서 실패**. 데이터 손상 없이 연속 beat를 수락한 결과이며 `ready=WVALID&&WREADY`와는 일치한다. 문구 명확화 또는 고립 펄스 설계 요구 결정이 필요. **TB는 전체 무결성 확인 후 fatal로 끝나며 전체 PASS로 처리하지 않았다.** RTL·모형·원문 변경 없음 |
| **T-02d** | **구현·자체 검증 완료 / Claude 검수·사용자 확인 대기.** `tb_m00_err.v` 신규. E1~E9 22 case PASS, 주입 8회, 실물 M00 프로토콜·C12 위반 0, `expect_violation` 미사용. 최종 compile/elaboration 오류·경고 0. 기존 read/write/모형 자체시험 3개 모두 재통과, 기존 RTL/TB/모형 14파일 해시 보존. write는 Claude가 보정한 W5 버전을 그대로 재실행했다. [T-02d 검증 기록](cnn_rtl/docs/T-02d_구현_검증기록.md) 참조 |
| T-02d D08 근거 | 중간 RRESP/RID/BRESP/BID 오류에도 48 beat/3 burst 전체 완료. err는 다음 START 수락 에지 직후 clear. 이른/누락 RLAST는 RD_FAULT에서 2,000 cycle busy=1 유지, START/READY로 탈출 불가, 공통 reset 뒤 새 read 정상. watchdog=8은 err만 설정하고 AXI 취소 없이 응답 재개 뒤 완료. 전송 중 공통 reset 복구 및 이미 쓴 5 word 보존 확인. **M00 단독 reset 안전성·실제 reset 범위·D08 정책은 미결** |
| **T-03** | **구현·자체 검증 완료 / Claude 검수·사용자 확인 대기.** Top의 LD_RD1/LD_RD2/LD_WAIT 구현, Loader stub 및 실물 M00 통합 TB 추가. 통합 10조건·회귀 10 TB PASS. 정상 LOAD 3,722 word 전량 대조, AR 47+187=234, 통합 프로토콜/C12 위반 0. [T-03 검증 기록](cnn_rtl/docs/T-03_구현_검증기록.md) 참조 |
| T-03 사용자 승인 보정 | 오류 시 즉시 FINISH 대신 현재 LD_RD 상태에서 `ld_valid=0`, `mem_rd_ready=1`로 임시 drain 후 FINISH. LOAD 중 Loader done과 같은 cycle의 error를 보관해 LD_WAIT 이전 펄스도 처리. **D08 전체 결정 아님**. 오류로 중단된 Loader 재시작 및 RD_FAULT 탈출은 해결하지 않음 |
| T-03 합성·보존 | xc7z020 / 잠정 100 MHz OOC: LUT146 / FF77 / BRAM0 / DSP0 / WNS +1.986 ns, 래치·조합 루프 0. S00/M00/메모리 모형/Encoder 무변경. 기존 15개 소스 중 승인 수정 3개 외 12개 해시 동일. 상태/CSR TB만 LOAD handshake와 busy 기대값 갱신 |
| **T-04** | **구현·자체 검증 완료 / Claude 검수·사용자 확인 대기.** IN_RD 입력 read/11-bit beat 주소 및 ENC 구동, input RAM/Encoder stub·통합 TB 추가. INFER 13조건·15회와 회귀 TB 12개(21 xsim 실행) PASS. 입력 1,440 word 전량 일치, 정렬 90/비정렬 91 AR, 통합 AXI/C12/RAM 위반 0. [T-04 검증 기록](cnn_rtl/docs/T-04_구현_검증기록.md) |
| T-04 완료·오류 관측 | 동기식 지연 0/5/100/1000, 1-cycle/레벨 done과 reset 없는 연속 실행 PASS. 중간 RRESP 오류는 RAM 21 word 이후 중지·1,419 beat drain, 마지막 beat 오류도 Encoder 시작 0·error=4. **오류 beat 자체는 M00의 등록된 err보다 먼저 RAM에 쓰일 수 있음.** D08 전체 재시작 정책을 확정한 것은 아님 |
| T-04 합성·보존 | xc7z020/잠정 100 MHz OOC: LUT239 / FF120 / BRAM0 / DSP0 / WNS **+1.734 ns(T-03 대비 −0.252 ns)**, 래치·조합 루프 0. 기존 31파일 중 승인 수정 3개 외 28개 해시 동일. LOAD 10조건 관측값도 그대로 유지. ENC는 T-05 전까지 임시 FINISH이며 FC/pose 출력은 없음 |
| **T-05 현재** | **FC1·D06 구현 및 독립 검증 완료, P7/P9 보정 답변 대기.** 신규 통합 11조건·14 INFER, 정상마다 push/pop 49,152 word 전량 일치. 느린 소비 full 145,322 cycle, 정지/재개 최대 연속 full 1,427 cycle. 통합 위반 0. [T-05 구현·검증 기록](cnn_rtl/docs/T-05_구현_검증기록.md) |
| T-05 미완료 조건 | **P7:** RRESP 오류 후 1,285 word에서 push 중지, 47,867 beat drain·error=4는 통과했으나 FC는 active에 남는다. reset·재LOAD를 복구 시험으로 인정할지 답변 대기. **P9:** 무수정 `tb_top_infer`는 FC 출력 0 기대와 충돌하여 case 0에서 실패. 입력 13조건 유지+FC1 fixture 최소 수정 허용 여부 대기. 파일을 보존했으며 전체 회귀 통과로 쓰지 않음 |
| T-05 합성·보존 | xc7z020/잠정 100 MHz OOC: LUT362 / FF158 / BRAM0 / DSP0 / WNS **+1.408 ns(T-04 대비 −0.326 ns)**, 래치·조합 루프 0. 임계 `weight_addr_reg[6] → mem_rd_addr[28]`. 중단 기준 1.0 ns보다 높음. 기존 회귀 12 TB PASS, 보호 31파일 해시 동일, 포트 45개·상태 인코딩 13개 유지. [FC 요구사항 초안](cnn_rtl/docs/T-05_FC_요구사항_초안.md) 작성만 했으며 전달·Notion 등록하지 않음 |
| 다음 소단계 예고 | **T-06: FC2/FC3와 pose 출력 write(WR). 미착수.** 현재 T-05의 남은 조건과 사용자 확인을 먼저 처리한다 |
| Top FSM 분할 예정 | T-01R 골격/상태 → T-02a 모형 자체 시험 → T-02b read/처리율 → T-02c/d 실물 M00 후속 검증 → T-03 LOAD → T-04 IN_RD/ENC → T-05 FC1(**D06 확정**) → T-06 FC2/FC3/WR → T-07 ERR_DRAIN(**D08**). 이번 승인·구현 범위는 T-05뿐 |
| Loader | 보류. 재개 시 L-01(beat 카운터·구간 판별·`ld_ready`) 명세가 준비되어 있다. 상주 RAM은 **D09** 필요 |
| 병렬 진행 | D09 질문 2건을 동우·지원에게 지금 전달해 두면 Loader 재개 시 막히지 않는다 |
| D01–D05 | **2026-09-24 확정 완료** (5.1절). S00-05는 5.1절의 판정표·규칙대로 구현한다. 정렬 검사도 S00-05에 포함한다 |
| 민영 전달 | 5.1절의 **PS 시퀀스 규격**을 구현 규격으로 전달한다. 질의가 아니다 |
| 남은 미결 | D08·D09, D10의 클록·최종 출력, D07의 reset 생성·공급 구현. D06 LOAD base 보관 및 D07 동기식 active-low reset 방식은 확정. 각 미결 항목은 해당 구현·통합 전에 결정한다 |

향후에는 이 표의 현재 단계/상태와 관련 결정만 갱신한다. 완료한 단계의 설명을 공통 문서에 계속 복제하지 않고 사용자 학습 기록과 변경 파일을 참조한다.
