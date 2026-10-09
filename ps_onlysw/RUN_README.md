# PS vs PL 추론 시간 비교 — 실행 방법

Zybo Z7-20(PetaLinux 2020.2) 보드에서 같은 입력으로 **PS(ARM 소프트웨어)** 추론과 **PL(FPGA IP)** 추론 시간을 비교하는 절차입니다.
코드와 파일 설명은 [README.md](README.md)를 참고하세요.

---

## 1. 준비 (PC)

실행파일과 테스트 파일을 보드로 복사합니다.

```bash
scp PS_SW_RX5/bin/* PS_SW_RX5/test_vectors/* root@<ZYBO_IP>:/root/
```

복사되는 파일:

| 파일 | 내용 |
|---|---|
| `pose_cnn_rx5_bench` | PS/PL 시간 비교 도구 |
| `pose_cnn_rx5_live_sw` | 실시간 CSI → PS 추론 앱 |
| `weights_5rx.bin` | ML 실가중치 blob (685,136 B) |
| `input_rx5.bin` | INT8 입력 윈도우 1개 (19,200 B) |
| `pose_expected_rx5.bin` | RTL 기대 출력 (24 B) |

## 2. 보드 상태 맞추기 (보드, root)

1. 공정하게 비교하려면 FPGA나 CPU를 쓰는 다른 앱을 먼저 끕니다.
   ```bash
   killall pose_cnn_rx5_live pose_cnn_rx5_live_sw 2>/dev/null
   ```
2. 실행 권한을 줍니다.
   ```bash
   cd /root && chmod +x pose_cnn_rx5_bench pose_cnn_rx5_live_sw
   ```
3. CPU 클럭을 확인합니다. 값이 안 나오면 고정 클럭이니 그대로 진행하면 됩니다.
   ```bash
   cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null
   ```

`--pl` 옵션을 쓰려면 pose_cnn bitstream이 로드된 상태여야 하고 root 권한이 필요합니다.
PS만 측정할 때는 bitstream이 없어도 됩니다.

## 3. 측정

1. PS(코어 1개)와 PL을 같은 입력으로 100회씩 돌립니다.
   ```bash
   ./pose_cnn_rx5_bench weights_5rx.bin input_rx5.bin -n 100 -t 1 --pl -e pose_expected_rx5.bin
   ```
2. 코어 2개를 쓴 PS와도 비교합니다.
   ```bash
   ./pose_cnn_rx5_bench weights_5rx.bin input_rx5.bin -n 100 -t 2 --pl -e pose_expected_rx5.bin
   ```
3. 각 명령을 2~3번씩 돌려서 값이 비슷한지 확인합니다.

### 옵션

| 옵션 | 의미 |
|---|---|
| `-n N` | 측정 반복 횟수 (기본 100) |
| `-t T` | PS 스레드 수 1~5 (기본 1, Zynq-7020은 코어 2개) |
| `-e FILE` | 첫 윈도우 출력을 비교할 24B 기대값 |
| `--pl` | FPGA IP도 같이 측정 (생략하면 PS만 측정) |

## 4. 결과 읽는 법

출력 형태입니다. 숫자는 예시입니다.

```
SW  vs EXPECTED: BIT-EXACT PASS                   ← PS 결과가 정답과 일치
PL  vs SW: 0/1 windows differ -> BIT-EXACT PASS   ← PS와 PL 결과 동일
  PS  SW total           ... avg  80.0 ms
  PS  SW encoder         ... avg  79.5 ms         ← Conv/Pool
  PS  SW fc              ... avg   0.5 ms         ← FC
  PL  HW (START->DONE)   ... avg  23.0 ms         ← FPGA 연산만
  PL  e2e (copy+run)     ... avg  23.2 ms         ← 입력·출력 복사 포함
Speed-up PL vs PS: 3.4x (e2e)
Max window rate : PS 12.5 win/s, PL 43.1 win/s
```

- **비교 기준은 `PS SW total` avg와 `PL e2e` avg입니다.** 둘 다 "입력 하나를 넣고 Pose를 받기까지" 걸린 시간이라 조건이 같습니다.
- `PASS`가 두 개 다 떠야 의미 있는 비교입니다. 결과가 다르면 시간 비교도 소용없습니다.
- 평균 말고 p95와 max도 같이 보면 시간이 얼마나 튀는지 알 수 있습니다.
- 종료 코드는 출력이 모두 일치하면 0, 하나라도 다르면 1입니다.

## 5. (선택) 실제 CSI 스트림으로 비교

1. PL 버전을 돌리면서 입력 윈도우를 파일로 저장합니다. 맨 끝 인자가 저장할 파일입니다.
   ```bash
   pose_cnn_rx5_live /dev/ttyACM0 <encoder.input_scale> 100 /root/weights_5rx.bin /root/live100.bin
   ```
2. 저장한 실제 윈도우 100개로 PS와 PL을 비교합니다. 윈도우마다 PS/PL 출력이 같은지도 확인합니다.
   ```bash
   ./pose_cnn_rx5_bench weights_5rx.bin live100.bin -n 100 --pl
   ```
3. CPU 점유율도 비교하려면 터미널 하나에서 `top -d 1`을 켜 두고, 다른 터미널에서 각각 실행합니다.
   ```bash
   pose_cnn_rx5_live /dev/ttyACM0 <encoder.input_scale> 0 /root/weights_5rx.bin
   ```
   ```bash
   POSE_SW_THREADS=1 ./pose_cnn_rx5_live_sw /dev/ttyACM0 <encoder.input_scale> 0 /root/weights_5rx.bin
   ```
   - PS 버전은 매 윈도우 `infer_ms / encoder_ms / fc_ms`를 출력합니다.
   - Ctrl+C로 끝낼 때 `PS INFER STATS avg/min/max`를 출력합니다.
   - `POSE_SW_THREADS=2`로 코어 2개를 쓸 수 있습니다.

`<encoder.input_scale>`에는 최종 모델의 `activation_scales["encoder.input"]` 값을 넣습니다.

## 6. 정리용 표

| 구분 | 평균(ms) | p95(ms) | 초당 윈도우 | CPU 점유율 |
|---|---|---|---|---|
| PS 1코어 | | | | |
| PS 2코어 | | | | |
| PL (e2e) | | | | |
| PL (HW만) | | | | — |

## 주의할 점

- 기존 PL live 앱이 찍는 `infer_ms`는 ms 단위 정수인 데다 100µs 쉬면서 상태를 확인하는 방식이라 정밀하지 않습니다. 비교 수치는 bench의 `PL HW` / `PL e2e`를 쓰세요.
- window 하나가 CSI 10 cycle이라, 추론이 그보다 빠르면 실시간 처리량은 PS든 PL이든 CSI 수신 속도에서 막힙니다. 그 경우 차이는 추론 지연과 CPU 점유율에서 드러납니다.
- live 앱에서 `-t 2`(또는 `POSE_SW_THREADS=2`)를 쓰면 USB/TCP 스레드와 코어를 나눠 씁니다.

## 문제 해결

| 증상 | 확인할 것 |
|---|---|
| `open /dev/mem: Permission denied` | root로 실행 |
| `CNN lock unavailable` | 다른 CNN 앱(`pose_cnn_rx5_live`, `board_test`)이 실행 중 → 종료 |
| `PL LOAD timeout` / `PL busy before LOAD` | bitstream 로드 여부, 보드 재부팅 |
| `PL vs SW ... FAIL` | 보드 bitstream의 RTL 버전 (10/07 반올림 규약 반영 여부) |
| `INPUT_BIN size ... not a multiple of 19200` | 입력 파일이 19,200 B 단위인지 확인 |
| `not found` (실행 시) | `chmod +x`, 보드 glibc 버전 (PetaLinux 2020.2 기준 빌드) |
