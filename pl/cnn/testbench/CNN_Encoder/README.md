# CNN Encoder testbench

원본 RTL은 [CNN_Encoder](../../rtl/CNN_Encoder/)에 있습니다. 기대값은 현재 팀 [int8_reference.py](../../../../ml/pose/int8_reference.py)의 nearest, halfway away from zero·Pool·±127 포화를 사용합니다. Loader 소유 weight/parameter/GELU RAM은 testbench에서 1-cycle 동기 RAM으로 모델링합니다.

| Testbench | 벡터 생성 | 확인 |
|---|---|---|
| `tb_requant_stage.v` | `gen_requant_stage.py` | requant 5000개·tag |
| `tb_Conv_MAC.v` | `gen_Conv_MAC.py` | RX3 accumulator·tag·순서 |
| `tb_CNN_Encoder.v` | `gen_CNN_Encoder.py <RX>` | RX당 Pool 1024 bytes, done 1회 |

## 현재 RX5 실행

저장소 루트에서 NumPy와 Icarus Verilog를 준비하고 실행합니다.

```bash
python pl/cnn/testbench/rounding/run_regression.py
```

runner가 RX5 벡터를 새 reference로 생성하고 `tb_CNN_Encoder.RX=5`로 컴파일합니다. 5120 bytes(640 words)·done 1회를 비교합니다. FC/Encoder/Pool 수치 경계 검사도 포함합니다. 도구 옵션은 [rounding 안내](../rounding/README.md)를 참고하세요.

## Vivado xsim에서 직접 실행

이 폴더에서 실행하는 기본 RX3 예시입니다. TB parameter 기본값과 벡터 생성 인자를 함께 3으로 맞춥니다.

```bash
python gen_CNN_Encoder.py 3
xvlog ../../rtl/CNN_Encoder/*.v tb_CNN_Encoder.v
xelab tb_CNN_Encoder -s enc_sim
xsim enc_sim -R
```

RX5에는 벡터 인자와 elaboration의 `tb_CNN_Encoder.RX`를 모두 5로 설정해야 합니다. Vivado GUI에서는 생성된 `*.hex`를 simulation 실행 디렉터리에 둡니다. 현재 정수 규칙으로 생성한 벡터만 사용하세요. 전체 RX5 CNN/LOAD/INFER 비교는 [전체 golden TB](../rounding/README.md)와 [INT8 계약](../../../../ml/pose/INT8.md)에 있습니다.
