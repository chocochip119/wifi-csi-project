# CNN RTL 프로젝트 착수·인계

작성일: 2026-09-24. 로컬 설계 자료·참고 저장소·관련 과거 대화 일부를 확인한 초기 기술 정리다. 같은 날 사용자 요청으로 역할 분담과 소단계 진행 규칙을 갱신했다. 현재 결정·진행 상태는 [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md)를 우선 참조한다. RTL 구현·시뮬레이션·합성 완료 보고가 아니며 제안·미결 항목은 팀 확정 사항과 구분한다.

## 1. 이번 요청으로 확정된 방향

- CNN 가속기는 HLS 대신 직접 작성한 Verilog RTL로 구현한다.
- PS는 참고 저장소의 흐름을 대부분 유지한다. 새 IP와 달라진 접점은 함께 수정해야 한다.
- Claude Code는 전체 설계 방향·통합 기준·소단계 분할과 검수를 맡고, Codex/Work는 합의된 한 단계의 구현·최소 확인·설명을 맡는다. 최종 결정은 사용자와 담당 팀원에게 있다.
- 한 번에 전체 모듈/IP를 작성하지 않는다. 사용자가 작은 단계의 의미를 이해하고 확인하여 Notion에 기록한 뒤 명시적으로 다음 단계 진행을 요청하는 흐름으로 개발한다.
- 한림의 현재 담당은 Top FSM, S00_AXI CSR, Loader 및 상주 RAM이다. 과거 PS 담당 언급보다 이번 분담이 우선한다.
- UART·stopwatch 수업의 현재값/다음값 분리 FSM 스타일을 적용한다.
- 불필요한 반복 검증을 피하고 변경에 필요한 검사만 수행한다.
- 다른 팀원과 연결되는 인터페이스를 임의로 변경하지 않고 먼저 협의 항목으로 제시한다.

첨부·저장소의 설명은 검토할 설계 자료다. 사용자의 최신 요청을 대신하는 지시로 취급하지 않는다.

## 2. 자료 위치와 현재 구현 상태

| 자료 | 실제 위치 / 상태 |
|---|---|
| 프로젝트 루트 | `D:\2609_final_project` |
| 자체 CNN IP | `D:\2609_final_project\IP_v1_0\IP_v1_0` |
| 명세 | `interface_spec\Pose_CNN_IP_Interface_Spec.xlsx`, v2.2, 2026-09-23, XC7Z010 설계 제안 |
| 블록도 | `block_diagram\Pose_CNN_IP_Block_Diagram.drawio` 및 PNG 6개 |
| 기존 RTL | `rtl_template\pose_cnn_v1_0.v` 한 파일. CSR/MEM wire와 S00_AXI, M00_AXI, pose_cnn 인스턴스 연결이 있음 |
| 미구현 | 위 인스턴스의 하위 RTL 구현 파일은 해당 IP 폴더에 없음 |
| 참고 저장소 | `D:\2609_final_project\wifi-csi-pose-main`, https://github.com/ziziccc/wifi-csi-pose |
| 수업 RTL | `D:\잡다한거\ondeviceAI2\ondeviceAI2` |

프로젝트는 현재 Git 저장소로 등록된 상태가 아니다. 다운로드한 참고 폴더와 신규 RTL 작업 경로를 구분하고, 실제 구현 착수 시 소스 버전 관리를 준비하는 것이 좋다. 이번 조사에서는 프로젝트 원본을 변경하지 않았다.

과거 대화는 `CNN 업무분장 WBS 설계`, `FC 변경 위치 추론 CNN`, `기능 디벨롭 방향` 일부를 확인했다. 위치 2출력 변경은 질문/제안 단계로 확인되었으며 확정 사항으로 적용하지 않는다. 현재 명세의 pose 24출력을 기준으로 검토했다.

## 3. 시스템 이해

PS의 CSI 수집·전처리·양자화 → DDR의 INT8 입력 → RTL CNN → DDR의 INT8 pose → PS의 scale 복원·후처리·전송 흐름이다.

- 입력: `9 × 128 × 10 = 11,520 B`.
- 채널: `base0, base1, base2, delta0, delta1, delta2, mask0, mask1, mask2`. RX r은 채널 `r, r+3, r+6`을 사용한다.
- Encoder: 공유 가중치로 RX0~2를 순차 처리한다. Conv1 `3→16, 5×3`, GELU, Conv2 `16→32, 3×3`, GELU, AdaptiveAvgPool `8×4`.
- Pool/Flatten: RX마다 1,024개, 전체 3,072개. 순서는 RX→channel→pool_h→pool_w. Flatten은 이미 정렬해 저장된 주소·데이터를 연결한다.
- FC: `3072→128→128→24`. FC1/2 뒤 GELU, FC3 뒤 GELU 없음.
- DDR 접근 명령은 Top FSM에 모으고 실제 AXI burst는 민영의 M00_AXI가 수행한다.
- Encoder는 enc_start 1회로 RX 3개 전체를 처리한다. FC는 fc_sel과 fc_start로 각 층을 따로 시작하고 층마다 fc_done을 반환한다.

공통 명세는 단일 s00_axi_aclk, active-low reset(비동기 assert/동기 release), RAM 읽기 1-cycle, 내부 쓰기 we/addr/data, 블록 start/done 1-cycle을 전제로 한다. wrapper의 M00 인스턴스도 s00 클록/reset을 사용한다. 외부 m00 클록 포트가 별도 도메인처럼 해석되지 않도록 패키징/BD에 이 계약을 반영해야 한다.

## 4. 팀별 경계

| 담당 | 구현 범위 | 한림 파트와의 접점 |
|---|---|---|
| 동우 | 입력·fmap 버퍼, Conv MAC 16 lane, 내부 sequencer, Pool/결과 저장 | enc_start/done, 입력 쓰기, Conv/Param/LUT 읽기, pool 계수 |
| 지원 | FC1 FIFO, FC MAC, Hidden RAM, pose 버퍼, Flatten, 공통 Requant/GELU 모듈 | fc_start/done/sel, FIFO full/push, FCW/Param/LUT 읽기, pose_data |
| 한림 | S00_AXI CSR, Top FSM, Loader/Blob Decoder/상주 RAM, pose_cnn 코어 연결 | PS 명령 계약, mem_* 명령과 데이터 분배, 계산 블록 순서 제어 |
| 민영 | M00_AXI burst, IP 패키징, BD, PS 드라이버/앱, Python golden | CSR 주소·상태, DDR 형식, stall/오류 처리, 출력 복원 |

공통 Requant/GELU는 지원이 모듈을 관리하고 Encoder와 FC가 각 인스턴스를 사용한다. 동일한 코드 공유와 단일 하드웨어 인스턴스 공유는 구분한다.

## 5. Loader에서 확정적으로 읽힌 내용

Blob v2는 32-bit word 105,748개, 422,992 B, magic `0x36574C50`이다. 제공된 HLS 폴더의 실제 .bin 헤더와 크기도 이에 일치한다.

| 동작 | DDR 상대 주소 | 길이 | 용도 |
|---|---:|---:|---|
| LOAD 구간 1 | 0 | 5,936 B | header 및 Conv weight/parameter |
| LOAD 구간 2 | 399,152 | 23,840 B | FC parameter, FC2/3 weight, GELU LUT |
| INFER FC1 | 5,936 | 393,216 B | 매 추론 FIFO로 공급하는 FC1 weight |

Loader가 FC1 weight 전체를 상주 RAM에 저장하지 않는다. LOAD 스트림은 두 구간을 이어서 총 3,722개의 64-bit beat로 처리한다. 하위 32bit가 앞선 word이고 byte lane 0이 가장 먼저 온다.

| 상주 RAM | 명세 크기 | 목적 |
|---|---:|---|
| Conv Weight | 333 × 128bit | 16개 출력 lane에 맞춘 tap/lane 배치 |
| Param | 328 × 96bit | `{shift, mult, bias}`, 출력 채널당 한 word |
| GELU LUT | 1,024 × 8bit | Conv1, Conv2, FC1, FC2 각 256개 |
| FCW | 2,432 × 64bit | FC2/3 weight |

Conv/LUT는 한 beat를 최대 8회에 나눠 쓰고, Param은 2회, FCW는 1회 쓴다. Decoder는 쓰기 완료까지 ld_ready를 낮추고 Top FSM은 이를 mem_rd_ready로 전달한다. 전체 RAM을 reset 때 지우는 루프는 넣지 않고 cfg_ok로 유효성을 관리한다.

09_Loader_주소맵의 weight 순서 가정은 export 코드와 일치한다. int8_export.py는 Conv 텐서/Linear weight 형상을 유지하며, generate_assets.py의 reshape(-1)과 little-endian packing은 Conv `[oc][ic][kh][kw]`, FC `[출력][입력]` 순서를 유지한다. 주소맵의 주요 offset도 weight_layout.json과 일치한다. 이는 RTL의 주소 생성과 실제 모든 RAM 내용을 검증했다는 의미는 아니다.

## 6. 구현 전에 팀과 협의할 항목

### 우선 확정

1. **실제 FPGA 보드와 목표 클록 — 전원.** 자체 명세는 XC7Z010, 참고 저장소는 Zybo Z7-20 기반이다. 이번 자료만으로 최종 보드를 확정할 수 없다. 자원 적합성을 단정하지 않는다.
2. **최종 출력 — 전원.** 현재 기준은 pose 24개. 과거 위치 2출력 제안을 적용할지는 별도 결정이다. 변경하면 FC3, blob, Loader 길이/주소, 출력 버퍼, PS 및 golden도 함께 바뀐다.
3. **CSR·출력 호환성 — 한림/민영.** 아래 차이를 PS 수정 범위로 확정한다.
4. **Param/LUT 공유 읽기 포트 선택 — 한림/동우/지원.** 05_Loader A86/A99는 물리 읽기 포트 1개를 Encoder/FC가 공유한다고 하지만, Loader 경계 포트 목록에 선택 입력이 없다. 제안은 Top FSM의 실행 phase에서 만드는 명시적 선택 신호다. 신호명·선택 시점·1-cycle 응답 정렬을 명세에 추가한 뒤 구현한다. 대안으로 물리 포트를 늘리는 것은 자원 및 RAM 구현을 함께 검토해야 한다.
5. **오류 종료와 재시작 — 한림/민영/지원.** LOAD 중 mem_rd_err가 발생해도 현재 Loader는 그 오류를 입력받지 않으므로 cfg_ok의 최종 유효성을 어떻게 막을지 정해야 한다. 또한 소비 블록이 중단해도 이미 발행한 AXI 응답은 받아 종료해야 한다. drain 중 데이터 폐기, FIFO 비움/재초기화, 오류 우선순위, 재시작 규칙을 합의한다. 이는 구현 전 명세 공백이며 현재 RTL에서 재현된 버그는 아니다.

### 기존 계약을 구현할 때 함께 확인

- LOAD 후 WEIGHT_ADDR를 바꾸면 상주 Conv/parameter와 새 FC1 weight가 서로 다른 모델일 수 있다. LOAD 당시 base를 유지하거나 변경 시 재LOAD를 요구하는 규칙을 정한다.
- mem_rd_start 이후 busy가 실제 올라갔다가 내려간 것을 완료로 판정한다. 최종 beat 전달과 Loader의 마지막 RAM 쓰기 완료를 구분한다.
- FC1은 DDR 읽기 완료와 FC 연산 완료를 구분한다. 입력 FIFO full/empty에 따른 대기 중 데이터나 카운터가 건너뛰지 않도록 한다.
- mem_wr_ready는 일반적인 ready 레벨이 아니라 WVALID&&WREADY 전송 사건이다. pose beat는 이 사건에만 전진하고 stall 중 고정한다. status_done은 마지막 B 응답 이후다.
- CLEAR_STATUS와 새 완료/오류의 동시 발생, START+CLEAR 동시 쓰기, 주소 정렬 위반 응답의 우선순위를 문서화한다.
- 지원/동우는 INT8 포화 범위 `[-127,127]`, 음수 requant 반올림, signed shift, GELU index를 같은 Python 기준과 맞춘다.
- Adaptive pool 가로 구간은 `[0,3), [2,5), [5,8), [7,10)`이며 열 2·7은 두 bin에 들어간다. 각 bin은 48개 sample이다.

## 7. PS 재사용 범위와 바뀌는 접점

실시간 PL 실행 앱은 `petalinux\tools\pl_accel_v6\esp_pose_pl_runner_rt.c`다. `ps_pose_infer.c`는 PS-only 비교용이므로 혼동하지 않는다.

CSI serial 파싱, 전처리, window 구성, base/delta/mask, INT8 입력 양자화, ping-pong 입력 처리, GUI 전송 흐름을 재사용할 수 있다. IP 제어부는 새 명세에 맞게 수정한다.

| 항목 | 참고 HLS/PS | 자체 명세 v2.2 |
|---|---|---|
| 제어/상태 | AP_CTRL 0x00, done clear-on-read 계약 | CONTROL 0x00, STATUS 0x04, sticky done/error 및 명시적 clear |
| COMMAND | 0x28 | 0x08 |
| 입력 주소 | 0x10/0x14 | 0x0C, 32bit |
| blob 주소 | 0x1C/0x20 | 0x10, 32bit |
| 출력 주소 | 0x30/0x34 | 0x14, 32bit |
| 출력 | float32 ×24 = 96 B | INT8 ×24 = 24 B, OUTPUT_SCALE_BITS 0x18 |
| 설정 미로드 INFER | HLS 내부 자동 load 가능 | NO_CFG 오류 |
| COMMAND 유효값 | HLS는 nonzero load-only | 0=INFER, 1=LOAD, 나머지 BAD_CMD |

PS는 출력 24 byte를 signed INT8로 읽고 output_scale(float32 bits)를 곱해 기존 후처리 입력으로 복원한다. 메모리 할당·캐시 처리 범위는 보드 환경의 cache-line 규칙에 맞춰 유지한다. 새 bitstream/XSA에 따라 BD 주소, device tree 및 DDR 예약 영역의 연동도 민영이 확인한다.

## 8. 코딩 스타일

근거 파일:

- `D:\잡다한거\ondeviceAI2\ondeviceAI2\UART\UART.srcs\sources_1\new\uart.v:73–108`
- `D:\잡다한거\ondeviceAI2\ondeviceAI2\20260504_Project2_uart_fifo_sensor_timer\source\top_control_unit.v:25–60,154–161`
- 같은 source 폴더의 `stopwatch_datapath.v:101–119`

적용 원칙:

- 상태 상수는 폭을 지정한 localparam, 현재/다음은 `state_reg/state_next`, 데이터와 카운터는 `*_reg/*_next` 쌍으로 선언한다. 외부 포트명은 팀 명세를 유지한다.
- 순차 블록은 posedge clk에서 nonblocking `<=`로 현재값을 갱신한다.
- 조합 블록은 always @(*)에서 blocking `=`를 사용한다. 시작 부분에 next=current와 출력 기본값을 둔다.
- 필요에 따라 상태 레지스터/다음 상태/출력을 3개 블록으로 분리한다. 불법 상태의 default 복구도 명시한다.
- 수업의 active-high 비동기 reset을 그대로 복사하지 않고 새 IP의 rst_n 및 reset release 계약에 맞춘다.
- 사용자 의도를 보수적으로 적용하여 새 합성 RTL에서는 for/task/function을 사용하지 않는 방식으로 작성한다. 반복 하드웨어는 명시적 인스턴스/대입, 시간 반복은 FSM/카운터로 표현한다. testbench는 별도다.
- for/task/function이 언어 차원에서 모두 비합성인 것은 아니다. 위 내용은 프로젝트 작성 규칙이다.
- RAM 배열 전체 reset, 내부 tri-state, 래치가 생기는 불완전 조합 대입을 피한다. signedness와 연산 폭을 명시한다.

## 9. Codex/Work와 Claude Code의 작업 순서

현재 작업 규칙의 원본은 [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) 7–8절이다. Codex는 [AGENTS.md](AGENTS.md), Claude는 [CLAUDE.md](CLAUDE.md)를 함께 따른다.

| 순서 | 담당과 행동 |
| --- | --- |
| 소단계 제안 | Claude가 목표·개념·수정 범위·확정 계약·완료 조건·최소 확인을 작은 단위 하나로 정의 |
| 구현 | 사용자 요청 범위에서 Codex가 해당 단계만 구현하고 필요한 최소 확인 수행 |
| 설명·검수 | Codex가 의미·신호·동작 예·변경 위치를 설명. Claude는 필요한 변경분만 검수 |
| 이해·기록 | 사용자 질문/필수 수정을 현재 단계에서 해결하고 Notion에 복사할 요약 제공 |
| 다음 단계 | 사용자의 명시적인 다음 단계 요청을 받은 뒤 시작. 검사/검수 통과만으로 자동 진행하지 않음 |

같은 파일을 두 도구가 동시에 수정하지 않는다. 참고 원본과 다른 담당자의 구현·공통 인터페이스를 임의로 바꾸지 않는다. Notion 기록 초안 제공을 실제 기록 완료로 보고하지 않는다. 직접 Notion 쓰기는 별도 요청과 대상 페이지가 있을 때만 한다.

초기 인계 후 공통 문서와 도구별 지침, CSR 상세 설계 초안이 만들어졌다. 기존 상세 초안은 설계 참고 자료이며 한 번에 전체 RTL을 구현하라는 요청이 아니다.

## 10. 최소 검증과 첫 구현 목표

- CSR: AW/W 도착 순서, byte write, busy 중 START/설정 거부, CLEAR 동작과 응답 stall을 한 소형 TB에서 확인한다.
- Loader: 제공 blob 한 개로 주소/내용의 주요 경계, ld_ready stall, 정상 완료를 확인하고 잘못된 header/shift 및 DDR 오류의 재시작을 필요한 범위에서 확인한다.
- Top FSM: 팀원 연산 블록을 간단한 모형으로 대체해 LOAD→INFER 1회, FC1 FIFO stall, 오류 drain을 확인한다.
- 합성: RAM 구현과 FSM이 갖춰졌을 때 실제 타깃으로 한 차례 확인해 래치/BRAM 추론/자원을 본다. 모든 작은 편집마다 전체 합성·전체 회귀를 반복하지 않는다.
- 통합: 제공 test vector 한 건으로 Python/참고 정수 연산과 비교한다. 다른 출력 형식과 부동소수 복원 오차를 구분한다.

다운로드에는 기존 weight .bin과 test_vectors.h가 있지만 weights_int8.npz, model_int8.json, 학습 .pt는 확인되지 않았다. 따라서 generate_assets.py를 그대로 재실행하는 작업부터 시작하지 않는다. 필요 시 기존 blob 기반 golden을 만들거나 원래 export 자료를 확보한다.

첫 대상 모듈은 S00_AXI CSR이지만 이를 한 번에 완성하지 않는다. 다음 첫 소단계 제안은 **S00-01: CSR 역할과 기존 레지스터 맵 설명·확인**이며 RTL/TB 작성은 포함하지 않는다. 이후 사용자 이해·확인·Notion 기록과 다음 단계 요청을 거쳐 작은 구현 단위로 진행한다. 위 검사 목록은 해당 기능을 구현할 때 적용할 범위이며 매 단계마다 모두 실행하라는 뜻이 아니다. Loader와 Top FSM도 같은 방식으로 나눈다.

## 11. 주요 근거 위치

- 자체 명세: `00_개요 A17:G46`, `02_S00_AXI A5:G34`, `03_M00_AXI A7:G23/A67:A73`, `04_pose_cnn A39:G92`, `05_Loader A7:G31/A74:A99`, `06_Encoder A26:G51/A100:G111`, `07_Flatten A7:G12`, `08_FC A7:G24`, `09_Loader_주소맵 A5:G45`.
- 참고 모델: `ML\src\original_models.py:10–70`.
- 정수 golden 규칙: `ML\src\int8_reference.py:24–37,85–111,129–158`.
- Weight 순서: `ML\src\int8_export.py:42–61,259–292`, `HLS\pl_accel_v6\generate_assets.py:116–127,151–191`.
- Blob 주소: `HLS\pl_accel_v6\pl_accel_v6_weight_layout.json`, `full_pose.h`.
- HLS 상주 로드/FC1/출력: `HLS\pl_accel_v6\full_pose.cpp:265–292,539–560,610–615,645–650`.
- PS 제어: `petalinux\tools\pl_accel_v6\esp_pose_pl_runner_rt.c:57–63,431–483`.

위 참고 저장소 내 경로는 모두 `D:\2609_final_project\wifi-csi-pose-main` 기준이다. 이번 확인은 자료 읽기와 제공 blob 헤더·크기 확인까지이며, RTL 합성 가능성·타이밍·정확도·성능을 검증한 것은 아니다.
