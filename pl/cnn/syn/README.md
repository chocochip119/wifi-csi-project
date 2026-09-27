# 합성 점검 (syn)

기능 경계가 완성될 때마다 한 번 돌려서 **래치 / 조합 루프 / 자원 / 타이밍**을 본다
(`PROJECT_CONTEXT.md` 4절). 작은 편집마다 돌리지 않는다. 구현(P&R)은 하지 않는다.

## 실행

```
cd cnn_rtl/syn
vivado -mode batch -source syn_check.tcl -nojournal -nolog -tclargs \
       pose_cnn_v1_0_S00_AXI xc7z020clg400-1 ../rtl/pose_cnn_v1_0_S00_AXI.v
```

산출물(`vivado.log`, `.jou`, `xsim.dir` 등)은 재생성물이므로 보관하지 않는다.

## 기록

| 날짜 | 대상 | LUT | FF | BRAM | DSP | Setup WNS | 래치 |
|---|---|---:|---:|---:|---:|---:|---:|
| 2026-09-26 | `pose_cnn_ctrl` (X-02a 구성 블록 재검증, xc7z020) | 455 | 225 | 0 | 0 | +1.741 ns | 0 |
| 2026-09-26 | `weight_param_loader` (X-02a 구성 블록 재검증, xc7z020) | 650 | 212 | 10 RAMB36 + 3 RAMB18 | 0 | +1.365 ns | 0 |
| 2026-09-26 | `CNN_Encoder` (X-02a 작업본 재검증, xc7z020) | 6490 | 3530 | 13 RAMB36 | 10 | **−3.641 ns 실패 유지** | 0 |
| 2026-09-26 | `CNN_Encoder` (E-01 검증 후보, 공유 작업본 반영 대기, xc7z020) | 6490 | 3530 | 13 RAMB36 | 10 | **−3.641 ns 실패** | 0 |
| 2026-09-26 | `weight_param_loader` (L-07 D09 주소 선택, xc7z020) | 650 | 212 | 10 RAMB36 + 3 RAMB18 | 0 | +1.365 ns | 0 |
| 2026-09-26 | `pose_cnn_ctrl` (L-07 D09 선택 출력, xc7z020) | 455 | 225 | 0 | 0 | +1.741 ns | 0 |
| 2026-09-25 | `pose_cnn_v1_0_S00_AXI` (X-01, xc7z010) | 182 | 208 | 0 | 0 | +3.895 ns | 0 |
| 2026-09-25 | `pose_cnn_ctrl` (T-01R, 부분 구현, xc7z010) | 19 | 40 | 0 | 0 | +4.885 ns | 0 |
| 2026-09-25 | `pose_cnn_v1_0_S00_AXI` (R-01, 동기 reset, xc7z010) | 183 | 208 | 0 | 0 | +3.895 ns | 0 |
| 2026-09-25 | `pose_cnn_v1_0_M00_AXI` (R-01, 첫 합성, xc7z010) | 364 | 132 | 0 | 0 | +2.779 ns | 0 |
| **2026-09-25** | **`pose_cnn_v1_0_S00_AXI` (xc7z020 확정 보드)** | 183 | 208 | 0 | 0 | +3.895 ns | 0 |
| **2026-09-25** | **`pose_cnn_v1_0_M00_AXI` (xc7z020 확정 보드)** | 364 | 132 | 0 | 0 | +2.779 ns | 0 |
| **2026-09-25** | **`pose_cnn_ctrl` (xc7z020 확정 보드)** | 19 | 40 | 0 | 0 | +4.863 ns | 0 |
| 2026-09-25 | `Conv_MAC` (동우, 참고 측정) | 2274 | 1214 | 0 | 0 | +1.093 ns | 0 |
| 2026-09-25 | `Conv_MAC` (`use_dsp="yes"` 강제, 참고) | 260 | 651 | 0 | **35 DSP** | **-3.723 ns 실패** | 0 |
| 2026-09-25 | `CNN_Encoder` (동우) | — | — | — | — | — | **합성 실패** |
| 2026-09-25 | `pose_cnn_ctrl` (T-03 LOAD, xc7z020) | 146 | 77 | 0 | 0 | +1.986 ns | 0 |
| 2026-09-25 | `pose_cnn_ctrl` (T-04 IN_RD/ENC, xc7z020) | 239 | 120 | 0 | 0 | +1.734 ns | 0 |
| 2026-09-25 | `pose_cnn_ctrl` (T-05 FC1/D06, xc7z020) | 362 | 158 | 0 | 0 | +1.408 ns | 0 |
| 2026-09-25 | `pose_cnn_ctrl` (T-06 동일 기능, 주소 완화 전, xc7z020) | 475 | 191 | 0 | 0 | +1.406 ns | 0 |
| 2026-09-25 | `pose_cnn_ctrl` (T-06 FC2/FC3/WR, 주소 완화 후, xc7z020) | 471 | 220 | 0 | 0 | +1.728 ns | 0 |
| 2026-09-26 | `pose_cnn_ctrl` (T-07 ERR_DRAIN, 13상태 완성, xc7z020) | 457 | 225 | 0 | 0 | +1.741 ns | 0 |
| 2026-09-26 | `blob_decoder` (L-01 골격/header, CHECK_VERSION=0, xc7z020) | 135 | 117 | 0 | 0 | +3.760 ns | 0 |
| 2026-09-26 | `conv_weight_ram` (L-02 단독, xc7z020) | 0 | 0 | 2 | 0 | +3.565 ns | 0 |
| 2026-09-26 | `param_ram` (L-02 단독, xc7z020) | 0 | 0 | 1.5 | 0 | +3.565 ns | 0 |
| 2026-09-26 | `gelu_lut_ram` (L-02 단독, xc7z020) | 0 | 0 | 0.5 | 0 | +3.565 ns | 0 |
| 2026-09-26 | `fcw_ram` (L-02 단독, xc7z020) | 0 | 0 | 7.5 | 0 | +3.565 ns | 0 |
| 2026-09-26 | `loader_l02_synth` (L-03까지의 임시 fixture; L-02 decoder+RAM4종, xc7z020) | 437 | 199 | 11.5 | 0 | +1.801 ns | 0 |
| 2026-09-26 | `loader_l02_synth` (L-03까지의 임시 fixture; L-03 최초, Conv scatter, xc7z020) | 645 | 212 | 11.5 | 0 | **−0.016 ns 실패** | 0 |
| 2026-09-26 | `loader_l02_synth` (L-03까지의 임시 fixture; L-03 최종, 오류판정 경로 분리, xc7z020) | 631 | 212 | 11.5 | 0 | +1.365 ns | 0 |
| 2026-09-26 | `weight_param_loader` (L-04 정식 Loader 상위, enc 선택 고정, xc7z020) | 631 | 212 | 11.5 | 0 | +1.365 ns | 0 |

X-01 임계 경로: `S_AXI_ARESETN`(입력 포트) → `S_AXI_ARREADY`.
reset이 READY로 가는 조합 경로이며 AXI 권고(리셋 중 READY=0)를 위해 의도한 것이다.
100 MHz에서 여유 3.9 ns로 문제없다.

`timing_100mhz.xdc`의 100 MHz는 **잠정값**이다. 보드·클록은 D10 미결이다.

T-01R은 `xc7z020clg400-1`, 기존 스크립트·잠정 100 MHz 제약으로 1회 합성했다.
조합 루프 0, Setup failing endpoint 0이며 임계 경로는 상태 FF → `status_busy`이다.
합성 단계 자체의 오류·경고는 0이다. 실행 전체에는 Tcl store 접근 권한 관련
`Common 17-741` CRITICAL WARNING, OOC clock 위치 미지정 `Timing 38-242`,
래치 검색 결과가 비어 발생한 `Vivado 12-180` 경고가 있다.
배치·배선 및 hold 검증은 수행하지 않았으며 WNS는 OOC 합성 추정치다.
미사용 주소 snapshot과 미도달 상태는 최적화되고 FSM은 one-hot으로 재인코딩됐다.
RTL의 13상태 인코딩과 snapshot 동작은 RTL 시뮬레이션에서 별도로 확인한다.
[실행 명령·출력 전문](../docs/T-01R_syn_실행로그.txt)

R-01은 두 모듈을 기존 Tcl/XDC로 각각 1회 합성했다. 양쪽 모두 조합 루프 0,
Setup failing endpoint 0, `synth_design` 자체 오류·경고 0이다.
S00는 X-01 대비 LUT +1, FF/BRAM/DSP 및 WNS 변화 0이다. 동기 reset 매핑과
RVALID 게이트 추가 후의 합계이며, 임계 경로는 여전히 `S_AXI_ARESETN` → `S_AXI_ARREADY`다.
같은 +3.895 ns의 AWREADY/BVALID 경로도 보고됐다. M00의 임계 경로는
`M_AXI_ARESETN` → WVALID/전송 성립 논리 → `mem_wr_ready`이며,
`mem_wr_ready`에 별도 reset 게이트를 추가한 것은 아니다.
실행 전체에는 T-01R과 같은 `Common 17-741`, `Timing 38-242`, `Vivado 12-180`
메시지가 있다. OOC 추정치이며 배치·배선/hold 검증은 하지 않았다.
**R-01 회귀는 누적 6/6 PASS다.** 최초 실패한 regs/ctrl TB는 사용자 후속 요청으로
기대값을 유지한 채 reset 검사 시점을 상승 에지 뒤로 보정하고 두 TB를 재실행해 통과했다.
나머지 4개는 앞선 실행의 PASS 결과다. TB 보정 전후 S00/M00/Top RTL 해시가 동일하므로
합성을 반복하지 않았으며 위 결과를 유지한다. Claude 검수·사용자 확인 대기.
[R-01 보고서](../docs/R-01_구현_검증기록.md) ·
[S00 합성 전문](../docs/R-01_syn_S00_AXI_실행로그.txt) ·
[M00 합성 전문](../docs/R-01_syn_M00_AXI_실행로그.txt)

## 2026-09-25 타깃 보드 확정

**Zybo Z7-20 = XC7Z020-1CLG400C.** 이후 모든 합성은 `xc7z020clg400-1` 로 한다.
7z010 으로 잰 기존 행은 비교용으로 남긴다. 속도 등급이 -1 로 같아 타이밍은
사실상 동일하고, 달라지는 것은 자원 여유다 (LUT 17,600 → 53,200,
BRAM 60 → 140, DSP 80 → 220).

## 2026-09-25 Encoder 합성 결과 (동우 전달 필요)

`CNN_Encoder` 는 현재 **합성되지 않는다**.

```
ERROR: [Synth 8-3391] Unable to infer a block/distributed RAM for
       'gen_wide_write.mem_reg' ... number of bits (92160) is too large
ERROR: [Synth 8-6156] failed synthesizing module 'Buffer'
```

`Buffer.v` 의 비대칭 폭 인스턴스(W=64 / R=8 / 11,520 B)가 원인이다.
29 행이 한 클록에 `mem[waddr*RATIO + i]` 로 **8 개 주소를 동시에 쓴다**.
BRAM write 포트는 클록당 1 주소만 쓸 수 있다.
같은 모듈의 대칭 인스턴스(W=8 / R=8 / 20,480 B)는 BRAM36 8 개로 정상 합성된다.
시뮬레이션은 통과하므로 TB 로는 드러나지 않는다.


## 2026-09-25 T-03 LOAD 경로

`pose_cnn_ctrl`을 `xc7z020clg400-1`에 기존 잠정 100 MHz OOC 제약으로 합성했다.
LUT 146 / FF 77 / BRAM 0 / DSP 0, WNS +1.986 ns, 래치 0 / 조합 루프 0이다.
Setup failing endpoint 0이며 임계 경로는 `weight_addr_reg_reg[6]` → `mem_rd_addr[30]`이다.
도달 가능한 6상태를 합성기가 3-bit sequential로 최적화했으며 RTL의 도면 기준
13상태 4-bit localparam은 유지했다. 배치·배선 및 hold 검증은 하지 않았다.

임시 디렉터리에서 첫 실행은 `.Xil/.../realtime/tmp` 삭제 오류로 중단됐다.
RTL 변경 없이 이 syn 디렉터리에서 재실행해 합성을 완료했다.
실행 전체에는 기존 `Common 17-741`(Tcl store), `Timing 38-242`(OOC clock),
`Vivado 12-180`(래치 검색 결과 없음) 메시지가 있다.
[구현·검증 보고서](../docs/T-03_구현_검증기록.md) ·
[완료한 실행 전문](../docs/T-03_synthesis_run.txt) ·
[최초 환경 오류](../docs/T-03_synthesis_initial_issue.txt)


## 2026-09-25 T-04 IN_RD/ENC

기존 `xc7z020clg400-1`, 잠정 100 MHz OOC 조건으로 1회 합성했다.
LUT239 / FF120 / BRAM0 / DSP0, WNS **+1.734 ns**, 래치·조합 루프 0이다.
T-03 대비 LUT +93 / FF +43, **WNS 여유 0.252 ns 감소**(+1.986 → +1.734).
Setup failing endpoint 0, TNS 0으로 현재 제약은 만족한다. 임계 경로는
`cmd_reg_reg[30]` → `mem_rd_addr[10]`의 명령 판정/주소 선택이다.

도달 가능한 8상태는 합성기가 3-bit sequential로 최적화했으며 도면 기준 RTL의
13상태 4-bit localparam은 그대로다. P&R/hold 검증은 하지 않았다.
전체 실행의 기존 환경/제약/조회 메시지 `Common 17-741`, `Timing 38-242`,
`Vivado 12-180`은 유지되며 시뮬레이션 compile/elaboration 경고 0과 구별한다.
[구현·검증 보고서](../docs/T-04_구현_검증기록.md) ·
[합성 명령·출력 전문](../docs/T-04_synthesis_run.txt)

## 2026-09-25 T-05 FC1/D06

기존 `xc7z020clg400-1`, 잠정 100 MHz OOC 조건으로 1회 합성했다.
LUT362 / FF158 / BRAM0 / DSP0, WNS **+1.408 ns**, 래치·조합 루프 0이다.
T-04 대비 LUT +123 / FF +38, **WNS 여유 0.326 ns 감소**(+1.734 → +1.408).
Setup failing endpoint 0, TNS 0. 사용자 지정 중단 기준인 1.0 ns보다 높다.
임계 경로는 `weight_addr_reg_reg[6]/C` → `mem_rd_addr[28]`이며,
9 logic level(CARRY4 7개 + LUT 2개)의 주소 가산/선택 경로다.
다음 경로 `load_base_reg_reg[6]/C` → `mem_rd_addr[30]`은 +1.424 ns다.
임의의 타이밍 완화는 하지 않았다.

도달 가능한 9상태는 합성기가 4-bit sequential로 인코딩했으며 RTL의
13상태 localparam 대조와 별개다. P&R/hold 검증은 하지 않았다.
실행 전체의 기존 `Common 17-741`, `Timing 38-242`, `Vivado 12-180` 메시지는
유지되며 합성 단계 자체 및 시뮬레이션 compile/elaboration 오류·경고는 0이다.
**T-05 전체 완료를 의미하지 않는다.** P7 오류 뒤 FC 복구 방식과 P9 기존 INFER TB
수정 금지 충돌에 대한 사용자 답변을 기다리는 상태다.
[구현·검증 보고서](../docs/T-05_구현_검증기록.md) ·
[합성 명령·출력 전문](../docs/T-05_synthesis_run.txt)

## 2026-09-25 T-06 FC2/FC3/WR와 주소 경로 완화

같은 T-06 기능에서 두 read 주소를 출력 시 가산하는 비교본과, LOAD 진입
에지에 미리 계산해 저장한 최종본을 각각 1회 합성했다. 기존 `xc7z020clg400-1`,
잠정 100 MHz OOC 제약을 유지했고 `mem_rd_addr`/`mem_wr_addr` 출력 자체는
등록하지 않았다. 주소 완화 전/후 **WNS +1.406 → +1.728 ns(0.322 ns 개선)**,
LUT 475→471, FF 191→220이다. T-05 대비 최종 WNS는 0.320 ns 증가했다.

완화 전 임계 경로는 `weight_addr_reg_reg[6]/C` → `mem_rd_addr[30]`이며
CARRY4 7개를 포함한 9 logic level이다. 완화 후에는
`cmd_reg_reg[15]/C` → `mem_rd_addr[0]`의 4 LUT level로 바뀌었다.
두 실행 모두 래치 0 / 조합 루프 0 / setup failing endpoint 0 / TNS 0이다.
WNS가 사용자 중단 기준 1.0 ns 아래로 내려가지 않았다.

합성 단계 자체 오류·경고 0. 전체 실행의 기존 `Common 17-741`,
`Timing 38-242`, `Vivado 12-180` 메시지는 유지된다. P&R/hold 검증은 하지 않았다.
주소 완화만 적용한 T-05 구조에서 기존 FC1 11조건/14회, LOAD 10조건,
상태/CSR TB가 수정 없이 통과했고 이전 관측값을 유지했다.
**최종 T-06의 기존 FC1 TB는 FC1→FINISH 기대와 새 경로가 충돌하므로
전체 회귀 완료를 의미하지 않는다.** 해당 TB 최소 보정 허용 답변을 기다린다.

[T-06 구현·검증 기록](../docs/T-06_구현_검증기록.md) ·
[완화 전 합성 전문](../docs/T-06_synthesis_before_run.txt) ·
[완화 후 합성 전문](../docs/T-06_synthesis_after_run.txt)


## 2026-09-26 T-07 ERR_DRAIN — 13상태 구현 완료

네 read 오류 경로의 제자리 대기를 ERR_DRAIN으로 통합하고, 오류 감지 cycle의
소비 쓰기 차단은 유지했다. 같은 xc7z020clg400-1 / 100 MHz OOC 조건으로 1회 합성했다.
**WNS +1.728 → +1.741 ns(+0.013 ns), LUT 471→457, FF 220→225**,
BRAM/DSP 0이다. 래치 0 / 조합 루프 0 / setup failing endpoint 0 / TNS 0.
임계 경로는 `cmd_reg_reg[30]/C → mem_rd_bytes[11]`, 4 LUT level, 데이터 지연 5.251 ns.
중단 기준 1.0 ns보다 높다. 구현(P&R)/hold 및 실제 BD reset 검증은 포함하지 않는다.

전체 실행의 기존 Common 17-741(Tcl store), Timing 38-242(OOC clock),
Vivado 12-180(래치 셀 검색 0개) 메시지는 그대로 있으며 새 합성 RTL 경고는 없다.
15종 TB 및 동일 TB를 이용한 T-06/T-07 동등성 비교가 통과했다.
마지막 beat read 오류 2건은 ERR_DRAIN 1 cycle 경유로 Top 완료만 1 cycle 늦어진다.
데이터·M00 완료·최종 결과 및 정상 경로의 관측값은 유지된다.

[T-07 구현·검증 기록](../docs/T-07_구현_검증기록.md) ·
[합성 명령·출력 전문](../docs/T-07_synthesis_run.txt)

## 2026-09-26 L-01 Blob Decoder 골격/header

`blob_decoder`를 xc7z020clg400-1 / 기존 100 MHz OOC 제약으로 1회 합성했다.
기본 `CHECK_VERSION=0` 조건에서 LUT135 / FF117 / BRAM0 / DSP0,
WNS **+3.760 ns**, 래치0 / 조합루프0 / setup failing endpoint0 / TNS0이다.
임계 경로는 `ld_data[27] → work_left_reg_reg[1]/D`, LUT5단, 데이터 지연5.206 ns다.
실제 RAM 쓰기는 아직 없으며 출력14개는 상수0이다. L-02 쓰기 로직이나
version 검사를 켠 구성의 자원·타이밍을 대표하지 않는다.

신규 25회 완전 스트림 시험 및 기존15종 TB가 통과했다. 정상 처리 시간은
명세 구간별 합산대로 **9,772 cycle**이며 원문의9,388은 합산 오류다.
기존 Common17-741 / Timing38-242 / Vivado12-180 메시지는 배치 실행에
남아 있다. 시뮬레이션 compile/elaboration 오류·경고는0이다.
구현(P&R)/hold 및 Top 실물 연결은 이번 범위가 아니다.

[L-01 구현·검증 기록](../docs/L-01_구현_검증기록.md) ·
[합성 명령·출력 전문](../docs/L-01_synthesis_run.txt)

## 2026-09-26 L-02 상주 RAM과 Param/FCW/LUT 쓰기

RAM 4종 단독과 decoder+RAM 결합을 각각 1회, 총 5회 합성했다.
표의 L-02 BRAM 수는 **36Kb 환산값**이다. 실제 primitive는 Conv RAMB36 2개,
Param RAMB36 1개 + RAMB18 1개, LUT RAMB18 1개, FCW RAMB36 7개 + RAMB18 1개다.
4종 모두 BRAM으로 추론됐고 LUTRAM은 0이다. RAM 단독의 FF 0은 동기 읽기 저장이
BRAM 내부에 포함된 결과다. Conv 쓰기 경로는 아직 상수 0이지만 이번 결합 합성에서도
Conv RAMB36 2개가 유지됐다. L-03 scatter 구현 완료를 뜻하지 않는다.

결합 결과 LUT 437 / FF 199 / RAMB36 10 + RAMB18 3 / DSP 0 / WNS **+1.801 ns**.
임계 경로는 `ld_data[8] → u_fcw_ram/mem_reg_0/ADDRARDADDR[10]`, LUT 6단,
데이터 지연 6.522 ns다. 모든 실행 래치 0 / 조합 루프 0 / setup failing endpoint 0 / TNS 0.
100 MHz OOC 제약이며 P&R/hold는 하지 않았다. L-01 단독 골격과는 합성 범위가 다르다.
기존 Common 17-741 / Timing 38-242 / Vivado 12-180 메시지가 있으며 새 RTL 합성 오류는 없다.

신규 RAM TB 및 decoder 완전 LOAD 38회, 기존 15종 TB가 통과했다.
정상 처리 시간은 L-01과 같은 9,772 cycle이다. 기존 23파일 무변경.
`loader_l02_synth.v`는 재현용 합성 fixture이며 Top/core 연결이 아니다.

[L-02 구현·검증 기록](../docs/L-02_구현_검증기록.md) ·
[결합 합성 전문](../docs/L-02_synthesis_loader_l02_synth.txt)

## 2026-09-26 L-03 Conv Weight byte scatter

같은 `loader_l02_synth` fixture, xc7z020clg400-1 / 100 MHz OOC 조건으로
decoder와 RAM 4종을 결합 합성했다. 최초 WNS **−0.016 ns** 실패 후,
Conv 주소 경로에서 불필요한 현재 입력의 header/shift 오류 판정을 분리했다.
최종 WNS **+1.365 ns**, LUT 631 / FF 212 / RAMB36 10 + RAMB18 3 / DSP 0이다.
래치 0 / 조합 루프 0 / setup failing endpoint 0 / TNS 0.

L-02 대비 LUT **+194(+44.4%)**, FF +13, WNS −0.436 ns이며 BRAM은 같다.
Conv tap/oc 카운터와 byte 선택·lane 배치·주소·제어 회로가 추가됐다.
RTL에는 나눗셈·나머지 연산이 없으며, LUT 수만으로 나눗셈기 유무를 판정하지 않았다.
최종 임계 경로는 `u_blob_decoder/beat_count_reg_reg[1]/C`에서
`u_conv_weight_ram/mem_reg_0/ADDRBWRADDR[13]`까지, 8 logic level,
데이터 지연 7.985 ns이다. P&R/hold와 보드 검증은 포함하지 않는다.

정상 Conv 5,328 byte 전량 대조에서 미기록·중복·불일치 0이며,
기존 9,772 cycle / READY low 6,050을 유지했다. 타이밍 수정 전후
성공 관측 561줄이 동일하다. Loader 완전 스트림 38회, 무수정 RAM TB와
기존 15종 TB가 통과했고 보호 대상 28파일은 변경하지 않았다.
시뮬레이션 compile/elaboration 오류·경고는 0이다. 최종 합성 실행에는
기존 Common 17-741(Tcl store), Timing 38-242(OOC clock),
Vivado 12-180(래치 검색 0개) 메시지가 남아 있다.

[L-03 구현·검증 기록](../docs/L-03_구현_검증기록.md) ·
[최초 합성 전문](../docs/L-03_synthesis_initial_run.txt) ·
[최종 합성 전문](../docs/L-03_synthesis_run.txt)

## 2026-09-26 L-04 정식 Loader 상위 모듈

`weight_param_loader`를 top으로 Decoder와 RAM 4종의 RTL을 읽어 1회 합성했다.
xc7z020clg400-1 / 같은 100 MHz OOC 제약에서 LUT 631 / FF 212 /
RAMB36 10 + RAMB18 3 / DSP 0 / WNS **+1.365 ns**로 L-03 최종 결합과 같다.
래치 0 / 조합 루프 0 / TNS 0 / setup failing endpoint 0이다.
임계 경로도 `u_blob_decoder/beat_count_reg_reg[1]/C` →
`u_conv_weight_ram/mem_reg_0/ADDRBWRADDR[13]`, 8 logic level,
데이터 지연 7.985 ns로 같다. 실행 wall-clock은 34.842초다.

상위의 Param/LUT 주소 mux는 명시했으나 `fc_active=0`이므로 합성에서
enc 경로로 최적화된다. D09의 실제 선택 신호가 연결된 구성의 비용·타이밍을
대표하지 않는다. 이후 Loader 합성 대상은 `weight_param_loader`이며,
`loader_l02_synth.v`는 과거 결과 재현용으로 보존하고 새 작업에는 사용하지 않는다.

외부 24포트 원문 대조, 포트만 사용하는 RAM 전량 대조와 1-cycle 읽기 검사,
6회 완전 LOAD·1회 중단/reset 시험, 무수정 기존 17종 TB가 통과했다.
정상 9,772 cycle / READY low 6,050 및 기존 회귀 관측 1,168줄이 그대로다.
기존 RTL/TB 30파일 무변경. 시뮬레이션 compile/elaboration 오류·경고 0.
합성에는 기존 Common 17-741 / Timing 38-242 / Vivado 12-180 메시지가 있다.
P&R/hold, Top 실물 연결과 FC 선택은 이번 검증 범위 밖이다.

[L-04 구현·검증 기록](../docs/L-04_구현_검증기록.md) ·
[상위 TB 명령·출력 전문](../docs/L-04_wrapper_run.txt) ·
[합성 명령·출력 전문](../docs/L-04_synthesis_run.txt)

## 2026-09-26 L-07 D09 Param/LUT 읽기 주소 선택

사용자 확정 C안에 따라 Top 선택 출력 2개와 Loader 주소 mux를 연결했다.
xc7z020clg400-1 / 기존 100 MHz OOC 제약으로 각 top을 1회씩 합성했다.

| 대상 | 이전 LUT → 현재 | FF | RAMB36 / RAMB18 | DSP | 이전 WNS → 현재 | 래치 / 조합 루프 |
|---|---:|---:|---:|---:|---|---|
| Loader | 631 → 650 (+19) | 212 → 212 | 10 / 3 (동일) | 0 | +1.365 → +1.365 ns | 0 / 0 |
| Top FSM | 457 → 455 (−2) | 225 → 225 | 0 / 0 (동일) | 0 | +1.741 → +1.741 ns | 0 / 0 |

Loader는 9-bit Param + 10-bit LUT 주소 선택이 더 이상 상수로 최적화되지 않는다.
Top LUT 감소는 이번 전체 합성의 관측값이다. 선택 디코드만의 독립 자원 비용을 뜻하지 않는다.
두 결과 모두 중단 기준 +1.0 ns를 웃돈다. TNS 0, setup failing endpoint 0.

Loader 임계 경로는 `u_blob_decoder/beat_count_reg_reg[1]/C` →
`u_conv_weight_ram/mem_reg_0/ADDRBWRADDR[13]`, 8 logic level, 데이터 지연 7.985 ns.
Top 임계 경로는 `cmd_reg_reg[30]/C` → `mem_rd_bytes[11]` 및 `mem_rd_start`,
4 logic level, 데이터 지연 5.251 ns다. 기존 임계 경로/여유와 같다.
실행 wall-clock은 Loader 36.330초, Top 45.798초다.

합성에는 기존 Common 17-741(Tcl store 접근), Timing 38-242(OOC clock skew),
Vivado 12-180(래치 검색 0개) 메시지가 남아 있다. RTL 합성 오류는 없다.
각각의 단독 합성 결과이므로 Top 선택 출력부터 Loader BRAM까지의 전체 경로,
P&R/hold 및 보드 타이밍은 X-02/X-03에서 별도 확인한다.

[L-07 구현·검증 기록](../docs/L-07_구현_검증기록.md) ·
[Loader 합성 명령·출력 전문](../docs/L-07_synthesis_loader.txt) ·
[Top 합성 명령·출력 전문](../docs/L-07_synthesis_ctrl.txt)

## 2026-09-26 E-01 Encoder Buffer BRAM 변환 후보

원본 `others/CNN_Encoder`는 보존했다. 입력 Buffer를 넓은 word 저장소와
같은 에지에 등록한 lane index로 바꾼 후보의 OOC 합성이 성공했다.
외부 작업의 공유 폴더 재복사를 확인하여, 실제 검증 대상은 scratch에 고정했다.
공유 `rtl/encoder` 반영은 동시 편집 종료 확인 대기다. 검증한 소스는
[후보 ZIP](../docs/E-01_encoder_candidate.zip)과 SHA-256으로 보존했다.

xc7z020clg400-1 / 기존 100 MHz 제약. LUT **6,490** / FF **3,530** /
RAMB36 **13** / RAMB18 0 / DSP **10**, 래치 0 / 조합 루프 0.
입력 Buffer(1,440×64-bit)는 RAMB36 **4개**, fmap Buffer(20,480×8-bit)는
**8개**, Pool 결과 RAM은 1개다. 두 Buffer 모두 저장소가 BRAM으로 추론됐다.
LUTRAM 0 / 전체 SRL 27개. 합성 wall-clock 72.344초.

**전체 WNS −3.641 ns, TNS −447.829 ns, setup failing endpoint 684개로 타이밍 실패.**
임계 경로는 `u_enc_rq/param3_reg[69]/C` → `u_enc_rq/rq_reg[1]/R`,
데이터 지연 13.033 ns, logic level 31이다. Conv_MAC 내부 FF 간 WNS는
+1.325 ns지만, 입력 Buffer BRAM → MAC 누산 FF 경로는 **−0.798 ns**다.
과거 단독 MAC +1.093 ns와 내부 경로의 수치 차이는 +0.232 ns이나,
합성 경계가 다르므로 전체 연결 타이밍이 유지됐다는 근거로 쓰지 않는다.

기능 비교는 실제 blob과 2종 입력, 2,557,780개 에지에서 외부 출력 5개와
버퍼 출력 2개 모두 불일치 0. 별도 Buffer 5구성 119,312 검사 통과.
각 실행의 완료 경과 주기는 1,278,889이며 START/완료 포함 비교 개수는
1,278,890이다. 원본과 후보가 같은 에지에 끝난다. 기존 19종 TB도 무수정 통과.

합성에는 기존 Common 17-741 / Timing 38-242 / Vivado 12-180 경고가 있다.
시뮬레이션 compile/elaboration 오류·경고는 0이다. TEMP CWD에서 발생한
Vivado 임시 폴더 정리 오류는 기존 `syn` CWD 사용으로 해결했다.
100 MHz 타이밍 수정, P&R/hold 및 코어 통합은 완료로 표시하지 않는다.

[구현·검증 기록](../docs/E-01_구현_검증기록.md) ·
[합성 명령·출력 전문](../docs/E-01_synthesis_run.txt) ·
[원본 대비 패치](../docs/E-01_encoder_patch.diff)

## 2026-09-26 X-02a 코어 구성 블록 재합성

`pose_cnn`은 실물 ctrl/Loader/Encoder와 TB 전용 `fc_stub`을 연결한 순수 배선이다.
코어 자체를 합성하지 않고 실물 세 블록을 기존 100 MHz OOC 조건으로 각각 합성했다.
현재 `rtl/encoder` 6개 파일이 E-01 검증 후보와 해시까지 같음을 확인했다.

| 블록 | LUT / FF | RAMB36 / RAMB18 | DSP | WNS | 이전 대비 |
|---|---|---|---:|---|---|
| pose_cnn_ctrl | 455 / 225 | 0 / 0 | 0 | +1.741 ns | 동일 |
| weight_param_loader | 650 / 212 | 10 / 3 | 0 | +1.365 ns | 동일 |
| CNN_Encoder | 6,490 / 3,530 | 13 / 0 | 10 | **−3.641 ns 실패** | 동일 |

모두 래치 0 / 조합 루프 0. Encoder 임계 경로는 requant 내부
`param3_reg[69]/C` → `rq_reg[*]/R`로 그대로다. 타이밍 개선은 이번 범위에 넣지 않았다.
각각의 단독 결과이며 코어 통합 합성/P&R 수치나 실제 FC 포함 자원을 뜻하지 않는다.
wall-clock은 ctrl 51.837초, Loader 48.477초, Encoder 92.104초.
기존 Common 17-741 / Timing 38-242 / Vivado 12-180 메시지가 있다.

[ctrl 로그](../docs/X-02a_synthesis_pose_cnn_ctrl.txt) ·
[Loader 로그](../docs/X-02a_synthesis_weight_param_loader.txt) ·
[Encoder 로그](../docs/X-02a_synthesis_CNN_Encoder.txt)

## 2026-09-26 F-01 저장소 3종

FIFO full 동시 read/write는 write를 버리고 512→511로 동작하도록 확정됐다.
FIFO/hidden/pose 각각과 3종 묶음의 OOC 합성을 완료했다.
xc7z020clg400-1, 기존 100 MHz 및 입출력 2 ns 제약. P&R 결과는 아니다.

| 대상 | LUT (중 LUTRAM) | FF | RAMB36/18 | DSP | WNS | 래치/조합 루프 |
|---|---:|---:|---|---:|---|---|
| fc1_weight_fifo | 104 (0) | 93 | 1/0 | 0 | +2.641 ns | 0/0 |
| hidden_buffer | 73 (64) | 64 | 0/0 | 0 | +5.501 ns | 0/0 |
| pose_buffer | 25 (0) | 192 | 0/0 | 0 | +5.501 ns | 0/0 |
| 3종 묶음 fc_storage_ooc | 170 (64) | 349 | 1/0 | 0 | +2.615 ns | 0/0 |

FIFO의 512×64 저장 배열은 **RAMB36E1 1개**로 추론됐다. 동기 RAM 읽기와
첫 word/단일 word 교체용 bypass로 FWFT를 제공한다. hidden은 RAM32M 16개,
pose는 FF 192개다. 묶음 LUT는 합성기 최적화 결과이므로 단독 LUT의 단순 합과 다르다.
FIFO 임계 경로는 BRAM 출력 → fifo_rdata 출력 mux다.
wall-clock: FIFO 50.517초, hidden 58.834초, pose 44.941초, 묶음 52.762초.
hidden/pose 단독 결과는 소스 무변경을 확인하고 앞선 결과를 유지했다.
기존 Common 17-741 / Timing 38-242 / Vivado 12-180 환경·빈 검색 경고가 있다.

[F-01 검증 기록](../docs/F-01_구현_검증기록.md) ·
[FIFO 로그](../docs/F-01_synthesis_fc1_weight_fifo.txt) ·
[hidden 로그](../docs/F-01_synthesis_hidden_buffer.txt) ·
[pose 로그](../docs/F-01_synthesis_pose_buffer.txt) ·
[묶음 로그](../docs/F-01_synthesis_fc_storage_ooc.txt)

## 2026-09-26 F-02 FC MAC

8-lane signed INT8 곱셈/파이프라인 누산. DSP 강제 없음.
xc7z020clg400-1, 기존 100 MHz OOC 및 입력/출력 delay 2 ns 제약.

| 대상 | LUT (중 LUTRAM) | FF | RAMB36/18 | DSP | WNS | 래치/조합 루프 |
|---|---:|---:|---|---:|---|---|
| fc_mac | 799 (0) | 616 | 0/0 | 0 | +3.895 ns | 0/0 |
| MAC + FIFO/hidden/pose | 955 (64) | 965 | 1/0 | 0 | +3.857 ns | 0/0 |

Vivado가 8개 곱셈을 LUT로 구현했다. 묶음은 FIFO RAMB36E1 1개,
hidden RAM32M 16개, pose FF 192개를 포함한다. FCW는 Loader 소유 외부 포트로 남겼다.
단독 임계 경로는 fifo_empty→fifo_re(2.070 ns), 묶음은 FIFO count[9]→fifo_full(3.135 ns).
두 WNS 모두 +1.0 ns 중단 기준 이상. P&R/후처리/코어 전체 타이밍 수치가 아니다.
wall-clock은 각각 50.382 / 31.309초.

기존 Common 17-741 / Timing 38-242 / Vivado 12-180 경고와 단독 MAC의
Netlist 29-101(flat primitive 수에 따른 floorplanning 안내)을 보존했다. 합성 오류 0.
시뮬레이션 compile/elaboration 오류·경고 0. golden 누산값 280개 불일치 0.

[F-02 검증 기록](../docs/F-02_구현_검증기록.md) ·
[MAC 합성 전문](../docs/F-02_synthesis_fc_mac.txt) ·
[묶음 합성 전문](../docs/F-02_synthesis_fc_mac_storage_ooc.txt)


## 2026-09-26 F-03a requant 파라미터화 — 타이밍 기준으로 중단

태그 폭/Param 주소만 파라미터화. 산술·reset/순차 블록 byte 동일.
xc7z020clg400-1, 기존 100 MHz OOC / 입출력 2 ns 제약, P&R 아님.

| 대상 | LUT (중 LUTRAM) | FF | BRAM36 | DSP | WNS | 실패 endpoint |
|---|---:|---:|---:|---:|---|---:|
| CNN_Encoder 전 | 6490 (27) | 3530 | 13 | 10 | −3.641 ns | 684 |
| CNN_Encoder 후 | 6490 (27) | 3530 | 13 | 10 | −3.641 ns | 684 |
| FC requant 단독 | 966 (9) | 157 | 0 | 7 | **−3.494 ns** | 15 |
| FC MAC + requant | 1742 (9) | 773 | 0 | 7 | **−3.494 ns** | 15 |

모두 래치 0 / 조합 루프 0. Encoder 전후 모든 수치와 임계 경로 동일.
FC 두 구성은 +1.0 ns 중단 기준 미달로 추가 RTL 변경을 멈췄다.
임계 경로는 `param3[69]` (`shift[5]`) → `rq[1]/R`, data path 12.886 ns / logic 31단.
DSP 강제 없음. FC 합성 fixture의 RAM은 외부 포트여서 BRAM 0이다.
단계 전체 완료나 100 MHz 타이밍 충족으로 표시하지 않는다. E-02 판단 필요.

기능: FC golden 280개 일치, saturation/rounding/Param 변형 통과.
G-02 및 Encoder 등가성, 기존 24 TB 무수정 통과. 컴파일/elaboration 경고·오류 0.
합성 환경/빈 검색 경고는 로그에 보존했다.

[검증 기록](../docs/F-03a_구현_검증기록.md) ·
[Encoder 전](../docs/F-03a_synthesis_encoder_before.txt) ·
[Encoder 후](../docs/F-03a_synthesis_encoder_after.txt) ·
[FC 단독](../docs/F-03a_synthesis_fc_requant_ooc.txt) ·
[MAC+RQ](../docs/F-03a_synthesis_fc_mac_requant_ooc.txt)


## 2026-09-26 E-02a requant P&R 측정

RTL/TB 무변경. xc7z020clg400-1, Vivado 2020.2. 기존 timing_100mhz.xdc의
I/O delay 2 ns를 유지하고 새 impl_check.tcl로 OOC synth → opt → place → phys_opt → route 실행.
아래는 **post-route** 결과다. 기존 합성 추정값과 구분한다.

| 대상 | 주기 ns | directive | LUT | FF | BRAM tile | DSP | WNS | 실패 setup endpoint |
|---|---:|---|---:|---:|---:|---:|---:|---:|
| Encoder | 10.000 | default | 6557 | 3639 | 13 | 10 | -3.562 ns | 1485 |
| Encoder | 10.000 | performance | 6617 | 3654 | 13 | 10 | -3.160 ns | 1523 |
| FC MAC+RQ | 10.000 | default | 1779 | 851 | 0 | 7 | -2.413 ns | 15 |
| FC MAC+RQ | 10.000 | performance | 1776 | 871 | 0 | 7 | -2.133 ns | 15 |
| Encoder | 13.160 | performance | 6444 | 3608 | 13 | 10 | -0.268 ns | 32 |
| Encoder | 13.500 | performance | 6365 | 3582 | 13 | 10 | -0.052 ns | 7 |
| Encoder | 14.000 | performance | 6377 | 3608 | 13 | 10 | +0.182 ns | 0 |

100 MHz는 기본/성능 두 directive 모두 미달했다. 성능 실행에서도 Encoder requant
−2.986 ns, Conv MAC −2.824 ns, Pool −3.160 ns가 남아 requant 단독 문제로 볼 수 없다.
Encoder OOC 확인 통과점은 14.000 ns / 71.429 MHz다. 기존 1,338,265 cycle 환산 18.735710 ms. 절대 Fmax나 최종 BD 보장값이 아니다.
74.074 MHz 확인은 −0.052 ns로 실패했다. pipeline 여부와 D10 결정은 보류한다.

모든 완료 route: 래치 0 / 조합 루프 0 / hold 실패 0 / routing errors 0.
HD.CLK_SRC·HD.PARTPIN_LOCS 미지정으로 OOC clock/port 지연 일부는 추정이다.
특히 Pool 입력 경로와 그 경로로 계산한 Fmax는 이 한계를 받는다.
pose_cnn + 변경하지 않은 fc_stub 참고 실행은 fc_stub.v:76 합성 오류로 중단했다.
기본 10 ns 두 실행은 P&R 완료 후 보조 속성 조회 오류로 exit 1이었고,
저장 checkpoint를 다시 열어 동일 WNS·배선 완료를 검증했다. 원래 로그/종료 코드는 보존했다.

RTL 21 / TB 30 / golden 28 / others 14 / 참고 원본 299 / 기존 Tcl·XDC 2:
총 **394 파일 SHA-256 및 파일 목록 무변경**. 시뮬레이션 실행 없음.

[E-02a 측정 기록·모든 실행 로그](../docs/E-02a_측정기록.md) ·
[구간별 지연](../docs/E-02a_구간별지연.md) ·
[파일별 해시](../docs/E-02a_hash_audit.json)
