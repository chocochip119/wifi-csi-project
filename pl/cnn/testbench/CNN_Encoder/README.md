# CNN_Encoder testbench

RTL: `pl/cnn/rtl/CNN_Encoder/`

| testbench | 대상 | 벡터 생성 | 확인 내용 |
|---|---|---|---|
| `tb_requant_stage.v` | requant_stage | `gen_requant_stage.py` | 5,000개 rq · rq_tag |
| `tb_Conv_MAC.v` | Conv_MAC | `gen_Conv_MAC.py` | 3 RX acc 184,320개 값 · tag · 순서 |
| `tb_CNN_Encoder.v` | CNN_Encoder (전체) | `gen_CNN_Encoder.py` (numpy) | Pool 결과 3,072 B, enc_done |

기대값은 `ML/src/int8_reference.py` 와 같은 수치 규칙(round shift, ÷48, ±127 clamp)으로 계산한다.
Loader 소유 RAM(Conv weight / Param / GELU LUT)은 testbench 안에서 1-cycle 동기 RAM으로 모델링한다.

## 실행 (Vivado xsim, 이 폴더에서)

```
python gen_CNN_Encoder.py
xvlog ../../rtl/CNN_Encoder/*.v tb_CNN_Encoder.v
xelab tb_CNN_Encoder -s enc_sim
xsim enc_sim -R
```

`tb_Conv_MAC`, `tb_requant_stage` 도 같은 방식으로 `gen_*.py` 를 먼저 실행한 뒤 top 이름만 바꿔서 돌린다.
Vivado GUI 에서는 `*.hex` 를 simulation 실행 디렉터리(`<project>.sim/sim_1/behav/xsim`)에 두면 된다.

통과 시 출력:

```
checked=5000 errors=0                                   # tb_requant_stage
checked=184320 errors=0 bad_addr=0 state=0              # tb_Conv_MAC
feat words checked=384 errors=0 enc_done pulses=1       # tb_CNN_Encoder
```
