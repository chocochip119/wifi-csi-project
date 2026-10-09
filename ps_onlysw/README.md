# PS_SW_RX5 — Pose CNN을 PS(ARM)에서 전부 처리 + PS/PL 속도 비교

`ps/`(origin/main `7dfe2d0`) 구조를 그대로 따르되, CNN 추론을 FPGA 대신 **Cortex-A9 소프트웨어**로 수행합니다.
같은 `weights_5rx.bin`, 같은 INT8 입력 `[15,128,10]`을 받아 **PL IP와 바이트 단위로 동일한 24B Pose**를 냅니다
(반올림 규약 `nearest_half_away_from_zero_v1`, `ml/pose/INT8.md`).

> 보드에서 PS/PL 시간을 비교하는 절차는 [RUN_README.md](RUN_README.md)에 정리되어 있습니다.

## 파일

| 경로 | 역할 |
|---|---|
| `include/pose_cnn_sw.h`, `src/pose_cnn_sw.c` | SW CNN 엔진 (blob 검증·해석, Conv1/2+GELU, Pool, FC1~3). RX 단위 멀티스레드 옵션 |
| `src/pose_cnn_rx5_live_sw.c` | `pose_cnn_rx5_live`의 PS 전용판. USB 수신·전처리·TCP 5000/5001 동일, 추론만 SW. `/dev/mem`·bitstream 불필요 |
| `src/pose_cnn_rx5_bench.c` | 같은 입력으로 PS SW와 PL IP(`--pl`)를 돌려 지연시간 통계 + bit-exact 비교 |
| `src/csi_pipeline.c`, `src/wise_server.c`, `include/*.h` | upstream `ps/` 그대로 복사 (수정 없음) |
| `petalinux/pose-cnn-rx5-sw.bb` | PetaLinux recipe (`-O3`) |
| `bin/` | Vitis 2020.2 ARM gcc 9.2로 미리 빌드한 실행파일 (glibc 2.30 동적 링크, PetaLinux 2020.2와 동일) |
| `test_vectors/` | ML 실가중치 `weights_5rx.bin` + 입력 + RTL 기대 출력 (RTL sim `vec_rx5_ml`과 동일) |

## 검증 결과 (Host PC)

- `vec_rx5`(합성), `vec_rx5_ml`(실가중치) 두 벡터 모두 RTL 기대 출력과 **24/24 bytes 일치**
- ARM 크로스 빌드 `-Wall -Wextra` 경고 0
- 보드 실행/속도 측정은 아직 안 함 (아래 절차로 측정)

## 보드에 올리기

빠른 방법 — 미리 빌드된 바이너리 복사:

```bash
scp bin/pose_cnn_rx5_bench bin/pose_cnn_rx5_live_sw test_vectors/* root@<ZYBO_IP>:/root/
```

정식 방법 — PetaLinux recipe:

```bash
cd ~/wimotion/projects/pose-cnn-linux
petalinux-create -t apps --template install -n pose-cnn-rx5-sw --enable
cp <PS_SW_RX5>/petalinux/pose-cnn-rx5-sw.bb project-spec/meta-user/recipes-apps/pose-cnn-rx5-sw/
cp <PS_SW_RX5>/src/*.c <PS_SW_RX5>/include/*.h project-spec/meta-user/recipes-apps/pose-cnn-rx5-sw/files/
petalinux-build -c pose-cnn-rx5-sw
```

직접 크로스 빌드 (Windows, Vitis 2020.2):

```bash
T=C:/Xilinx/Vitis/2020.2/gnu/aarch32/nt/gcc-arm-linux-gnueabi
$T/bin/arm-linux-gnueabihf-gcc --sysroot=$T/cortexa9t2hf-neon-xilinx-linux-gnueabi \
  -O3 -mcpu=cortex-a9 -mfpu=neon -mfloat-abi=hard -Iinclude \
  -o bin/pose_cnn_rx5_bench src/pose_cnn_sw.c src/pose_cnn_rx5_bench.c -lm -pthread
```

## 속도 비교 방법

### 1) 고정 입력 벤치마크 (권장)

```bash
# PS만 (bitstream 없어도 됨)
./pose_cnn_rx5_bench weights_5rx.bin input_rx5.bin -n 100 -e pose_expected_rx5.bin
./pose_cnn_rx5_bench weights_5rx.bin input_rx5.bin -n 100 -t 2      # 코어 2개 사용

# PS vs PL (root, pose_cnn bitstream 로드 상태, 다른 CNN 앱 종료)
./pose_cnn_rx5_bench weights_5rx.bin input_rx5.bin -n 100 -t 1 --pl -e pose_expected_rx5.bin
```

출력 항목:

| 항목 | 의미 |
|---|---|
| `PS SW total / encoder / fc` | ARM 추론 전체 / Conv·Pool / FC 구간 |
| `PL HW (START->DONE)` | CSR START부터 DONE까지 (busy-poll, sleep 없음) |
| `PL e2e (copy+run)` | 입력 DDR 복사 + HW + 출력 복사 — live 앱이 실제로 쓰는 비용 |
| `Speed-up`, `win/s` | PS 평균 ÷ PL 평균, 초당 처리 가능한 윈도우 수 |
| `PL vs SW` | 모든 윈도우에서 PL과 SW 출력이 같은지 (BIT-EXACT PASS) |

실제 CSI로 비교하려면 live 앱의 5번째 인자 `DUMP_BIN`으로 입력 윈도우를 저장한 뒤 그 파일을 `INPUT_BIN`으로 주면 됩니다
(N×19,200 bytes, 윈도우별로 PL/SW를 비교).

### 2) 실시간 스트림 비교

```bash
pose_cnn_rx5_live    /dev/ttyACM0 <encoder.input_scale> 100 /root/weights_5rx.bin   # PL
POSE_SW_THREADS=1 ./pose_cnn_rx5_live_sw /dev/ttyACM0 <encoder.input_scale> 100 /root/weights_5rx.bin   # PS
```

PS 버전은 매 윈도우 `infer_ms / encoder_ms / fc_ms`를 출력하고, 종료 시 `PS INFER STATS avg/min/max`를 출력합니다.
TCP 5001 Pose 패킷의 `infer_us`에도 SW 측정값이 들어갑니다.

## 해석 시 주의

- 기존 PL live 앱의 `infer_ms`는 **ms 단위 정수 + 100µs sleep 폴링**이라 정밀 비교에는 bench의 PL 수치를 쓰세요.
- CSI 1 window = 10 cycle이므로, 추론 시간이 window 주기보다 짧으면 live 처리량은 PS/PL 모두 CSI 수신 속도로 제한됩니다.
  차이는 추론 지연과 CPU 점유율(`top`)에서 드러납니다.
- `-t 2`는 RX 5개를 두 코어로 나눕니다 (3:2 분배). live에서는 USB/TCP 스레드와 코어를 나눠 씁니다.
- 위의 Host PC(x86) 수치(~5ms)는 참고용이 아닙니다. A9 667MHz에서는 수십~100ms대가 예상됩니다.
- SW 엔진은 PL loader와 같은 blob 검증(magic/version/words, shift −31..63, scale > 0)을 합니다.
