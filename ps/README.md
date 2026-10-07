# WiSensing PS — RX5 CSI·FPGA 제어·TCP

Zybo Z7-20 / PetaLinux 2020.2의 C 앱입니다. PS는 USB CSI를 파싱·전처리하고 DDR/AXI4-Lite로 FPGA Pose CNN을 제어합니다. 같은 cycle의 원본 CSI는 PC 위치 Backend로 전달합니다. 전체 순서는 [통합 실행](../docs/bringup.md), 바이트 규격은 [PS↔PC TCP](../docs/ps_pc_protocol.md)를 참고하세요.

## 파일 안내

| 경로 | 역할 |
|---|---|
| [src/pose_cnn_rx5_live.c](src/pose_cnn_rx5_live.c) | USB 수신, TX 명령·watchdog, LOAD/INFER, Pose 출력 |
| [src/csi_pipeline.c](src/csi_pipeline.c) / [include/csi_pipeline.h](include/csi_pipeline.h) | CSI 파서, INT8 입력 윈도우 |
| [src/wise_server.c](src/wise_server.c) / [include/wise_server.h](include/wise_server.h) | TCP 5000/5001, 포트별 송신 스레드·유한 큐 |
| [include/pose_cnn_regs.h](include/pose_cnn_regs.h) | CSR·DDR 주소 |
| [include/pose_cnn_lock.h](include/pose_cnn_lock.h) | 두 앱의 FPGA/DDR 동시 접근 방지 |
| [src/pose_cnn_rx5_board_test.c](src/pose_cnn_rx5_board_test.c) | 기존 시험 scale을 사용하는 고정 입력 검증 앱 |
| [test_vectors/](test_vectors/README.md) | 과거 blob·입력·기대 출력과 최신 반올림 차이 |
| [petalinux/install_app.sh](petalinux/install_app.sh) | PetaLinux 앱 소스 배치·기존 recipe 백업 |
| [petalinux/pose-cnn-rx5.bb](petalinux/pose-cnn-rx5.bb) | ARM 컴파일·설치 recipe, `-lm -pthread` |
| [petalinux/pose-cnn-rx5-vectors.inc](petalinux/pose-cnn-rx5-vectors.inc) | 선택적인 바이너리 설치 설정 |
| [petalinux/system-user.dtsi](petalinux/system-user.dtsi) | DDR 예약·USB Host 설정 |

## 데이터·하드웨어 계약

| 항목 | 값 |
|---|---|
| USB | TX Coordinator → `/dev/ttyACM0` 등 실제 TTY |
| 입력 | INT8 `[15,128,10]`, 19,200 bytes/윈도우 |
| 출력 | INT8 24 bytes, 12관절 x/y; `INT8 × output_scale` |
| CSR | `0x43C00000` |
| 가중치 / 입력 / 출력 DDR | `0x3F000000` / `0x3F100000` / `0x3F200000` |
| 예약 메모리 | `0x3F000000`부터 16MiB, `no-map` |
| TCP | 5000: CSI/STATUS/ACK, 5001: Pose; PS 서버·PC 클라이언트 |

주소·Device Tree·레지스터를 실제 하드웨어와 맞춰야 합니다. 저장소의 [기존 XSA](../integration/README.md)는 내부 bitstream을 포함하지만 최신 RTL로 재생성한 배포 결과가 아닙니다. BOOT.BIN/Linux 이미지는 별도로 빌드합니다. CSR 상세와 CLEAR 제한은 [인터페이스](../docs/interface.md)에 있습니다.

## PetaLinux에 설치 — Ubuntu VM

저장소의 `ps/`에서 실행합니다. 설치 경로는 `project-spec/meta-user/recipes-apps/pose-cnn-rx5`입니다.

```bash
source /home/petalinux/petalinux/2020.2/settings.sh
bash petalinux/install_app.sh ~/wimotion/projects/pose-cnn-linux
```

기본은 source-only 설치입니다. 저장소에는 과거 시험 `.bin`이 존재하고 스크립트가 recipe의 `files/`로 복사하지만, 기본 recipe의 바이너리 설치는 활성화하지 않습니다. 검증된 세 파일을 rootfs에도 설치하려면 `bash petalinux/install_app.sh PROJECT VERIFIED_VECTOR_DIR`로 디렉터리를 명시합니다. 이름·scale·재검증 조건은 [시험 벡터 안내](test_vectors/README.md)를 확인하세요.

Device Tree는 자동으로 덮어쓰지 않습니다. `petalinux/system-user.dtsi`와 프로젝트의 `project-spec/meta-user/recipes-bsp/device-tree/files/system-user.dtsi`를 비교·병합합니다.

```bash
cd ~/wimotion/projects/pose-cnn-linux
petalinux-build -c pose-cnn-rx5 -x clean
petalinux-build -c pose-cnn-rx5
petalinux-build
tar -tzf images/linux/rootfs.tar.gz | rg 'usr/bin/pose_cnn_rx5_(live|board_test)'
```

동일 하드웨어·Device Tree의 앱 업데이트에는 새 `image.ub`를 사용합니다. XSA나 부트 이미지에 들어가는 하드웨어·Device Tree가 바뀌면 BOOT.BIN도 다시 패키징합니다.

## 보드 실행

TX 네이티브 USB/OTG를 Zybo J11에 연결하고 RX 5대를 켠 뒤 실제 TTY를 확인합니다.

```bash
ls -l /dev/ttyACM* 2>/dev/null
```

최종 모델의 `activation_scales["encoder.input"]`을 INPUT_SCALE에 사용합니다. 실행 형식:

```text
pose_cnn_rx5_live TTY INPUT_SCALE [MAX_WINDOWS] [BLOB] [DUMP_BIN]
pose_cnn_rx5_live /dev/ttyACM0 <encoder.input_scale> 0 <최종_weights_5rx.bin>
```

`MAX_WINDOWS=0`은 연속 실행입니다. `DUMP_BIN`은 입력 윈도우이며 출력 Pose가 아닙니다. 10윈도우는 192,000 bytes, 100윈도우는 1,920,000 bytes입니다. 좌표는 로그의 `POSE_INT8`, `POSE_FLOAT`와 TCP 5001로 전달합니다. 예전 시험의 입력 scale `0.02`를 최종 학습 모델에 그대로 적용하지 마세요.

고정 입력 검사는 동일 blob·입력·기대 출력과 해당 하드웨어를 준비한 뒤 사용합니다.

```text
pose_cnn_rx5_board_test [BLOB INPUT EXPECTED]
```

기본 경로는 `/usr/share/pose-cnn-rx5/`의 `blob_rx5_test.bin`, `input_rx5_test.bin`, `pose_expected.bin`입니다. 성공 시 `BIT-EXACT PASS`, `BOARD RX5 CNN PASS`를 출력합니다. 다만 기존 기대 출력은 최신 반올림 결과와 **15/24 bytes**가 다르고, 앱의 `EXPECTED_SCALE_BITS=0x3BD997A8`도 고정되어 있습니다. 최신 golden으로 비교하고 임의 최종 모델의 scale 검사는 별도로 맞춰야 합니다.

## PC 연결

PC 저장소 루트에서 `python pc/backend/run_backend.py --ps-host <PS_IP>`를 실행합니다. 기본 PS bind는 `0.0.0.0`; `WISE_TCP_BIND`로 IPv4 주소를 제한할 수 있습니다. 포트별 활성 연결은 1개, 송신 큐는 64프레임이고 250ms 제한을 넘으면 해당 연결을 초기화합니다. PS는 실행 중 3초마다 TX STATUS를 조회합니다.

PC에서 실제 RX 배치/학습 순서를 확인한 뒤 API로 위치 추론을 시작합니다. [Backend 실행·API](../pc/backend/README.md)를 참고하세요. 기존 `CSI_UDP_TARGET=IPv4:port` WCSI v1 디버그 경로는 선택적으로 유지하며 [UDP 확인 도구](../pc/backend/tools/udp_receiver.py)를 사용합니다.

## 검증 기록과 현재 상태

아래는 **2026-09-30 당시 코드·시험 모델**의 보드 기록입니다. 최신 TCP/반올림 수정의 보드 회귀 결과로 해석하지 않습니다.

| 시험 | 당시 결과 |
|---|---|
| 정적 검사 | 레지스터, LOAD/INFER, 기대 출력 24/24 bytes |
| 실시간 100윈도우 | CSI 1,000사이클·윈도우 100개·추론 100회 |
| 오류 통계 | watchdog 0, malformed 0, checksum error 1 |
| TX/RX 재연결 | 이후 10윈도우·추론 10회 |
| 전체 전원 재부팅 | 이후 10윈도우·추론 10회 |
| FPGA 추론 시간 | 관찰값 약 23~24ms/윈도우 |

현재 소스의 호스트 컴파일·TCP 회귀 결과는 [2026-10-07 점검](../docs/reviews/2026-10-07-pc-integration.md)에 있습니다. ARM/PetaLinux 전체 빌드·새 RTL bitstream·보드 비교는 남아 있습니다. `infer_ms`는 CSI 수집을 포함한 전체 지연시간과 다릅니다.

입력 scale은 유한 양수·범위와 전체 문자열을 검사하고, 윈도우 수는 부호 없는 십진수로 검사합니다. 두 앱은 `/run/pose-cnn-rx5.lock`을 공유하지만 다른 직접 접근 프로그램에는 적용되지 않습니다. BUSY/timeout 강제 복구는 구현하지 않았고 CLEAR는 DMA 중단이 아닙니다. timeout 후 하드웨어 reset 절차를 확인해야 합니다.

수정은 저장소의 `ps/`에서 진행하고 [Git 가이드](../docs/git_guide.md)에 따라 PR로 검토합니다. 빌드 결과·SD 백업은 소스 변경과 구분합니다.
