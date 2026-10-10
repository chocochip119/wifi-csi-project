# FC 전용 테스트벤치

저장소 루트에서 Python 3와 Icarus Verilog(`iverilog`, `vvp`)로 실행합니다. 추가 Python 패키지는 필요 없습니다.

```bash
python pl/cnn/testbench/FC/run_regression.py
```

각 TB는 기대값을 자동 비교하고 데이터 불일치, valid/tag 지연, 누락, 초과 출력, timeout을 `$fatal(1,...)`로 실패 처리합니다. Python runner도 실패한 simulator를 비정상 exit로 전달합니다. 생성한 hex와 실행 파일은 임시 폴더에서 제거합니다.

| TB | 검증 범위 |
|---|---|
| `tb_fc_fifo.v` | 깊이 3/8/512, FWFT 순서, full/empty, 동시 push/pop, full 쓰기/empty 읽기 거부, 포인터 순환, 리셋 |
| `tb_fc_mac.v` | signed INT8 경계, 8-lane 내적/누산, first/last, 첫 beat 태그 유지, 640그룹 누산, 빈 cycle, 4단 파이프라인, 리셋 flush; 256출력 |
| `tb_fc_requant.v` | 독립 Python 정수 oracle 12,000개, bias/multiplier INT32 경계, shift INT32_MIN~MAX, 반올림/포화, 동기 파라미터 RAM, 태그/7단 지연, 리셋 flush |
| `tb_fc_gelu.v` | 4개 테이블 × signed INT8 256값, offset-binary 주소, 동기 LUT 읽기, valid/tag, 빈 cycle |
| `tb_fc_memories.v` | Hidden RAM 양쪽 bank·byte lane, Pose 24주소, 동기 읽기와 read-first 동작, RAM 내용 리셋 후 유지, Flatten 640주소 연결 |
| `tb_fc_controller.v` | FC1/2/3 주소·태그·first/last, FIFO empty stall, 실행 중 start/selector 변경 무시, selector=3 무시, 저장 완료까지 대기, done 1cycle |
| `tb_fc_top.v` | RX3/RX5의 FC1→FC2→FC3, 원래 크기 128→128→24, 동기 외부 RAM, FIFO full/empty, 실행 중 리셋·재시작, reset 없이 2회 추론, 모든 MAC·저장값·Pose 읽기·done 비교 |

`gen_vectors.py`는 고정 seed로 fixture를 재생성합니다. 계산은 Python 정수 내적과 몫/나머지를 이용한 독립 반올림이며 RTL 중간 레지스터를 복사해 기대값을 만들지 않습니다. Top의 GELU LUT는 테이블 선택·주소·타이밍을 식별하기 위한 합성 fixture입니다. 학습 모델의 GELU 근사 정확도나 실제 CSI 자세 정확도를 검증하는 데이터는 아닙니다.

## 실행 옵션

```bash
# VCD: 10개 실행 결과를 따로 보관
python pl/cnn/testbench/FC/run_regression.py --waves build/fc_waves

# 패키징된 IP의 FC 복사본에도 같은 테스트 적용
python pl/cnn/testbench/FC/run_regression.py --rtl-dir integration/pose_cnn_1.1/src
python pl/cnn/testbench/FC/run_regression.py --rtl-dir integration/pose_cnn_par_1.2/src

# PATH 밖의 Icarus 설치
python pl/cnn/testbench/FC/run_regression.py --iverilog /path/to/iverilog --vvp /path/to/vvp --ivl-base /path/to/ivl
```

`--waves`는 대용량 파일을 만들 수 있으므로 생성물은 git에 넣지 않습니다. `build/`는 저장소의 ignore 대상입니다. RX3 Top은 FIFO depth=8, RX5 Top은 실제 기본 depth=512로 실행합니다. Top은 FC1 시작 전 FIFO를 가득 채운 뒤 주기적으로 공급을 멈춰 full과 empty를 모두 확인합니다.

## Vivado

Python이 PATH에 있는 Vivado shell에서 아래 명령으로 개별 TB를 실행할 수 있습니다.

```bash
vivado -mode batch -source pl/cnn/testbench/FC/run_vivado.tcl -tclargs top 5
vivado -mode batch -source pl/cnn/testbench/FC/run_vivado.tcl -tclargs mac
```

첫 인자는 `fifo/mac/requant/gelu/memories/controller/top`, 두 번째는 RX `3/5`입니다. Tcl은 hex 생성, 임시 Vivado 프로젝트 구성, simulation top 선택, xsim 작업 폴더에 hex 배치 후 behavioral simulation을 실행합니다. 개별 `.v` TB를 기존 프로젝트의 Simulation Sources에 추가할 때는 File Type을 **SystemVerilog**로 지정합니다. Top TB의 `RX`와 생성 fixture의 `--rx`는 일치해야 합니다.

실제로 실행한 도구는 Icarus 12.0입니다. 이 작업 환경에는 Vivado가 없으므로 Tcl의 xsim 실행과 synthesis/implementation 및 실제 보드 검증은 수행하지 않았습니다. 전체 CNN/Loader/AXI 검증은 [기존 golden TB](../rounding/README.md)를 사용합니다.

## 2026-10-10 검증 결과

기준 소스: `main`의 `f6e4d7a5152eb553fac84ac9528655ab3978f10a`.

| 대상 | 결과 |
|---|---|
| `pl/cnn/rtl/FC` | 6종 단위 TB(8회 실행)와 RX3/RX5 Top 통과 |
| `integration/pose_cnn_1.1/src`의 FC | 동일 회귀 통과 |
| `integration/pose_cnn_par_1.2/src`의 FC | 동일 회귀 통과 |
| 기존 반올림 회귀 | Encoder/FC 각각 8,000개, Pool 16,383+12,950개, Encoder Requant 5,000개, RX5 Encoder 640 words 모두 통과 |

각 Top 구성은 총 560개 MAC 결과와 560개 저장값, 48개 Pose 읽기, done 6회를 확인합니다. RX5 FC2는 2,062cycle, FC3는 397cycle이 관측됐습니다. FC1은 의도적으로 공급을 멈추므로 약 123,292cycle이며 일반 처리속도 측정값으로 사용하지 않습니다. FC 연산 RTL은 수정하지 않았습니다.
