# PL Localization — Ridge AXI Accelerator (Modular  v1.1)

Wi-Fi CSI 기반 위치 분류를 **Zynq PL의 Ridge 선형 분류기**로 실행하기 위한 RTL 원본 및 검증 파일이다. 이 디렉터리의 기준 버전은 **7개 모듈로 분리한 Ridge AXI IP v1.1**이다.

> **검증 범위:** XSim Golden 테스트, Vivado 합성·배치배선, 100 MHz 타이밍 검증까지 완료했다. **실제 Zybo Z7-20 보드의 MMIO·모델 로드·추론 및 CNN 동시 동작은 아직 검증하지 않았다.** IP가 빌드되었다는 사실을 실시간 서비스 적용 완료로 해석하면 안 된다.

## 1. 시스템 구성

- **대상 환경:** Zybo Z7-20 (`xc7z020clg400-1`), Vivado 2020.2, PL 100 MHz
- **인터페이스:** PS `M_AXI_GP0` → AXI Interconnect → Ridge **AXI4-Lite Slave** (32-bit 데이터)
- **Ridge 주소:** `0x43C10000`, 주소 영역 64 KiB (`0x10000`)
- **CNN 주소:** `0x43C00000` (별도 IP, 기존 DDR/HP0 경로 유지)
- **입력:** RX 5개에서 계산한 CSI magnitude/RSSI 기반 **955개 특징**
- **출력:** **11개 클래스**(`p01`~`p10`, `empty`)의 점수와 최종 분류 결과
- **연산:** PC/PS 측에서 학습한 Ridge 계수와 입력을 고정소수점으로 변환해 전송하고, PL에서 순차 MAC 및 최대 점수 비교를 수행한다. Ridge IP에 DDR DMA 경로는 없다.

```text
ESP32 CSI → PS: 특징 추출(955D)·고정소수점 변환
                      │
                 AXI4-Lite (GP0)
                      │
                ridge_axi_v1
           ┌──────────┼───────────┐
      ridge_axi_slave  ridge_ctrl  ├── ridge_model_mem (Weight/Bias)
           │                       ├── ridge_feature_mem (Input)
           │                       ├── ridge_mac (MAC)
           └───────────────────────└── ridge_result (Scores/Argmax)
                      │
                AXI4-Lite 결과 읽기
                      │
                      PS
```

CNN과 Ridge는 **독립적인 IP**이다. Ridge 추론이 CNN 하드웨어 추론을 대체하거나 CNN AXI/DDR 경로를 변경하는 구조가 아니다.

## 2. 디렉터리 구조

```text
pl/localization/
├── README.md
├── rtl/
│   ├── ridge_axi_v1.v         # Top: 모듈 연결, AXI 포트
│   ├── ridge_axi_slave.v      # AXI4-Lite Slave, CSR, 데이터 전송
│   ├── ridge_ctrl.v           # 연산 제어 FSM
│   ├── ridge_model_mem.v      # Weight / Bias 저장
│   ├── ridge_feature_mem.v    # 입력 Feature 저장
│   ├── ridge_mac.v            # 고정소수점 곱셈·누산
│   └── ridge_result.v         # 클래스별 Score 및 Argmax
└── testbench/
    ├── tb_ridge_axi_v1.v
    └── generated/
        ├── biases.mem
        ├── features.mem
        ├── raw_scores.mem
        ├── weights.mem
        └── winner_code.mem
```

Vivado에서 재사용할 **패키징 IP**는 [`../../integration/ridge_axi_1.1/`](../../integration/ridge_axi_1.1/)에 별도로 보관한다 (`component.xml`, `src/`, `xgui/`). **이 디렉터리의 RTL 7개와 IP 패키지 `src/`의 동일 이름 파일은 내용이 일치해야 한다.** 이전 단일 파일 버전은 [`../../integration/ridge_axi_1.0/`](../../integration/ridge_axi_1.0/)에 보존한다.

## 3. 데이터 및 모델 계약

| 항목 | 규격 |
|---|---|
| 특징 수 | 955 |
| 클래스 수 | 11 |
| 특징 입력 | signed INT16, Q7; AXI 32-bit 워드당 2개 패킹 |
| 가중치 | signed INT16; AXI 32-bit 워드당 2개 패킹 |
| Bias / Score | signed 64-bit |
| 가중치 전송량 | 5,253 × 32-bit 워드 |
| Bias 전송량 | 11 × 64-bit |
| 특징 전송량 | 478 × 32-bit 워드 |
| 모델 사용 조건 | Weight/Bias 전송 및 `MODEL_COMMIT` 후 `MODEL_VALID` 필요 |

학습된 모델의 **StandardScaler와 Ridge 계수 결합·양자화는 소프트웨어 측에서 수행**한다. IP는 이미 변환된 Weight/Bias와 특징을 입력받아 계산한다. *Estimator class index*와 외부에 전송하는 *wire class code*는 별도 매핑이므로 드라이버에서 혼동하지 않아야 한다.

## 4. AXI4-Lite CSR 맵

Base Address: **`0x43C10000`**. 오프셋은 아래 기준이다.

| Offset | 이름 | 기능 |
|---|---|---|
| `0x00` | `CONTROL` | `1`: START, `2`: MODEL_COMMIT, `4`: CLEAR (각각 단독 기록) |
| `0x04` | `STATUS` | bit0 BUSY, bit1 DONE, bit2 ERROR, bit3 MODEL_VALID |
| `0x08` | `ERR` | 오류 상태 코드 |
| `0x0C` / `0x10` | `WPTR` / `WDATA` | 가중치 전송 포인터 / 데이터 |
| `0x14` / `0x18` / `0x1C` | `BPTR` / `BLO` / `BHI` | Bias 포인터 / 하위 32비트 / 상위 32비트 |
| `0x20` / `0x24` | `XPTR` / `XDATA` | Feature 전송 포인터 / 데이터 |
| `0x28` | `RESULT` | 최종 estimator index 및 wire class code |
| `0x2C` / `0x30` / `0x34` | `SPTR` / `SLO` / `SHI` | 클래스별 Score 포인터 / 하위 32비트 / 상위 32비트 |
| `0x38` | `CORE_ID` | `0x52444731` (`RDG1`) |
| `0x3C` | `CYCLES` | 추론 연산 사이클 수 |
| `0x40` / `0x44` / `0x48` | `WCOUNT` / `BCOUNT` / `XCOUNT` | 가중치 / Bias / Feature 로드 수 |

> 실제 보드에서 가장 먼저 `0x43C10038`을 읽어 `0x52444731`인지 확인한다. 이는 AXI 통신 확인일 뿐 **모델 로드와 추론의 정상 동작을 증명하지는 않는다.**

## 5. 검증 결과 (2026-10-13)

### 기능 시뮬레이션

- Vivado 2020.2 XSim에서 **Golden 40/40 PASS**.
- 고정소수점 클래스별 점수·분류 결과, AXI4-Lite 오류 응답, 모델 유효성·초기화/Reset 관련 시나리오를 확인했다.
- 이 결과는 **제공된 테스트 벡터 기준의 RTL 기능 검증**이다. 실제 CSI 데이터 전체에 대한 위치 정확도나 실보드 검증 결과는 아니다.

### FPGA 합성·Implementation (Routed Design)

| 사용량 | Ridge v1.1 | CNN+Ridge 통합 SoC |
|---|---:|---:|
| LUT | 948 | 36,927 |
| FF | 1,261 | 27,508 |
| RAMB36 | 8 | 68 |
| RAMB18 | 1 | 8 |
| BRAM36 환산 | 8.5 | 72 |
| DSP48 | 1 | 40 |

| 타이밍 항목 | 결과 |
|---|---:|
| 클록 | 100 MHz (10.000 ns) |
| WNS (Setup) | **+0.494 ns** |
| WHS (Hold) | **+0.027 ns** |
| TNS / THS | **0 / 0 ns** |
| Setup/Hold 실패 경로 | **0개** |

Vivado 보고서에서 `All user specified timing constraints are met`를 확인했다. 보고서의 전체 최악 Setup 경로는 CNN 내부 `u_pool`에 있으며, 위 WNS는 **Ridge 단독 성능이 아니라 통합 SoC의 최악 경로 수치**이다.

**7개 모듈 합성 확인:** `ridge_axi_v1` 및 `u_axi`, `u_ctrl`, `u_feature`, `u_mac`, `u_model`, `u_result` 계층이 Implemented Design의 Hierarchical Utilization에 나타났다. 단, **전체 Warning/Critical Warning 검토는 별도의 synth_1/impl_1 로그 점검이 필요**하다.

## 6. 재현 및 변경 관리

1. RTL 수정 시 `pl/localization/rtl/`을 기준으로 수정하고 XSim 회귀 테스트를 수행한다.
2. 검증한 RTL을 `integration/ridge_axi_1.1/src/` 패키지 소스에도 동일하게 반영한다. `component.xml`에 기록된 파일 상대경로를 임의로 바꾸지 않는다.
3. Vivado의 IP Catalog에 CNN `pose_cnn_par:1.2`와 Ridge `ridge_axi:1.1` **두 IP 저장소를 함께 등록**한다.
4. Block Design에서 CNN 주소 `0x43C00000`, Ridge 주소 `0x43C10000` (각 64 KiB), PS GP0, 100 MHz 클록 및 Active-Low Reset을 확인한다.
5. `Validate Design → Synthesis → Implementation → Timing → Generate Bitstream`을 수행한다.
6. PS 연동용 최종 산출물은 **Bitstream 포함 XSA**로 Export한다. `.xsa`만으로 Vivado Block Design을 편집 가능하게 복원할 수는 없으므로 재생성용 BD Tcl도 별도 관리하는 편이 좋다.

`.gitignore`에 의해 Vivado 자동 생성 프로젝트·캐시·로그·Bitstream 파일은 기본적으로 추적되지 않는다. `integration/`의 패키지와 XSA 및 이 폴더의 RTL/TB/Golden을 기준 소스로 관리한다.

## 7. 아직 확인할 사항

- Zybo Z7-20 실보드에서 Ridge `CORE_ID` 및 AXI 읽기/쓰기 검증
- 실제 Weight/Bias/Feature 로드 → `MODEL_COMMIT` → `START` → `DONE` → Score/Argmax 대조
- CNN과 Ridge 동시 실행 시 기능·메모리·타이밍 영향 및 PS 드라이버 연동
- 실제 CSI 입력에 대한 인식 정확도와 종단 간 지연 측정
- 최종 XSA의 **v1.1 반영 및 Bitstream 포함 여부** 확인

관련 문서: [`integration/README.md`](../../integration/README.md), [`ps_location/README.md`](../../ps_location/README.md).
