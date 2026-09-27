# S00_AXI CSR 인계 — 민영 전달용

작성·최종 확인: **2026-09-24** / 전달: 한림 → 민영  
대상: **`pose_cnn_v1_0_S00_AXI.v`, S00-05 완료본**

## 1. 전달 요약과 현재 상태

S00_AXI의 CSR 기능 구현과 네 개 TB의 기능 검증을 마쳤다. 민영은 이 RTL을 기준으로 **IP 패키징·Vivado BD 연결·PS 제어부**를 준비하면 된다. 현재 확정된 PS 계약을 전달하는 문서이며, 아래에서 별도로 표시한 미결 사항은 아직 구현 규격으로 확정하지 않는다.

- 구현 완료: AW/W 독립 수락, 4개 RW 저장소와 WSTRB 병합, CONTROL 등록 펄스, commit 시점 busy/DDR 정렬 거부, BRESP 저장, 읽기 snapshot과 STATUS mux, scale 조건부 SLVERR.
- 최종 정적 재검토에서 확정 계약과 어긋나 수정이 필요한 RTL 결함을 찾지 못했다. 기존 wrapper의 **전체 포트 32개(AXI·clock/reset 21개 + CSR 11개)** 연결 이름과 폭도 확인했다.
- `PROJECT_CONTEXT.md` 8절에는 S00-05 구현·Claude 검수 완료와 추가 독립 검증 통과가 기록되어 있다. 본 인계 작성 때에는 코드와 연결을 재검토했고, 이미 통과한 시뮬레이션을 반복 실행하지 않았다.
- **합성·타이밍·실제 Top/Loader/M00 통합·보드 실행은 아직 검증하지 않았다.** CSR 기능 완료를 전체 CNN IP 완료로 해석하지 않는다.
- RTL 지원 설정은 **`C_S_AXI_DATA_WIDTH=32`, `C_S_AXI_ADDR_WIDTH=5`**뿐이다. 파라미터 선언이 다른 폭의 지원을 뜻하지 않는다. M00의 64-bit 데이터 폭과 S00의 32-bit CSR 폭은 별개다.

인계 RTL SHA-256:

```text
C843BFB058F33E3ED75F6CC7353DCCE82129A084F82903BD27AB70A2951D35C7
```

## 2. 함께 전달할 파일과 기준 문서

작성 환경 루트는 `D:\2609_final_project`다. 다른 PC에서는 프로젝트 루트만 해당 환경에 맞춘다. 아래 전체 `cnn_rtl` 폴더를 함께 전달하면 RTL·TB·문서를 같은 버전으로 유지하기 쉽다.

| 파일 | 용도 |
| --- | --- |
| [RTL](D:/2609_final_project/cnn_rtl/rtl/pose_cnn_v1_0_S00_AXI.v) | 합성용 S00_AXI 소스. 패키징할 구현은 이 파일이다 |
| [쓰기 handshake TB](D:/2609_final_project/cnn_rtl/tb/tb_s00_axi_write.v) | AW/W 도착 순서, 보류, commit/B 1회성 |
| [RW 저장소 TB](D:/2609_final_project/cnn_rtl/tb/tb_s00_axi_regs.v) | 선택 저장, byte 병합, RO 쓰기, 주소 별칭, reset |
| [읽기 TB](D:/2609_final_project/cnn_rtl/tb/tb_s00_axi_read.v) | STATUS/scale, snapshot, R stall, 읽기·쓰기 독립 |
| [CONTROL/거부 TB](D:/2609_final_project/cnn_rtl/tb/tb_s00_axi_ctrl.v) | 펄스·busy·정렬·응답 고정, N=1/2/8 코어 모형 |
| [검증 기록 전문](D:/2609_final_project/cnn_rtl/docs/S00-05_검증기록.md) | 실제 실행 명령·출력·최종 해시. 기존 기록을 내용 변경 없이 동봉 |

계약의 우선순위는 최신 사용자 결정 → [PROJECT_CONTEXT.md 5.1절](D:/2609_final_project/PROJECT_CONTEXT.md:83) → 인터페이스 명세의 변경되지 않은 항목이다. 상세 설계 초안의 미결·권장 표기를 현재 결정으로 되돌리지 않는다.

- 명세 원본: [Pose_CNN_IP_Interface_Spec.xlsx](D:/2609_final_project/IP_v1_0/IP_v1_0/interface_spec/Pose_CNN_IP_Interface_Spec.xlsx), `02_S00_AXI` 및 오류 코드의 `00_개요`.
- 기존 연결 참고: [wrapper](D:/2609_final_project/IP_v1_0/IP_v1_0/rtl_template/pose_cnn_v1_0.v:122). S00 인스턴스와 이번 소스의 포트가 일치한다. 이번 작업에서 wrapper를 수정하거나 전체 wrapper를 빌드하지 않았다.
- 참고 저장소 `D:\2609_final_project\wifi-csi-pose-main`은 원본을 보존한다. PS 수정본은 별도 작업 위치에서 작성한다.

## 3. PS가 사용하는 레지스터 맵

아래는 **CSR base에 더하는 byte offset**이다. 예를 들어 COMMAND는 `BASE + 0x08`이다. word 번호 `2`를 주소로 쓰면 안 된다. `AWADDR/ARADDR[4:2]`로 선택하며 하위 2bit만 무시한다. 따라서 `0x0C`와 `0x0E`는 같은 CSR이지만, PS는 정렬된 아래 주소만 사용한다.

| Offset | 이름 | 읽기 | 쓰기·초깃값 |
| --- | --- | --- | --- |
| `0x00` | CONTROL | 항상 0 / OKAY | bit0 START, bit1 CLEAR_STATUS. 저장하지 않고 1-cycle 펄스 발생 |
| `0x04` | STATUS | 아래 비트 배치 / OKAY | 무시 / OKAY. 입력 상태를 조립하며 CSR에 별도 상태 저장소 없음 |
| `0x08` | COMMAND | 저장값 / OKAY | RW 32bit, reset=0. `0=INFER`, `1=LOAD` |
| `0x0C` | INPUT_ADDR | 저장값 / OKAY | RW 32bit, reset=0. DDR 주소 값 **8 B 정렬** |
| `0x10` | WEIGHT_ADDR | 저장값 / OKAY | RW 32bit, reset=0. blob DDR 주소 값 **8 B 정렬** |
| `0x14` | OUTPUT_ADDR | 저장값 / OKAY | RW 32bit, reset=0. DDR 주소 값 **32 B 정렬** |
| `0x18` | OUTPUT_SCALE_BITS | cfg_ok=1: scale 비트 / OKAY. cfg_ok=0: **0 / SLVERR** | 무시 / OKAY |
| `0x1C` | RESERVED | 항상 0 / OKAY | 무시 / OKAY |

STATUS는 읽어도 지워지지 않는다. reset 뒤 STATUS가 0이 되는 것은 Top/Loader가 상태 입력을 초기화한다는 시스템 계약에 달려 있다. S00가 이 입력들을 지우지는 않는다.

| STATUS 비트 | 의미 | PS 마스크 |
| --- | --- | --- |
| 0 | busy | `0x01` |
| 1 | done | `0x02` |
| 2 | error = `status_error != 0` | `0x04` |
| 3 | cfg_ok | `0x08` |
| 7:4 | error_code | `(status >> 4) & 0xF` |
| 31:8 | 0 | — |

명세의 실행 오류 코드는 `0=OK`, `1=BAD_CMD`, `2=NO_CFG`, `3=BLOB_ERR`, `4=MEM_RD_ERR`, `5=MEM_WR_ERR`, `6~15=예약`이다. **생성과 우선순위 처리는 Top/Loader/M00 연결 책임**이며 S00는 4bit 입력을 그대로 보여준다. COMMAND에 0/1 이외의 값을 저장하는 것 자체는 허용하며, START 때 Top이 의미를 검사한다.

## 4. 쓰기 수락·거부 규칙

`BRESP/RRESP`: `2'b00=OKAY`, `2'b10=SLVERR`. 아래 쓰기 판정은 **AW/W 수락 시점이 아닌 commit 시점**에 수행하고 결과를 저장한다.

| 우선순위 | 조건 | 결과 |
| --- | --- | --- |
| 1 | STATUS / SCALE / RESERVED 쓰기 | busy·WSTRB와 무관하게 무시 + OKAY |
| 2 | CONTROL, `WSTRB[0]=0` | busy와 무관하게 펄스 없음 + OKAY |
| 3 | CONTROL, `WSTRB[0]=1`, START bit=1, busy=1 | **SLVERR, START/CLEAR 모두 억제** |
| 4 | 나머지 CONTROL 쓰기 | 유효 START/CLEAR bit만 펄스로 발생 + OKAY |
| 5 | COMMAND / 주소 RW 쓰기, busy=1 | **WSTRB=0이어도 SLVERR**, 값 전체 보존 |
| 6 | DDR 주소 RW 쓰기, busy=0, 병합 후보 정렬 위반 | **SLVERR**, 값 전체 보존 |
| 7 | 나머지 idle RW 쓰기 | 병합 반영 + OKAY. WSTRB=0이면 무변화 |

WSTRB는 `[0]→[7:0]`, `[1]→[15:8]`, `[2]→[23:16]`, `[3]→[31:24]`를 선택한다. DDR 정렬은 **기존값과 선택 byte를 합친 후보**로 검사한다. INPUT/WEIGHT는 후보 `[2:0]==0`, OUTPUT은 후보 `[4:0]==0`이어야 한다. 비선택 WDATA의 낮은 bit는 검사에 영향을 주지 않는다. 잘못된 값을 강제로 정렬하거나 일부 byte만 저장하지 않는다.

CONTROL 예약 bit `[31:2]`는 무시한다. idle에서 `CONTROL=3`은 두 펄스를 함께 발생시키며, busy에서는 쓰기 전체를 거부한다. busy 중 CLEAR 단독은 하드웨어에서 허용하지만 **정상 PS 규격은 idle에서만 CLEAR**하는 것이다.

SLVERR는 해당 요청의 거부 응답이다. **진행 중 CNN을 정지시키거나 STATUS.error_code를 기록하는 기능은 아니다.** CSR의 OKAY도 CNN 실행 성공을 뜻하지 않는다. PS가 bus 오류를 어떻게 관찰하는지는 실제 MMIO 경로에서 민영이 확인해야 하며, 정상 흐름은 아래 규격으로 SLVERR를 피한다.

## 5. AXI 채널과 시간 관계

- AW와 W는 각각 1-entry에 독립적으로 저장한다. 서로 다른 cycle에 도착해도 된다. READY에 반대 채널 VALID나 busy를 사용하지 않는다.
- 둘을 모두 보유한 뒤 한 번 commit한다. 설정 반영·펄스·B 응답을 이 지점에서 결정한다.
- BVALID를 보유하는 동안 새 AW/W를 받지 않는다. **B handshake 에지에도 새 쓰기를 받지 않는다.** BREADY가 낮아도 BRESP는 유지되며 펄스가 반복되지 않는다.
- AR은 읽기 응답이 없을 때 하나만 수락한다. 그 에지의 RDATA/RRESP를 저장하고 R handshake까지 유지한다. **R handshake 에지에 새 AR을 받지 않는다.**
- 읽기와 쓰기는 독립이다. B stall은 읽기를, R stall은 쓰기를 막지 않는다. 읽기 1건과 쓰기 1건이 각각 진행될 수 있다.
- AR과 CSR write commit 또는 Top 상태 갱신이 같은 에지에 겹치면 **갱신 전 값**을 읽는다. 따라서 PS는 쓰기 완료와 읽기 발행의 순서를 보장해야 한다.

commit 에지를 E0로 놓은 START 연결 예:

| 에지 | 동작 |
| --- | --- |
| E0 | START 쓰기를 수락 판정하고 `reg_start=1`, B 응답 등록 |
| E1 | Top이 START를 샘플해 설정을 저장하고 busy=1. S00의 START 펄스는 0으로 복귀. BREADY=1이면 첫 B 수락 |
| E2 | 다음 AW/W를 가장 빨리 수락할 수 있는 에지 |
| E3 | 두 번째 쓰기의 가장 빠른 commit. **이 에지 직전 busy**로 판정 |

첫 실행 busy가 N=1 cycle이면 E3 이전에 이미 종료되어 두 번째 START가 OKAY인 것이 맞다. N=2 이상이면 위 가장 빠른 두 번째 commit은 busy=1을 보고 거부된다. 검증한 핵심 성질은 **busy=1에서 commit된 START는 항상 거부**된다는 것이다. PS는 짧은 busy=1을 반드시 관찰하려고 기다리지 않는다.

## 6. Top/Loader와 연결하는 CSR 선 11개

방향은 S00_AXI 기준이다. 모두 `S_AXI_ACLK`와 같은 clock 영역에서 사용한다.

| 신호 | 방향·폭 | 연결과 책임 |
| --- | --- | --- |
| `reg_start` | 출력 1bit | 등록된 1-cycle 펄스 → Top. Top이 다음 상승 에지에 수락 |
| `reg_clear_status` | 출력 1bit | 등록된 1-cycle 펄스 → Top. 표시 상태 해제 요청 |
| `reg_cmd` | 출력 32bit | 저장된 COMMAND → Top |
| `reg_input_addr` | 출력 32bit | 저장된 INPUT_ADDR → Top |
| `reg_weight_addr` | 출력 32bit | 저장된 WEIGHT_ADDR → Top |
| `reg_output_addr` | 출력 32bit | 저장된 OUTPUT_ADDR → Top |
| `status_busy` | 입력 1bit | Top이 생성. 쓰기 거부와 STATUS에 사용 |
| `status_done` | 입력 1bit | Top의 sticky 완료 표시 |
| `status_error` | 입력 4bit | Top의 sticky 오류 코드 |
| `cfg_ok` | 입력 1bit | Loader/Top 연결에서 제공하는 설정 유효 상태 |
| `output_scale_bits` | 입력 32bit | Loader의 scale float32 비트 패턴. S00는 연산 없이 전달 |

Top에 요구되는 확정 계약:

1. 수락된 `reg_start` 다음 상승 에지에 command/주소를 저장하고 busy=1로 만든다. 이후 실행은 저장한 설정을 사용한다.
2. 즉시 오류도 busy를 최소 1 cycle 유지한다. 이는 상태 전이를 일정하게 하기 위한 계약이다.
3. 새 START는 이전 done/error를 해제한다. 같은 START의 BAD_CMD/NO_CFG 등 새 오류는 남긴다.
4. 새 오류 > 새 완료 > START/CLEAR 해제 순으로 경합을 처리한다.
5. CLEAR는 표시만 지우며 실행이나 내부 실패 기록을 취소하지 않는다. 작업 종료 때 결과를 다시 표시한다.
6. 출력 쓰기 성공의 done은 마지막 AXI B 응답까지 끝난 뒤에만 발생한다. 오류 뒤 남은 메모리 응답 처리와 복구의 세부 구현은 D08에서 결정한다.

이 항목들은 **CSR 내부에서 구현한 기능이 아니라 Top/Loader 통합 시 만족해야 할 계약**이다. 현재 TB의 코어 모형이 실제 Top 구현을 대신하지 않는다.

## 7. 민영의 IP 패키징·Vivado 연결 항목

| 항목 | 적용 내용 / 현재 상태 |
| --- | --- |
| 합성 소스 | 위 `cnn_rtl/rtl`의 S00_AXI를 등록. 같은 모듈 이름의 구형 소스를 중복 포함하지 않음 |
| TB 분리 | `cnn_rtl/tb`의 파일과 그 안의 코어 모형은 simulation sources 전용 |
| 파라미터 | S00 DATA_WIDTH=32, ADDR_WIDTH=5 고정. wrapper의 `C_S00_AXI_*`가 이 값으로 전달됨 |
| 버스 | S00_AXI는 AXI4-Lite 제어 인터페이스. AWADDR/ARADDR 5bit, WDATA/RDATA 32bit, WSTRB 4bit, BRESP/RRESP 2bit |
| clock | 기존 wrapper는 S00, M00 인스턴스, 코어에 `s00_axi_aclk`를 연결. 외부 `m00_axi_aclk` 포트가 별도 clock 사용을 뜻하지 않음 |
| reset | active-low, 비동기 assert / **외부에서 동기 release 보장 필요**. 기존 wrapper에 release synchronizer가 있다고 가정하지 않음 |
| startup guard | `channel_enable_reg`는 release 직후 수락을 한 clock 막는 장치. **reset synchronizer가 아님** |
| reset 중 동작 | AWREADY/WREADY/ARREADY/BVALID/RVALID=0, RW 저장값·펄스 초기화. 보류 중인 요청/응답도 폐기됨 |
| reset 해제 후 | 첫 정상 상승 에지 뒤 READY 활성. 그 다음 상승 에지부터 handshake 가능 |
| 주소 영역 | 구현 CSR 범위는 32 B(`0x00~0x1F`). 실제 base와 BD 할당 크기·상위 주소 decode는 민영이 설정. 5bit 밖의 주소 구분을 이 모듈이 해주지는 않음 |
| PROT | AWPROT/ARPROT는 포트로 받지만 사용하지 않음 |
| interrupt | 이 CSR 모듈에 IRQ 출력이나 HLS interrupt/auto-restart register는 없음. 현재 PS는 STATUS polling 사용 |
| 연결 후 확인 | 합성·주소 매핑·clock/reset 연결·PS의 32bit MMIO 순서·bus 오류 노출을 별도 통합 단계에서 확인 |

D07의 reset 동기 release 생성 위치는 아직 미결이다. BD의 공통 reset 출력에서 보장하는 안이 제안되어 있지만, 이 문서로 담당 구현 위치를 새로 확정하지 않는다.

## 8. PS가 따라야 할 실행 흐름

### 공통 접근 규칙

- CSR은 **32bit MMIO**로 접근한다. 정상 쓰기는 전체 word(`WSTRB=0xF`)를 사용한다. byte/halfword 접근 및 기존 `reg_write_u64`를 재사용하지 않는다.
- COMMAND/주소/START/CLEAR 쓰기는 모두 busy=0을 확인한 뒤 수행한다. PS는 START와 CLEAR를 한 쓰기에 섞지 않는다.
- INPUT/WEIGHT 주소 값은 8 B, OUTPUT 주소 값은 32 B 정렬한다. 이 CSR은 **정렬만 검사**하며 DDR 할당 범위·용량·캐시 일관성을 확인하지 않는다.
- 모든 설정 쓰기를 완료한 뒤 START를 쓴다. **START 쓰기 완료 뒤** STATUS 읽기를 발행한다. 사용 플랫폼의 MMIO 완료·순서 보장 방법은 PS 구현에서 적용한다. 읽기/쓰기 채널이 독립이므로 미리 발행한 읽기는 이전 상태를 반환할 수 있다.
- 출력 scale은 cfg_ok=1을 확인한 뒤 `0x18`에서 읽는다. float32의 **비트 재해석**을 사용하며, uint32 값을 float로 수치 변환하는 것이 아니다.

### LOAD와 INFER

1. **idle 확인:** STATUS.busy=0을 확인한다. 오류 복구 시 표시를 지울 필요가 있으면 `CONTROL=2`를 쓰고 완료한다.
2. **LOAD 준비:** 유효 blob을 DDR에 준비하고 WEIGHT_ADDR, COMMAND=1을 설정한 뒤 `CONTROL=1`로 시작한다. DDR 가시성과 MMIO 순서를 지킨다.
3. **LOAD 결과:** 아래 종료 조건으로 polling한다. 성공과 cfg_ok=1을 확인한 뒤 scale을 읽는다. cfg_ok=0 상태에서 INFER를 요청하면 Top의 NO_CFG 대상이다.
4. **INFER 준비:** 전처리·양자화한 입력을 준비하고 INPUT_ADDR/WEIGHT_ADDR/OUTPUT_ADDR 및 COMMAND=0을 설정한다. **권장 흐름은 직전 LOAD에 사용한 WEIGHT_ADDR를 유지하는 것**이다. 주소 변경 이후 동작과 하드웨어 보호는 D06에서 별도로 확정한다. 현재 명세의 데이터 크기는 입력 **11,520 B**, 출력 **signed INT8 24 B**다.
5. **INFER 시작·대기:** `CONTROL=1` 쓰기 완료 뒤 STATUS를 polling한다. 짧은 busy pulse를 반드시 포착하는 별도 대기 조건을 두지 않는다.
6. **성공 후 결과:** 플랫폼에 맞는 DDR/캐시 처리를 한 뒤 signed INT8 24개에 float32 scale을 곱해 후처리 입력으로 복원한다. 이 출력 경로 자체의 통합 검증은 아직 수행하지 않았다.

Polling 판정:

```text
완료 판단: busy == 0 && (done == 1 || error == 1)
성공:      busy == 0 && done == 1 && error == 0
실패:      busy == 0 && error == 1   -> error_code 확인
대기:      busy == 1 또는 (busy == 0 && done == 0 && error == 0)
```

timeout을 둔다. error가 먼저 나타나도 busy=1이면 다음 START를 발행하지 않는다. timeout 또는 메모리 오류 뒤의 시스템 복구 방법은 D08과 플랫폼 통합에서 확정해야 하며, CLEAR 자체를 실행 중단이나 복구 명령으로 취급하지 않는다.

### 참고 HLS PS와 달라지는 접점

| 항목 | 참고 흐름 | 이번 CSR 계약 |
| --- | --- | --- |
| 완료 확인 | AP_CTRL `0x00`, done clear-on-read | STATUS `0x04`, 읽기 부작용 없음 |
| COMMAND | `0x28`, nonzero를 LOAD로 취급하는 흐름 | `0x08`, 정확히 0=INFER / 1=LOAD |
| 주소 설정 | INPUT `0x10/14`, WEIGHT `0x1C/20`, OUTPUT `0x30/34`의 64bit 쓰기 | INPUT `0x0C`, WEIGHT `0x10`, OUTPUT `0x14`의 32bit 쓰기 |
| 출력 처리 | float32 ×24 = 96 B | signed INT8 ×24 = 24 B + `0x18` scale |
| 초기 설정 | 자동 load에 의존 가능한 기존 흐름 | LOAD 성공/cfg_ok 확인 후 INFER |

수집·전처리·window 구성·후처리 흐름은 최대한 유지한다. 메모리 할당과 캐시 처리, bitstream/XSA의 주소 정보, device tree/DDR 예약 영역의 일치는 민영의 보드 환경에서 확인한다.

## 9. 확인한 결과와 검수 범위

실행 환경: **Vivado xsim 2020.2**. RTL은 `xvlog`, TB는 `xvlog -sv`로 컴파일했다. 각 TB에는 FAIL 시 `$fatal`과 watchdog이 있다.

| TB | 실제 확인 결과 |
| --- | --- |
| write | AW=5, W=5, commit=5, B=5. 동시/AW 우선/W 우선, B stall 및 응답 중 다음 요청 차단 |
| regs | write=49, commit=49, B=49. 4개 저장소·단일/조합 strobe·0 strobe·비선택 X byte·주소 별칭·reset |
| read | AR=50, R=50, write commit/B=7. STATUS 24개 조합·scale SLVERR·snapshot·양방향 stall 독립 |
| ctrl N=1 | commit/B=52, START=6, CLEAR=4. 가장 빠른 재START는 이전 실행 종료 후 OKAY |
| ctrl N=2 | commit/B=52, START=5, CLEAR=4. 가장 빠른 재START는 마지막 busy 에지에서 SLVERR |
| ctrl N=8 | commit/B=58, START=7, CLEAR=5. busy 초기/중간/마지막 에지 START 모두 거부 |

최종 ctrl 출력: `PASS: S00-05 ALL CONTROL CHECKS PASSED (15a/15b/15c included)`.

검증 기록 전문에는 이전 write/regs/read 실행 및 최종 ctrl 실행의 명령·출력이 있다. 실행 당시 원문을 보존했으므로 그 안의 “Claude 검수 대기”는 당시 상태이며, 현재 검수 상태는 이 문서 1절과 최신 공통 문서를 따른다. 상위 문서에 기록된 Claude shadow 모델/양채널 stress 결과와는 구분한다. 여기 표는 실제 보존된 네 TB 실행 결과다.

인계 전 재검토 범위는 RTL 전체와 확정 계약의 대조, wrapper 포트 연결, 지원 폭, reset, 조합 기본값/복구, B/R stall 고정, commit/AR snapshot 시점이다. 정적 검토에서는 조합 feedback loop나 기본값 누락을 찾지 못했으며, **합성 결과를 대신하는 판정은 아니다**. 인계 RTL 해시는 이전 통과본과 동일하다.

## 10. 남은 통합 결정과 다음 작업

| 항목 | 상태와 담당 접점 |
| --- | --- |
| CSR 합성·타이밍 | 미실행. 다음 별도 단계에서 래치·조합 루프·자원·목표 clock 확인 |
| D06 모델 일관성 | WEIGHT_ADDR 변경 후 다시 LOAD하는 안은 권장 상태. loaded-base 하드웨어 보호와 최종 PS 제약은 한림/민영 결정 필요 |
| D07 reset | 동기 release 보장 위치를 한림/민영이 BD 통합 전 결정 |
| D08 오류 복구 | drain·cfg_ok 무효화·FIFO 복구·오류 우선순위를 한림/민영/지원이 Top/Loader 구현 전에 결정 |
| D09 공유 포트 | Param/LUT 공유 포트 선택을 한림/동우/지원이 연결 전 결정 |
| D10 보드·clock·출력 | 최종 보드/clock 등 미결. 변경 확정 전 현재 24개 INT8 출력 기준 유지 |
| 실제 Top/Loader/M00 연결 | 위 신호·시점 계약을 만족하도록 각 담당이 구현·통합. 이 CSR 전달만으로 동작 가능한 전체 IP가 되지는 않음 |

다음 소단계 후보는 **CSR 합성 1회 확인 → Loader 소단계 분할**이다. 이 인계 문서 작성으로 후속 구현을 착수한 것은 아니다.

## 전달할 때 붙일 짧은 설명

> S00_AXI CSR 기능 구현과 TB 검증을 마친 소스입니다. DATA_WIDTH=32 / ADDR_WIDTH=5로 사용하고, 첨부 문서의 레지스터 맵과 PS 순서에 맞춰 패키징·BD·PS 접점을 연결해 주세요. 주요 변경은 32bit CSR 접근, STATUS polling, 명시적 LOAD, INT8 24 B 출력입니다. reset 동기 release는 외부에서 보장해야 하고, busy/done/error 및 START 처리 시점은 실제 Top과 연결할 때 계약을 맞춰야 합니다. 합성·보드 통합은 아직 미실행이며 D06~D10은 별도 결정 사항입니다.
