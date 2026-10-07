# 정수 반올림 / RX5 golden 검증

저장소 루트에서 NumPy, Icarus Verilog(`iverilog`, `vvp`)를 설치하고 실행합니다.

```bash
python pl/cnn/testbench/rounding/run_regression.py
```

runner는 임시 디렉터리에 벡터/시뮬레이터 출력을 만들고 실패 시 비정상 exit로 종료합니다. 도구가 PATH에 없으면 `--iverilog`, `--vvp`, `--ivl-base` 옵션으로 지정할 수 있습니다.

| 파일 / 단계 | 비교 |
|---|---|
| `gen_vectors.py` + `tb_rounding.v` | 독립 정수 oracle 8000개를 Encoder/FC 각각 비교, signed 경계·동기 BRAM·빈 cycle |
| `tb_pool_rounding.v` | `/48` 중간값 16,383개와 shift 12,950개 |
| 기존 `CNN_Encoder/gen_requant_stage.py` + TB | 팀 reference로 생성한 5000개 requant |
| 기존 `CNN_Encoder/gen_CNN_Encoder.py 5` + TB | RX5 Pool 출력 5120 bytes/640 words와 done 1회 |

## 전체 CNN

`tb_pose_rx5_golden.v`는 가중치 LOAD 뒤 reset 없이 INFER 두 번을 수행해 각각 24좌표, output scale, DMA 출력 길이를 확인합니다. RX5 전용이며 다음 파일을 작업 디렉터리에서 읽습니다.

| 파일 | 크기 |
|---|---:|
| `weights_5rx.bin` | 685,136 bytes |
| `golden_input.bin` | 19,200 bytes |
| `golden_pose.bin` | 24 bytes |

Colab v5가 최종 export 모델과 test window로 생성한 파일을 사용하세요. Verilator 실행 명령과 수치 식은 [INT8 계약](../../../../ml/pose/INT8.md)에 있습니다. 저장소의 과거 [PS 시험 벡터](../../../../ps/test_vectors/README.md)는 최신 반올림 기준으로 재생성한 golden을 대신하지 않습니다.
