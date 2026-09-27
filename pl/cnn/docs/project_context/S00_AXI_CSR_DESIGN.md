# S00_AXI CSR 상세 설계

작성: 2026-09-24. **RTL 구현 전 검토안**. 공통 기준과 결정 상태는 [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md)를 따른다.

진행 규칙 갱신: 이 문서는 전체 동작을 설명하는 설계 초안이며 전체 CSR을 한 번에 작성하라는 요청이 아니다. Claude가 소단계로 나누고 Codex가 사용자 요청 범위의 한 단계만 구현한다. 설명·사용자 이해/확인·Notion 기록 후 다음 단계 진행 요청을 기다린다. 이번 갱신으로 아래 설계안이나 D01–D10의 기술 결정을 확정하지 않는다.

## 1. 범위와 근거

대상은 한림 담당 `pose_cnn_v1_0_S00_AXI`다. 기존 wrapper의 AXI 포트와 CSR 선 11개를 유지한다. Top/Loader 상태 갱신은 필요한 계약만 기술하며 다른 담당자 구현을 변경하지 않는다.

| 구분 | 이번에 확인한 원문 |
| --- | --- |
| CSR 맵·상태·pulse | `Pose_CNN_IP_Interface_Spec.xlsx`, `02_S00_AXI A5:G34` |
| AXI 폭·reset·독립 latch·응답·RO 쓰기 | 같은 파일 `02_S00_AXI A36:G66` |
| 동작·오류 코드 | 같은 파일 `00_개요 A17:G47` |
| 코어/Top 상태 소유권·메모리 완료 | 같은 파일 `04_pose_cnn A5:G73, A90:G92` |
| 실제 연결 | `IP_v1_0/IP_v1_0/rtl_template/pose_cnn_v1_0.v:91–102,126–138,184–185,227–240` |
| 코드 스타일 | 공통 문서 4절의 UART/stopwatch 대표 범위 |

XLSX의 실제 위치는 `D:\2609_final_project\IP_v1_0\IP_v1_0\interface_spec\Pose_CNN_IP_Interface_Spec.xlsx`다. PS 기존 동작과 Loader 상세는 인계 문서의 조사 결과를 재사용했다.

아래 **[명세]**는 원문에 있는 계약, **[설계안]**은 이를 구현하기 위한 구조, **[미결 Dxx]**는 외부에 관찰되거나 팀 연결에 영향을 주는 미합의 동작이다.

## 2. 레지스터 맵 — 명세 기준

byte offset, 데이터 32bit, 주소 5bit다. CSR 값과 주소는 unsigned다. scale은 부동소수 연산을 하지 않고 32bit 패턴 그대로 전달한다.

| Offset | 이름/접근 | 필드·리셋/읽기값 | 쓰기 동작 |
| --- | --- | --- | --- |
| 0x00 | CONTROL / WO | bit0 START, bit1 CLEAR_STATUS. 읽기 0 | W1P. START는 busy 중 SLVERR/pulse 없음. CLEAR 단독은 busy에도 허용 |
| 0x04 | STATUS / RO | bit0 busy, bit1 done, bit2 error, bit3 cfg_ok, [7:4] error_code, [31:8]=0. reset 0 | 무시, OKAY |
| 0x08 | COMMAND / RW | 32bit, reset 0. 0=INFER, 1=LOAD | busy 중 SLVERR, 값 보존 |
| 0x0C | INPUT_ADDR / RW | 32bit DDR base, reset 0, 8 B 정렬 | busy 중 SLVERR, 값 보존 |
| 0x10 | WEIGHT_ADDR / RW | 32bit blob base, reset 0, 8 B 정렬 | busy 중 SLVERR, 값 보존 |
| 0x14 | OUTPUT_ADDR / RW | 32bit pose base, reset 0, 32 B 정렬 | busy 중 SLVERR, 값 보존 |
| 0x18 | OUTPUT_SCALE_BITS / RO | cfg_ok=1이면 header word4/OKAY, cfg_ok=0이면 0/SLVERR | 무시, OKAY |
| 0x1C | RESERVED / RO | 읽기 0 | 무시, OKAY |

STATUS 구성은 `{24'b0, status_error[3:0], cfg_ok, (|status_error), status_done, status_busy}`다. 읽어서 done/error가 지워지지 않는다. CONTROL에는 저장용 register를 두지 않는다.

| error_code | 명세 의미 | 검출 담당 |
| --- | --- | --- |
| 0 | OK | Top 상태 |
| 1 | BAD_CMD: START 시 COMMAND가 0/1 이외 | Top |
| 2 | NO_CFG: cfg_ok=0에서 INFER | Top |
| 3 | BLOB_ERR: header/길이/shift 검사 실패 | Loader → Top |
| 4 | MEM_RD_ERR | M00 → Top |
| 5 | MEM_WR_ERR | M00 → Top |
| 6–15 | 예약 | 이번 설계에서 새 코드를 배정하지 않음 |

COMMAND에 2 등을 저장하는 것 자체를 CSR 오류로 만들지 않는다. idle에서 COMMAND 쓰기 및 START 쓰기의 AXI 응답은 OKAY일 수 있고, 그 후 Top이 BAD_CMD를 보고한다. **AXI 쓰기 수락과 CNN 실행 성공은 별개다.** busy 거부나 CSR 정렬 거부로 STATUS.error_code를 임의로 바꾸지 않는다.

## 3. 상태 소유권과 내부 구조

### 3.1 소유권 — 명세

| 모듈 | 보유/생성하는 값 |
| --- | --- |
| S00_AXI | COMMAND/INPUT_ADDR/WEIGHT_ADDR/OUTPUT_ADDR 4개, AXI 채널 보류값·응답, reg_start/reg_clear_status pulse |
| Top FSM | 실행 시 command/주소 snapshot, status_busy, sticky status_done/status_error |
| Loader | cfg_ok, output_scale_bits |

CSR는 status_done/status_error를 다시 sticky latch하지 않는다. 상태 입력 5종은 읽기 응답을 만들 때만 snapshot한다. CLEAR는 코어에 pulse를 보내며 실행 중단이나 cfg_ok 해제 명령이 아니다. LOAD 시작/실패에 따른 cfg_ok 해제는 기존 Loader 계약을 유지한다.

### 3.2 구현 구조 — 설계안

- 쓰기는 한 번에 transaction 1개만 처리한다. AW 1-entry(`awaddr_reg`, `aw_hold_reg`)와 W 1-entry(`wdata_reg`, `wstrb_reg`, `w_hold_reg`)를 독립으로 둔다.
- write FSM은 폭 지정 `WR_COLLECT`/`WR_RESP` 두 상태로 구성한다. COLLECT에서 양쪽을 수집하고, 둘 다 보유한 뒤 한 번 commit한다. commit에서 AW/W hold를 모두 소비해 0으로 내리고 RESP로 전환한다. RESP에서 B handshake를 기다린다.
- AWREADY는 COLLECT이며 AW 보관함이 비었을 때, WREADY는 COLLECT이며 W 보관함이 비었을 때 올린다. 상대 채널의 VALID 및 코어 busy를 READY 조건으로 삼지 않는다.
- B 응답이 보류되면 새 AW/W를 받지 않는다. B handshake edge에도 다음 요청을 동시에 받지 않는 단순 구조로 시작한다. 불필요한 처리량 최적화는 하지 않는다.
- 읽기는 write와 독립이며 outstanding 1개다. ARREADY는 reset 해제 상태에서 `!rvalid_reg`일 때만 올린다. AR 수락 때 RDATA/RRESP를 register에 넣고 RVALID를 올린다. R handshake에서 RVALID를 내리며, 그 edge에는 새 AR를 받지 않는다.
- 내부 상태·보류값·응답은 `*_reg/*_next`, pulse의 next 기본값은 0, 저장 데이터/응답 payload의 next 기본값은 current다. bus 응답과 pulse는 등록된 출력으로 만든다.

## 4. 쓰기 수락과 응답

### 4.1 AW/W 독립 수락 — 명세 + 설계안

`aw_fire = AWVALID && AWREADY`, `w_fire = WVALID && WREADY`인 상승 에지에서 각 payload를 별도로 보관한다. AW가 먼저든 W가 먼저든 나머지를 기다리고, AW/W 동시 도착도 처리한다. 이미 수락한 채널의 주소/데이터는 이후 외부 입력 변화에 영향받지 않는다. AWPROT/ARPROT는 명세대로 무시한다.

이 문서에서 **commit**은 AW/W가 모두 보관된 후 쓰기 효과와 BRESP를 단 한 번 결정하는 상승 에지다. 한 채널의 handshake 또는 B handshake를 commit으로 부르지 않는다. 명세의 “write 수락 cycle”을 이 commit에 대응시키는 안은 D03으로 명시한다.

예시에서 E0/E1/E2는 연속 상승 에지다.

| 시점 | 동작 |
| --- | --- |
| E0 | AW/W 중 마지막 미수락 채널을 latch. 이때까지 쓰기 효과 없음 |
| E1 | 양쪽 hold 확인 후 commit. 설정값 갱신 또는 CONTROL pulse register=1, BRESP 결정, BVALID=1 |
| E1 직후–E2 | START/CLEAR pulse가 1인 한 cycle. BREADY=0이어도 이 pulse를 연장하지 않음 |
| E2 | Top이 pulse와 command/주소를 샘플. S00 pulse=0. BREADY=1이면 B 응답 완료 |
| E2 이후 | B가 완료된 경우 COLLECT로 복귀. 다음 AW/W 수락은 빨라도 E3, 다음 commit은 빨라도 E4 |

BVALID는 AW와 W를 모두 수락하기 전에 발생하지 않는다. `BVALID && !BREADY` 동안 BVALID/BRESP는 고정하며 CSR 쓰기/pulse를 반복하지 않는다. BREADY를 기다려 pulse를 발생시키지도 않는다.

### 4.2 busy 판정 — 미결 D03

권장 기준은 commit 직전의 `status_busy || reg_start`다. `reg_start`는 이미 발생해 Top이 아직 소비 중인 pulse 구간을 보호하는 내부 조건이며 새 외부 포트가 아니다. 위 직렬 구조 자체도 후속 commit 공백을 보장한다. busy 상승까지 기다리는 무기한 pending lock은 두지 않는다. BAD_CMD/NO_CFG는 busy를 오래 올리지 않고 종료할 수 있기 때문이다.

- AW가 busy 중 수락되어도 W 수락/commit 전에 idle이면 권장안에서는 idle 쓰기로 처리한다.
- 반대로 AW가 idle에서 수락되었어도 commit에 busy이면 거부한다.
- 완료 edge 직전 busy=1이면 그 edge의 START/설정 commit은 거부한다. 다음 거래에서 재시도한다.
- busy일 때도 AW/W handshake를 마친 뒤 B에 SLVERR를 반환한다. busy가 끝날 때까지 AXI 채널을 막아 거부를 숨기지 않는다.

Top은 START 소비 edge에서 command/주소를 latch한다. 정상 LOAD/INFER라면 그 edge 이후 busy를 올리고, 즉시 검증 실패면 error를 남긴다. 이 타이밍은 Top 연결 검수 항목이다.

### 4.3 WSTRB와 원자적 갱신

**[명세]** WSTRB는 4개 byte lane을 선택하며 CONTROL bit0/1은 `WSTRB[0]`으로 마스크한다. **[설계안]** 4개 RW register 모두 선택된 byte만 병합한다. `for` 없이 `[7:0]`, `[15:8]`, `[23:16]`, `[31:24]`를 명시적으로 갱신한다.

- `start_req = wstrb_reg[0] && wdata_reg[0]`.
- `clear_req = wstrb_reg[0] && wdata_reg[1]`.
- COMMAND는 32bit 전체를 보존한다. 값의 의미 검사는 Top의 START 처리에서 한다.
- **[미결 D04]** 주소 register는 기존값과 WSTRB를 병합한 후보를 먼저 만든다. INPUT/WEIGHT 후보 `[2:0] != 0`, OUTPUT 후보 `[4:0] != 0`이면 전체 쓰기 SLVERR, 기존 register 전체 보존을 권장한다. 하위 bit를 강제로 0으로 만들지 않는다. 잘못된 DDR 접근을 시작 전에 막으면서 새 STATUS 오류 코드가 필요 없다는 이유다.
- **[미결 D05]** idle의 `WSTRB=0000`은 no-op/OKAY를 권장한다. busy의 COMMAND/주소 쓰기는 strobe=0이어도 명세의 busy-write 거부를 우선해 SLVERR로 처리한다.
- CONTROL 예약 bit [31:2]는 무시하고 OKAY를 권장한다. `WSTRB[0]=0`이면 데이터 bit0/1이 1이어도 pulse가 없다.

### 4.4 쓰기 응답 판정 순서 — 미결 D01/D04/D05

아래 순서의 권장안을 적용하면 SLVERR 거래에 부분 부작용이 남지 않는다. OKAY=`2'b00`, SLVERR=`2'b10`은 명세의 응답 값이다.

| 순서 | 조건 | 효과/응답 |
| --- | --- | --- |
| 1 | CSR byte offset `[1:0] != 0` | 어떠한 쓰기/pulse도 없이 SLVERR (D04) |
| 2 | 0x04/0x18/0x1C | busy·WSTRB에 무관하게 무시/OKAY (**명세**) |
| 3 | 0x00 CONTROL, start_req=1이고 write 차단 조건=1 | START+CLEAR 여부와 무관하게 두 pulse 모두 억제/SLVERR (동시 쓰기 부분은 D01) |
| 4 | 0x00 CONTROL, 위 거부 아님 | 유효 START/CLEAR 각 1-cycle, 또는 no-op/OKAY |
| 5 | 0x08~0x14, write 차단 조건=1 | 값 미반영/SLVERR. 0 strobe 처리 순서는 D05 |
| 6 | idle의 0x08~0x14, WSTRB=0 | 값 보존/OKAY (D05) |
| 7 | idle의 주소 register, 병합 후보 정렬 위반 | 값 전체 보존/SLVERR (D04) |
| 8 | 그 외 유효 RW 쓰기 | 병합 후보 반영/OKAY |

CSR 접근 주소의 4 B 정렬과 register 안의 DDR 주소 값 정렬은 서로 다른 검사다. 현재 5-bit aperture `0x00–0x1F`에는 aligned slot 8개가 모두 정의되어 있다. 그 밖 시스템 주소의 decode는 BD/interconnect 책임이다. S00가 전달받지 못하는 상위 주소 bit까지 검사한다고 기록하지 않는다. 추후 주소 폭 확대 시에는 undefined offset 응답을 별도 명세화한다.

## 5. 읽기와 응답 stall

**[설계안/미결 D03]** AR handshake 상승 에지에서 읽기값 및 RRESP를 함께 snapshot한다. STATUS 전체 bit를 동일 edge에서 읽으며, 응답 대기 중 코어 상태가 바뀌어도 응답은 유지한다.

- CONTROL/RESERVED는 0/OKAY, RW register는 저장값/OKAY, STATUS는 2절 구성/OKAY다.
- OUTPUT_SCALE_BITS는 snapshot 시 cfg_ok가 0이면 0/SLVERR, 1이면 당시 scale/OKAY다. 이후 cfg_ok 변화로 이미 준비된 RRESP/RDATA를 바꾸지 않는다.
- **[미결 D04]** 비정렬 AR offset은 0/SLVERR를 권장한다.
- `RVALID && !RREADY` 동안 RVALID/RDATA/RRESP를 유지한다. ARVALID가 내려가도 응답을 취소하지 않는다.
- 같은 edge에 RW write commit과 AR 수락이 겹치면 **갱신 전 저장값**을 읽는 안을 권장한다. 코어가 CLEAR/완료/오류로 상태를 바꾸는 edge도 갱신 전 값을 snapshot한다. 새 값은 후속 read로 관찰한다. PS는 쓰기 후 B 완료 및 플랫폼의 MMIO 순서를 지킨 뒤 읽는다.
- R stall은 write 진행을 막지 않고 B stall은 read 진행을 막지 않는다. 예를 들어 START의 B 응답이 stall이어도 STATUS read와 코어 진행은 가능하다.

## 6. START/CLEAR와 상태 경합 — 미결 D01/D02

### 6.1 같은 CONTROL 쓰기에 START와 CLEAR가 함께 있을 때

| commit의 조건 | 권장 결과 | 이유 |
| --- | --- | --- |
| idle, start_req=1, clear_req=1 | OKAY, 두 pulse를 같은 cycle 발생 | 이전 표시 상태 해제와 새 실행을 한 번에 표현 가능 |
| busy, start_req=1, clear_req=1 | SLVERR, 두 pulse 모두 없음 | 실패한 쓰기에 CLEAR만 실행되는 부분 부작용을 피함 |
| busy, start_req=0, clear_req=1 | OKAY, CLEAR만 발생 | **이미 명세에 정해진 동작**. 실행 계속 |
| WSTRB[0]=0 | 두 요청 모두 없음 | 쓰기 byte lane을 존중 |

busy의 START+CLEAR에서 CLEAR만 수행하는 대안은 가능하지만, SLVERR 응답 후에도 기존 오류 기록이 지워져 PS가 재시도 효과를 예측하기 어렵다. 따라서 전체 거부를 권장한다. 이 권장안이 CLEAR 단독 허용 규칙을 바꾸지는 않는다.

### 6.2 CLEAR와 완료/오류가 같은 cycle일 때

여기서 “동시”는 **Top이 reg_clear_status/reg_start와 완료·오류 이벤트를 같은 상승 에지에서 소비하는 경우**다. S00 commit edge와 혼동하지 않는다. 아래는 Top 계약 및 CSR TB 코어 모형에 대한 권장안이며 S00 안에 sticky 상태를 추가하는 안이 아니다.

| 우선순위 | 같은 edge의 사건 | 다음 done/error 권장값 |
| --- | --- | --- |
| 0 | reset | 0/0 |
| 1 | 현재 작업의 새 오류 또는 실패가 기록된 작업의 종료 | done=0, 해당 오류 코드 |
| 2 | 오류 없는 성공 완료 | done=1, error=0 |
| 3 | 수락된 새 START 또는 CLEAR, 새 완료/오류 없음 | done=0, error=0 |
| 4 | 아무 사건 없음 | 기존값 유지 |

새 이벤트가 해제보다 우선하므로 완료/오류를 PS가 놓치지 않는다. START에서 이전 done을 지우는 것은 **명세**, 이전 error도 지우는 것은 **D02 권장안**이다. START와 즉시 BAD_CMD/NO_CFG가 겹치면 새 오류를 남긴다. 완료와 새 오류가 동시에 보이면 오류가 성공보다 우선한다.

추가 제약:

- CLEAR는 busy, command/주소 snapshot, cfg_ok, 출력 버퍼, 진행 카운터를 바꾸지 않는다.
- 표시용 status_error를 CLEAR하더라도 작업 내부의 `run_failed`/첫 오류 기록은 유지한다. 오류 drain 뒤 성공 done이 잘못 생기는 것을 막기 위함이다. 이 내부 기록은 새 작업/reset에서 초기화한다.
- M00의 mem_*_err는 다음 mem 명령까지 유지되는 level이다. 같은 level을 매 cycle 새 오류로 처리하면 CLEAR 직후 다시 set되는 문제가 있다. Top은 현재 명령에서 처음 감지한 오류를 사건으로 기록하고, 이미 처리한 level과 새 사건을 구분해야 한다.
- busy 중 CLEAR로 오류 표시를 지운 뒤, 실패 작업이 종료하면 저장된 실패 원인으로 오류 표시를 다시 남기는 안을 권장한다. CLEAR는 실패를 성공으로 바꾸지 않는다.
- 복수 오류의 구체적 코드 선택과 drain/재시작/FIFO 복구는 D08이다. 첫 검출 코드 유지 및 같은 edge에서는 관련 DDR 오류를 BLOB_ERR보다 우선하는 방향을 제안하되, Top 구현 전 별도로 합의한다.
- 이전 작업의 종료와 다음 START를 무조건 같은 cycle에 허용하지 않는다. 현재 busy 차단 계약과 4.2절 판정 시점을 유지하고, Top이 유휴 상태에서 받은 START만 새 실행으로 취급한다.

## 7. reset과 안전 복구

**[명세]** S00_AXI_ACLK는 s00 clock이며 reset은 active-low, 비동기 assert/동기 release다. **[설계안]** 순차 블록은 `always @(posedge S_AXI_ACLK or negedge S_AXI_ARESETN)` 형태로 이 계약을 따른다. active 상태의 register 갱신에는 nonblocking 대입을 사용한다.

- reset 시 RW 4개=0, START/CLEAR=0, AW/W hold=0, BVALID/RVALID=0, 응답·읽기 데이터=0, write state=COLLECT로 초기화한다.
- reset 동안 AWREADY/WREADY/ARREADY를 낮추고 거래를 수락하지 않는다. reset 전 절반만 받은 AW 또는 W, 아직 완료되지 않은 응답은 폐기한다. reset 후 이전 거래의 pulse나 쓰기가 뒤늦게 발생하지 않아야 한다.
- STATUS/scale의 reset 의미는 Top/Loader가 함께 reset되는 계약으로 보장한다. CSR가 해당 상태를 자체 생성하지 않는다.
- 각 조합 블록에서 기본 유지값과 pulse=0을 먼저 지정한다. write FSM의 불법 상태 default는 pulse=0, hold/보류 응답 제거, COLLECT 복귀로 명시한다. 불법 상태 복구가 미완료 AXI 거래를 정상 완료시킨다고 보장하지 않으며, 실제 시스템에서 발생하면 공통 reset 후 재개해야 한다. 새 CSR 오류 코드는 추가하지 않는다.
- CSR에는 RAM이 필요 없다. 이후 Loader에서도 RAM 전체 reset 대신 유효성 상태로 관리한다.
- **[미결 D07]** wrapper에는 reset 동기 해제 회로가 보이지 않는다. 민영의 BD 공통 reset 출력에서 동기 release를 보장하는 안을 권장한다. 블록마다 release cycle이 다른 동기화기를 임의로 삽입하지 않는다.

## 8. 민영과 공유할 PS 계약

### 8.1 이미 명세에 있는 계약 — 재질문하지 않음

- CSR offset은 2절을 사용한다. HLS AP_CTRL의 done clear-on-read를 재사용하지 않는다. STATUS는 읽기 부작용이 없고 CONTROL bit1로 지운다.
- idle에서 COMMAND/주소를 설정하고 START한다. busy 중 설정/START는 SLVERR이며 값/pulse가 적용되지 않는다. CLEAR 단독은 busy에도 가능하고 실행을 중단하지 않는다.
- INFER 전 LOAD 성공이 필요하며 자동 LOAD는 없다. COMMAND 유효값은 0/1이다.
- COMMAND=0/1 외 값의 BAD_CMD와 cfg_ok=0 INFER의 NO_CFG는 코어 실행 상태 오류다. CSR bus SLVERR와 구분한다.
- 입력 11,520 B, 출력 24 B의 signed INT8를 사용하고, cfg_ok=1일 때 얻은 scale의 float32 비트로 복원한다. 기존 출력 float32×24=96 B와 다르다.
- INPUT/WEIGHT base 8 B, OUTPUT base 32 B 정렬을 지킨다. 32bit 주소 범위와 플랫폼 DDR 예약·캐시 처리도 민영이 관리한다.
- 성공 판정은 busy=0이면서 done=1, error_code=0이다. 오류 종료는 busy=0 및 error_code!=0으로 확인한다. 오류로 busy가 곧바로 내려가지 않을 수 있으므로 drain 중 재START하지 않는다.
- B 응답은 CSR 쓰기 수락 결과일 뿐 실행 완료가 아니다. 커널/UIO/MMIO 경로에서 AXI SLVERR가 PS에 어떻게 노출되는지는 플랫폼 의존이므로 드라이버 계약에 포함한다.

### 8.2 합의할 항목

| 결정 ID | 민영과 합의할 내용 |
| --- | --- |
| D01 | CONTROL=3을 사용할지, busy에서 전체 거부하는 권장안 |
| D02 | 새 START의 이전 error 해제, CLEAR 동시 새 이벤트 우선, busy CLEAR 후 실패 종료의 오류 재표시 |
| D03 | commit 기준 busy 판정과 read snapshot. PS가 실패 응답 없이 연속 쓰기 효과를 추정하지 않도록 MMIO 순서 보장 |
| D04/D05 | 비정렬 CSR/DDR 후보 쓰기 거부, 0 strobe와 예약 bit의 응답. 실제 PS의 byte-write 사용 여부와 SLVERR 처리 |
| D06 | WEIGHT_ADDR를 바꾸면 재LOAD 후 INFER. 같은 주소의 blob 내용도 실행/상주 유효 기간에 임의로 교체하지 않음 |
| D07/D08 | 공통 reset 생성 책임, timeout 후 복구, drain 완료 판정·실패 후 재LOAD/재실행 조건 |

권장 PS 실행 순서는 idle 확인 → 필요 시 LOAD → LOAD 성공/cfg_ok 확인 → scale 읽기 → 입력 양자화·DDR/캐시 준비 → COMMAND/주소 쓰기 완료 확인 → START → done/error polling → 성공 시 출력 캐시 처리·24 B 복원이다. LOAD/INFER마다 START 전에 필요한 주소와 COMMAND를 준비한다. 오류가 나면 출력 데이터를 성공 결과로 사용하지 않는다. 실제 timeout 수치와 시스템 reset 경로는 이번 문서에서 임의로 정하지 않는다.

## 9. 구현 후 최소 검증 및 Claude Code 인계

이번에는 아래를 **실행하지 않았다**. 합의 반영 후 CSR 1개와 작은 코어 모형으로 확인할 범위다. TB에서는 for/task/function을 사용할 수 있다.

| 검사 묶음 | 필수 사례/관찰 |
| --- | --- |
| AXI 수집·응답 | AW 먼저/W 먼저/동시, VALID 유지, handshake 이후 입력 변경, 채널 하나만 오래 지연, 거래당 commit·B응답 각 1회 |
| stall | BREADY/RREADY 장기 0 동안 payload 고정, pulse 중복 없음, 읽기·쓰기 독립 진행, 응답 덮어쓰기 없음 |
| 맵·byte 쓰기 | 8개 offset, 각 WSTRB lane/혼합/0, RW readback, RO 쓰기 무시, CONTROL lane0 마스크·예약 bit |
| busy·경계 | busy 중 START/설정 거부·CLEAR 허용, 분리 AW/W 사이 busy 변화, START 소비 전 보호, 완료 edge에서의 쓰기 |
| 상태·경합 | idle/busy START+CLEAR, CLEAR+성공, CLEAR+오류, START+즉시 오류, 오류+성공, 새 START의 기존 상태 해제 |
| 읽기 시점 | STATUS/scale stall 중 코어 입력 변경, cfg_ok 0/1 scale 응답, 동시 read/write의 갱신 전 값 |
| 정렬·원자성 | CSR 비정렬 R/W, DDR 병합 후보 정렬 위반, 실패 시 byte 부분 갱신 없음, busy+정렬 위반 우선순위 |
| reset | AW만/W만 보유 중, B/R stall 중, pulse 중 reset. 해제 후 stale 거래 없음 |

Claude Code의 **문서 검수 후보 범위**: 2절 맵·비트·응답과 XLSX 원문 일치, 확정/권장 구분, 거래당 1회 commit, START 전달 공백, 상태 소유권, CLEAR 소비 edge, 미결 PS 계약 누락이다. 현재 사용자와 진행하는 소단계에 관련된 항목만 선택한다. 문서상 검토를 실제 RTL 검수 완료로 보고하지 않는다.

**구현 후 검수 범위**: 기존 11개 CSR 포트 유지, AW/W 독립 보관, WSTRB/거부 원자성, B/R stall 안정성, pulse 1-cycle, 위 경합 우선순위, reset/불법 상태 복구, 현재·다음값 스타일, 합성 RTL의 for/task/function 미사용, 소형 TB의 결과다. Top 모형으로만 검증한 동작은 실제 Top 통합에서 재확인한다.

모듈 수준의 의존 순서는 관련 결정 반영 → S00_AXI → Loader/RAM → Top FSM/코어 연결이다. 실제 실행은 공통 문서 7절의 소단계 규칙을 따른다. 다음 제안은 S00-01(CSR 역할·레지스터 맵 설명/확인)이며 코드 작성은 포함하지 않는다. 이후 사용자 진행 요청마다 현재 기능에 필요한 RTL/TB·검수만 수행한다. 위 표는 향후 CSR 전체의 검증 항목을 정리한 것이며 한 단계에서 모두 수행하라는 뜻이 아니다. 전체 합성·전체 회귀는 이번 문서 작업에 포함하지 않는다.
