# Vivado 하드웨어 통합 자료

Zybo Z7-20 (`xc7z020clg400-1`) / Vivado 2020.2 환경에서 **PS와 PL의 실제 연결 구조 및 FPGA IP 통합 산출물**을 관리합니다. 기존 Pose CNN 하드웨어와 **CNN + Location Ridge** 통합 하드웨어를 별도 버전으로 보존합니다.

## 이 폴더의 구현 내용

| 구성 | 기능 |
|---|---|
| **Pose CNN IP** | RX5 INT8 관절 추론: DDR/AXI 연산, 12관절 24개 결과 |
| **병렬 Pose CNN IP** | RX별 Encoder 병렬화를 반영한 CNN 패키지 |
| **Location Ridge IP** | 955개 위치 특징의 고정소수점 선형 분류 연산용 AXI4-Lite IP |
| **XSA 산출물** | 기존 CNN과 CNN+Ridge 버전의 Vivado 하드웨어 Export 파일 |

CNN 원본 RTL은 [`pl/cnn/`](../pl/cnn/README.md), Ridge 원본 RTL과 테스트는 [`pl/localization/`](../pl/localization/README.md)에 있고, 이 폴더는 **Vivado IP 패키징과 하드웨어 통합 경로**입니다. Ridge IP가 빌드되어 있어도 **현재 기본 `ps/` + `pc/backend/`의 위치 추론은 Zynq PS의 C Ridge**가 수행합니다. FPGA Ridge 가속은 별도 하드웨어 실험이며, 실보드에서 PS 드라이버로 적용되었다는 뜻이 아닙니다. [PS 기본 경로](../ps/README.md)와 [이전 개발판](../ps_location/README.md)을 구분하세요.

## 1. 파일 구성

| 경로 | 역할 | 비고 |
|---|---|---|
| `pose_cnn_1.1/` | 기존 CNN IP 패키지 | 이전 버전 보존 |
| `pose_cnn_par_1.2/` | 병렬 CNN IP 패키지 | 통합 설계에서 사용하는 CNN (`user.org:user:pose_cnn_par:1.2`) |
| `ridge_axi_1.0/` | 단일 RTL Ridge AXI4-Lite IP 패키지 | 이전 v1.0 보존 (`component.xml`, `src/`, `xgui/`) |
| `ridge_axi_1.1/` | **7개 모듈 Ridge AXI IP 패키지** | 현재 RTL 원본 [`pl/localization/`](../pl/localization/README.md)와 동기화 대상 |
| `design_1_wrapper.xsa` | 기존 CNN 하드웨어 내보내기 | 이전 산출물 보존 |
| `design_1_wrapper_parallel.xsa` | 기존 병렬 CNN 하드웨어 내보내기 | Ridge 통합 이전 버전 보존 |
| `cnn_ridge_design_1_wrapper.xsa` | CNN + Ridge 통합 XSA | 기존 10/13 구현·해시 기록 기준; `-include_bit` 확인 기록 |
| `design_1_wrapper_ridge_sep.xsa` | 별도 Ridge 통합 관련 XSA | **파일 존재만 확인**; 담긴 RTL 버전/bitstream/보드 실행 여부는 검증 필요 |

> `ridge_axi_1.0/`과 `ridge_axi_1.1/` IP 패키지, 관련 XSA는 현재 저장소에 포함되어 있습니다. **XSA 생성/합성 통과와 실제 보드 적용·동작 검증은 별개**이며, 기존 CNN XSA는 보존합니다.

원본 CNN RTL은 [`../pl/cnn/rtl/`](../pl/cnn/rtl/)에서 관리하며, Ridge 원본 RTL과 테스트벤치는 각각 `../pl/localization/rtl/`, `../pl/localization/testbench/`에 별도로 관리한다. Vivado IP 패키지의 `src/`는 해당 원본 RTL의 패키징용 복사본이다. 원본 수정 시 IP 패키지 소스도 함께 갱신한다. 기존 CNN v1.1 패키지의 `requant_core.v`, `requant_stage.v`, `Pool.v`는 원본과 바이트 일치를 확인했던 파일이며, 다른 복사본까지 동일함을 뜻하지는 않는다. 기존 XSA의 최신 CNN 수정 반영 여부도 별도로 확인해야 한다.

아래 2~4절의 구조·CSR·성능 표는 **2026-10-13 당시 `ridge_axi_1.0`/`cnn_ridge_design_1_wrapper.xsa` 기록**입니다. 최신 `ridge_axi_1.1`의 7모듈 RTL/별도 타이밍 결과는 [PL Ridge README](../pl/localization/README.md)를 우선 참조합니다. 기존 보고서의 수치를 v1.1/XSA 전부에 그대로 적용하지 마세요.

## 2. CNN + Ridge 통합 구조

```text
                    Zynq-7000 PS
                 M_AXI_GP0 (100 MHz)
                         |
                    AXI Interconnect
                      /          \
          0x43C00000                0x43C10000
        Pose CNN IP                Ridge AXI IP
      (pose_cnn_par 1.2)         (ridge_axi 1.0)
             |
        M_AXI / HP0
             |
          PS DDR
```

- 기존 **CNN RX5 구조, CNN CSR 주소, HP0 경유 DDR 데이터 경로**를 유지한다.
- Ridge는 GP0에 연결된 **독립적인 AXI4-Lite Slave IP**이며, 자체 Weight/Feature RAM 및 MAC 연산부를 가진다.
- Ridge 모델 가중치·Bias와 입력 특징은 PS가 AXI4-Lite 레지스터를 통해 전송한다. **Ridge는 DDR DMA를 사용하지 않는다.**
- CNN과 Ridge는 `FCLK_CLK0 = 100 MHz`를 사용한다.

| IP | AXI4-Lite Base | Address range | 연결 |
|---|---|---|---|
| Pose CNN (`pose_cnn_par_0`) | `0x43C00000` | 64 KiB | PS GP0, 기존 M_AXI–HP0/DDR 유지 |
| Ridge (`ridge_axi_0`) | `0x43C10000` | 64 KiB | PS GP0, 100 MHz / peripheral reset |

CNN의 DDR 주소(`0x3F000000` 가중치, `0x3F100000` 입력, `0x3F200000` 출력)와 16 MiB 예약 영역은 기존 PS 계약을 유지한다. 관련 설정은 [`../ps_location/ps/`](../ps_location/ps/) 및 `petalinux/system-user.dtsi`를 참고한다.

## 3. Ridge IP 하드웨어 계약

| 항목 | 값 |
|---|---|
| RTL Top | `ridge_axi_v1` |
| VLNV | `user.org:user:ridge_axi:1.0` |
| 입력 특징 | RX5 × CSI magnitude/RSSI, **955개** |
| 출력 클래스 | **11개** (`p01`~`p10`, `empty`) |
| 특징 형식 | signed INT16, **Q7**; 2개를 32-bit 워드에 패킹 |
| 가중치 형식 | signed INT16; 2개를 32-bit 워드에 패킹 |
| Bias / Score | signed 64-bit |
| 모델 저장량 | 가중치 **5,253워드** + Bias **11개** |
| 추론 입력량 | 특징 **478워드** |
| 계산 방식 | 순차 MAC, 동기식 RAM read → 곱셈 레지스터 → 누산 → 클래스별 평가 |

주요 레지스터 오프셋 (`0x43C10000` 기준):

| Offset | Register | 용도 |
|---|---|---|
| `0x00` | CONTROL | `1` START, `2` MODEL_COMMIT, `4` CLEAR (`각각 단독 기록`) |
| `0x04` | STATUS | bit0 BUSY, bit1 DONE, bit2 ERROR, bit3 MODEL_VALID |
| `0x08` | ERR | 오류 코드 (`0` 정상, `1` 모델 미완성, `2` 입력 미완성 등) |
| `0x0C`, `0x10` | WPTR, WDATA | 가중치 전송 |
| `0x14`, `0x18`, `0x1C` | BPTR, BLO, BHI | Bias 전송 (하위 32비트 → 상위 32비트) |
| `0x20`, `0x24` | XPTR, XDATA | 특징 전송 |
| `0x28` | RESULT | 추론 완료 후 estimator index(하위 4비트), wire class code(다음 4비트) |
| `0x2C`, `0x30`, `0x34` | SPTR, SLO, SHI | 클래스별 64-bit 점수 읽기 |
| `0x38` | ID | **`0x52444731`** (`RDG1`) |
| `0x3C` | CYCLES | MAC 연산 클록 수 |
| `0x40`, `0x44`, `0x48` | WCOUNT, BCOUNT, XCOUNT | 입력 완료 수 검사 |

**유의 사항:** PL 내부 가중치 RAM은 Bitstream 로드 직후 유효 모델이 아니다. PS가 모델을 로드하고 `MODEL_COMMIT`을 실행해야 추론이 가능하다. 기존 `WLOC v1`은 부동소수점 StandardScaler/계수를 포함하므로, PS 드라이버에서 Scaler를 계수에 결합한 뒤 고정소수점으로 변환한다. 클래스의 *estimator 인덱스*와 TCP의 *wire 코드*는 순서가 다르며, RTL·PS의 매핑을 동일하게 유지해야 한다.

## 4. 검증 현황 (2026-10-13)

| 검증 항목 | 결과 | 범위 |
|---|---|---|
| Vivado Synthesis | **PASS** | CNN + Ridge 포함, black box 0 |
| Vivado Implementation / Timing | **PASS** | Setup WNS **+0.507 ns**, Hold WHS **+0.031 ns**, 100 MHz |
| Bitstream 생성 | **PASS** | `cnn_ridge_design_1_wrapper.bit` |
| XSA Export | **PASS** | `cnn_ridge_design_1_wrapper.xsa`, `-include_bit` |
| XSA 내부 Bitstream 일치 | **PASS** | 별도 `.bit`와 SHA-256 동일 |
| Ridge 최종 RTL XSim | **40/40 PASS** | 고정소수점 Golden, AXI 오류·Reset 등 시험; 테스트 데이터 기준 |
| Ridge 실제 보드 MMIO/연산 | **미검증** | Linux에서 Bitstream 로드 후 확인 필요 |
| CNN + Ridge 동시 실보드 동작 | **미검증** | 기존 CNN 회귀 시험 및 PS 통합 필요 |
| 최신 데이터 위치 정확도 | **미검증** | 40개 정수 Golden PASS를 위치 분류 정확도로 해석하면 안 됨 |

최종 산출물 기록: 별도 Bitstream SHA-256 `50513984a3b315ded988d897ad7ac353295fbebbb9676d1ab903e1a3460b1aee`, XSA SHA-256 `bd46362764b2849b1a49e1a35b16b811d5a8b01e9e5462ea76a7ef0e80b89134`. 현재 제공된 최종 파일 기준으로 기록한 값이므로 파일이 갱신되면 다시 산출한다.

Ridge RTL 기준 한 번의 추론 계산은 **31,526클록**, 100 MHz에서 **315.26 μs**에 해당한다. 이는 **FPGA 내부 계산 시간만**이며, PS→PL AXI 전송과 Linux 소프트웨어 처리 지연은 포함하지 않는다.

## 5. 보드 적용 및 PS 연동

1. 기존 SD카드의 `BOOT.BIN`, `image.ub` 및 CNN 가중치 파일을 먼저 백업한다.
2. **단기 PL 시험:** 기존 Linux에서 FPGA 재설정 인터페이스(`/dev/xdevcfg` 또는 FPGA Manager) 지원 여부를 확인하고, CNN 앱을 정지한 뒤 새 Bitstream을 로드한다. 지원되는 입력 형식·절차는 실제 커널 설정에 맞춰 확인한다.
3. 새 IP 로딩 후 `devmem 0x43C10038 32`가 `0x52444731`을 반환하는지 확인한다. 이는 **Ridge IP 존재 및 AXI 읽기 확인**이지 MAC 추론 성공 판정은 아니다.
4. 별도 Ridge 보드 테스트로 가중치·특징 로딩, `MODEL_COMMIT`, `START`, `DONE`, 11개 Score와 Class Code를 Golden과 비교한다.
5. 기본 [`../ps/`](../ps/README.md)의 `loc_ridge.c`는 현재 **CPU 기반 Ridge 추론**이므로, 기존 955-feature/윈도우/TCP 경로를 유지하면서 FPGA 드라이버로 연산 부분을 교체한다. CNN 기존 동작도 재시험한다.
6. **최종 배포:** 새 Bitstream을 포함한 부팅 이미지(`BOOT.BIN`)를 준비하고, 필요한 PS 애플리케이션·Device Tree 변경을 PetaLinux 빌드 결과에 반영한다. **XSA를 SD카드에 복사하는 것만으로 PL이 갱신되지는 않는다.**

현재 PetaLinux 통합·자동 실행 절차는 [`../ps/petalinux/AUTOSTART.md`](../ps/petalinux/AUTOSTART.md) 참고. 기존 예약 DDR·USB Host 설정, 자동 실행 서비스, `/mnt/wise-boot/weights_5rx.bin` 가중치 경로를 유지할 것.

## 6. 업로드·버전 관리 원칙

- 기존 `design_1_wrapper.xsa`, `design_1_wrapper_parallel.xsa`, `pose_cnn_1.1/`, `pose_cnn_par_1.2/`는 **삭제하거나 덮어쓰지 않는다.**
- 통합 하드웨어 XSA는 `cnn_ridge_design_1_wrapper.xsa` 이름으로 **별도 등록**한다. 대화에서 다운로드한 `cnn_ridge_design_1_wrapper(1).xsa` 같은 중복 다운로드 이름은 GitHub 업로드 시 원래 이름으로 바꾼다.
- Ridge v1.1 패키지는 `component.xml`만이 아니라 **7개 `src/*.v` 모듈과 `xgui/*.tcl`을 함께** 관리한다. v1.0 단일 파일은 이전 비교용으로 보존한다.
- 최종 Ridge RTL·테스트벤치는 `pl/localization/`에 관리하고, 패키지의 RTL 복사본과 정합성을 확인한다.
- `.gitignore`에 `*.bit`가 있으므로 별도 `.bit`는 기본적으로 추적하지 않는다. **최종 XSA에는 `.bit`가 포함**되어 있다.
- 합성/구현 로그·보고서는 변경의 근거로 보존할 수 있지만, **Vivado 빌드 성공을 실보드 검증 완료로 표기하지 않는다.**
- Vivado 편집 가능한 Block Design 재현을 위해서는 `.xsa` 외에도 원본 Vivado 프로젝트 또는 재생성 가능한 Tcl/BD를 별도로 보관하는 것이 좋다.

CNN 및 Ridge IP의 현재 구성·확인 범위는 [PL CNN](../pl/cnn/README.md), [PL Ridge](../pl/localization/README.md), [PS 실행](../ps/README.md)을 각각 참고한다.
