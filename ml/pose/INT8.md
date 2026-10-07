# INT8 / RTL 반올림 계약

`int8_reference.py`는 ziziccc/wifi-csi-pose의 `4ee1a900bbd8c22fc9d3dc4c2c01845d82ab7fee`를 바탕으로 팀 RTL의 정수 계약을 적용한 NumPy 구현입니다. Colab v5는 학습 모델·calibration/export는 기존 참고 저장소에서, 전처리와 정수 추론·golden 생성은 동일한 팀 저장소 고정 commit에서 불러옵니다.

## 계산

계약 이름은 `nearest_half_away_from_zero_v1`입니다. `v=(acc+bias)*multiplier`, 오른쪽 shift `s>0`, `half=2**(s-1)`일 때:

- `v>=0`: `(v+half)>>s`
- `v<0`: `(v+half-1)>>s`
- `s=0`: 그대로 사용. `s<0`: 왼쪽 shift 후 포화.
- 출력은 `[-127,127]`로 포화합니다.

예를 들어 `v=-4,s=2`는 `-1`, `v=-6,s=2`는 `-2`, `v=-1,s=2`는 `0`입니다. Encoder의 bias 합은 signed 33-bit, 곱은 65-bit로 유지합니다. FC의 기존 pipeline과 파라미터 읽기 타이밍은 유지합니다. 큰 shift를 6비트로 잘라 사용하지 않습니다.

Pool의 두 번째 반올림도 같은 원칙입니다. `/48`은 `sign(p)*((abs(p)+24)//48)`이며, RTL에서는 reciprocal 계산 후 포화합니다. `p=-48`은 `-1`, `p=-24`는 `-1`입니다. 입력 float→INT8의 `np.rint` 및 calibration/weight 양자화는 기존 방식을 유지합니다.

## 검증

저장소 루트에서 NumPy·pytest와 Icarus Verilog(`iverilog`, `vvp`)가 필요합니다. runner의 도구 경로 옵션과 검증 범위는 [RTL 회귀 안내](../../pl/cnn/testbench/rounding/README.md)에 있습니다.

```bash
python -m pytest ml/pose/tests -q
python pl/cnn/testbench/rounding/run_regression.py
```

두 requantizer는 독립 정수 oracle, 동기 RAM, 연속 입력/빈 cycle, signed 경계값으로 확인합니다. Pool은 중간값 `-8191..8191`의 `/48`을 전부 비교합니다. RX5 Encoder 기대값도 새 reference로 매번 생성합니다. 실패·누락·timeout은 simulator의 실패 exit로 처리합니다.

Colab v5의 golden 셀은 실제 export 가중치와 test window 하나로 `golden_input.bin`(19,200 bytes), `golden_pose.bin`(24 bytes), 중간값 NPZ와 scale/commit/SHA256 manifest를 만듭니다. 가중치가 달라지면 golden도 다시 만들어야 합니다. 이는 해당 모델의 정수 기준 출력이며 실제 장비 테스트가 완료됐다는 표시가 아닙니다.

기존 [PS 시험 벡터](../../ps/test_vectors/README.md)의 기대 출력은 새 규칙과 15/24 bytes가 다릅니다. 최종 모델과 같은 export에서 golden을 생성하세요.

전체 RTL 비교에는 export 폴더에서 아래 testbench를 사용합니다. `REPO_ROOT`를 저장소의 절대 경로로 설정하고 Verilator와 C++ compiler를 설치합니다.

```bash
verilator --binary --timing --top-module tb_pose_rx5_golden -Wno-fatal -j 2 \
  "$REPO_ROOT/pl/cnn/testbench/rounding/tb_pose_rx5_golden.v" \
  $(find "$REPO_ROOT/pl/cnn/rtl" -name '*.v')
./obj_dir/Vtb_pose_rx5_golden
```

Testbench는 `weights_5rx.bin`, `golden_input.bin`, `golden_pose.bin`을 읽어 LOAD 뒤 reset 없이 INFER 두 번의 24좌표·scale·DMA 길이를 확인합니다. 합성 fixture 테스트와 최종 학습 모델/실제 보드 확인은 별도로 기록합니다.

`integration/pose_cnn_1.1/src`의 세 수치 연산 소스는 원본 RTL과 동일하게 맞췄습니다. Vivado에서 IP를 다시 패키징하고 synthesis/implementation, bitstream 및 XSA를 생성해야 장비에 반영됩니다. 저장소의 기존 bitstream/XSA가 자동 갱신되는 것은 아닙니다.
