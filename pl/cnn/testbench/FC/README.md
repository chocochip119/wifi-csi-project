# FC 연산부 시뮬레이션 테스트

수신기 3개(RX3)와 5개(RX5) 설정에서 FC 연산부를 확인합니다. 입력을 넣은 뒤 연산값, 메모리에 저장된 값, 최종 관절 좌표, 완료 신호를 예상 결과와 비교합니다.

## 실행 방법

저장소 루트에서 Python 3와 Icarus Verilog(`iverilog`, `vvp`)로 실행합니다. 추가 Python 패키지는 필요 없습니다.

```bash
python pl/cnn/testbench/FC/run_regression.py
```

테스트는 결과값이 다르거나 출력 개수·시점이 예상과 다를 때 실패합니다. 제한 시간 안에 끝나지 않아도 실패하며, 시뮬레이터의 실패는 실행 스크립트가 그대로 전달합니다. 생성된 HEX 파일과 실행 파일은 테스트가 끝나면 삭제합니다.

| 테스트 파일 | 확인하는 내용 |
|---|---|
| `tb_fc_fifo.v` | 깊이 3·8·512에서 데이터가 들어온 순서대로 나오는지 확인합니다. 가득 찼을 때 쓰기, 비었을 때 읽기, 동시 읽기·쓰기, 주소 순환, 리셋도 확인합니다. |
| `tb_fc_mac.v` | 부호 있는 INT8 경계값과 8개 병렬 곱셈·누산을 확인합니다. 처음·마지막 입력 신호와 첫 입력의 태그 유지, 640개 그룹 누산, 빈 클록, 4단 지연, 리셋을 포함해 출력값 256개를 비교합니다. |
| `tb_fc_requant.v` | Python으로 따로 계산한 예상값 12,000개와 비교합니다. bias·multiplier·shift의 경계값, 반올림과 포화, RAM 읽기, 태그와 7단 지연, 리셋을 확인합니다. |
| `tb_fc_gelu.v` | 테이블 4개에서 부호 있는 INT8 값 256개를 각각 확인합니다. 주소 변환, 동기 읽기, valid·tag 및 입력이 없는 클록도 확인합니다. |
| `tb_fc_memories.v` | Hidden RAM의 두 뱅크와 바이트 위치, Pose Buffer 주소 24개, Flatten 주소 640개를 확인합니다. 동기 읽기, 같은 주소를 동시에 읽고 쓸 때 기존 값 반환, 리셋 후 RAM 데이터 유지도 확인합니다. |
| `tb_fc_controller.v` | FC1~FC3의 주소·태그·처음/마지막 신호를 확인합니다. FIFO가 비면 대기하고, 실행 중 추가 시작 요청이나 선택 변경 및 잘못된 선택값을 무시하며, 저장 뒤 완료 신호를 한 클록만 내보내는지 확인합니다. |
| `tb_fc_top.v` | RX3·RX5에서 FC1부터 FC3까지 연결한 상태로 각 층의 출력 수 128→128→24를 유지해 검증합니다. 동기 방식 외부 RAM, FIFO가 가득 차거나 비는 상황, 실행 중 리셋·재시작, 리셋 없이 두 번 실행하는 경우를 확인합니다. |

`gen_vectors.py`는 고정 시드로 시험 데이터를 다시 만듭니다. 예상값은 Python에서 정수 내적과 몫·나머지로 별도 계산합니다. 전체 FC 테스트에서 GELU는 시험용 테이블을 사용해 테이블 선택, 주소, 출력 시점을 확인합니다. 학습 모델과 실제 CSI 자세 추정의 정확도는 별도 평가 대상입니다.

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

아래 결과는 Icarus Verilog 12.0에서 실행한 시뮬레이션입니다. Vivado 합성·구현과 실보드 측정은 별도 검증 범위입니다. CNN 전체와 Loader·AXI 연결을 확인하려면 [예상값과 비교하는 전체 CNN 테스트](../rounding/README.md)를 사용합니다.

## 2026-10-10 시뮬레이션 결과

검증에 사용한 소스는 `main`의 `f6e4d7a5152eb553fac84ac9528655ab3978f10a`입니다.

| 대상 | 결과 |
|---|---|
| `pl/cnn/rtl/FC` | 모듈별 테스트 6종(총 8회 실행)과 RX3·RX5 전체 FC 연결 테스트 통과 |
| `integration/pose_cnn_1.1/src`의 FC | 같은 시뮬레이션 테스트 통과 |
| `integration/pose_cnn_par_1.2/src`의 FC | 같은 시뮬레이션 테스트 통과 |
| 기존 반올림 테스트 | Encoder/FC 각각 8,000개, Pool 16,383+12,950개, Encoder Requant 5,000개, RX5 Encoder 640 words 모두 통과 |

RX3·RX5 각각에서 MAC 연산값 560개, 메모리 저장값 560개, 관절 좌표 읽기 48개, 완료 신호 6회를 비교했습니다. RX5 시뮬레이션에서 FC2는 2,062클록, FC3는 397클록이 걸렸습니다. FC1의 약 123,292클록은 가중치 공급을 일부러 중단한 시험 조건에서 나온 값입니다.
