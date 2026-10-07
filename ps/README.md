# WiSensing PS — 5RX CSI 처리 및 FPGA CNN 제어

Zybo Z7-20 / PetaLinux 2020.2에서 실행하는 C 소스입니다. PS가 5RX CSI를 파싱·전처리하고 DDR 및 AXI4-Lite를 통해 FPGA CNN을 제어합니다. CNN 연산은 FPGA에서 수행하며 PS CPU 단독 FP32/INT8 CNN 추론 코드는 포함하지 않습니다.

## 폴더 구조

```text
ps/
├── README.md
├── src/
│   ├── csi_pipeline.c                # CSI 파싱·INT8 전처리
│   ├── pose_cnn_rx5_live.c           # 실시간 수신·FPGA 제어·좌표 출력
│   ├── wise_server.c               # 비동기 TCP 5000/5001 서버
│   └── pose_cnn_rx5_board_test.c     # 고정 입력 bit-exact 검증
├── include/
│   ├── csi_pipeline.h               # 전처리 API
│   └── pose_cnn_regs.h              # 레지스터·DDR 주소
├── test_vectors/
│   └── pose_expected.txt            # 예상 출력 설명
└── petalinux/
    ├── install_app.sh               # PetaLinux 앱 배치 스크립트
    ├── pose-cnn-rx5.bb              # ARM 컴파일·설치 레시피
    └── system-user.dtsi             # DDR 예약·USB Host 설정
```

## 코드 바로 찾기

| 기능 | 파일 |
| --- | --- |
| USB 수신, Coordinator 명령, watchdog, DDR 전달, LOAD/INFER | [pose_cnn_rx5_live.c](src/pose_cnn_rx5_live.c) |
| CSI 파싱 및 입력 윈도우 생성 | [csi_pipeline.c](src/csi_pipeline.c) |
| 전처리 인터페이스 | [csi_pipeline.h](include/csi_pipeline.h) |
| CSR 오프셋 및 버퍼 주소 | [pose_cnn_regs.h](include/pose_cnn_regs.h) |
| 레지스터 및 예상 출력 비교 | [pose_cnn_rx5_board_test.c](src/pose_cnn_rx5_board_test.c) |
| 컴파일 및 rootfs 설치 | [pose-cnn-rx5.bb](petalinux/pose-cnn-rx5.bb) |
| DDR 예약 및 USB PHY/Host | [system-user.dtsi](petalinux/system-user.dtsi) |
| 예상 출력 설명 | [pose_expected.txt](test_vectors/pose_expected.txt) |

읽는 순서: **레지스터 정의 → 정적 검증 앱 → 전처리 → 실시간 앱**.

## 데이터 흐름

```text
RX 5대 → TX Coordinator → Zybo USB /dev/ttyACM0
       → PS CSI 파싱·INT8 전처리 [15,128,10]
       → DDR 입력 → AXI4-Lite 시작 명령
       → FPGA CNN (M00_AXI → PS HP0)
       → PS 결과 읽기 → POSE_INT8 / POSE_FLOAT
```

| 항목 | 값 |
| --- | --- |
| 입력 | INT8 `[15,128,10]`, 19,200 bytes/윈도우 |
| 출력 | INT8 24 bytes, 12관절 x/y 좌표 |
| CSR | `0x43C00000` |
| 가중치 / 입력 / 출력 DDR | `0x3F000000` / `0x3F100000` / `0x3F200000` |
| 예약 메모리 | `0x3F000000`부터 16MiB, `no-map` |

주소와 Device Tree는 RX5 CNN XSA에 맞춘 설정입니다. 다른 하드웨어에서는 주소·메모리 크기·레지스터 규격을 확인해야 합니다. XSA, bitstream, BOOT.BIN 및 Linux 이미지는 포함하지 않습니다.

## PetaLinux 프로젝트에 설치 — Ubuntu VM

이 저장소는 코드 탐색을 위해 폴더를 간단히 구성했습니다. [install_app.sh](petalinux/install_app.sh)가 앱 파일을 PetaLinux의 `project-spec/meta-user/recipes-apps/pose-cnn-rx5` 경로에 배치합니다. 기존 레시피가 있으면 먼저 백업합니다.

저장소의 `ps` 폴더에서 실행합니다. GitHub checkout에는 가중치/고정 입력/예상 출력 `.bin`이 포함되지 않습니다. 아래 명령은 소스만 설치합니다. 검증된 시험 바이너리가 있다면 `install_app.sh PROJECT VERIFIED_VECTOR_DIR`로 세 파일을 명시적으로 함께 배치하세요. 최종 학습 blob은 실행 시 경로와 input_scale을 별도로 지정해야 합니다.

```bash
source /home/petalinux/petalinux/2020.2/settings.sh
bash petalinux/install_app.sh ~/wimotion/projects/pose-cnn-linux
```

Device Tree는 스크립트가 자동으로 덮어쓰지 않습니다. `petalinux/system-user.dtsi` 내용을 프로젝트의 `project-spec/meta-user/recipes-bsp/device-tree/files/system-user.dtsi`와 비교·병합합니다. 이미 검증된 DDR 예약·USB 설정이 있으면 그대로 사용합니다.

```bash
cd ~/wimotion/projects/pose-cnn-linux
petalinux-build -c pose-cnn-rx5 -x clean
petalinux-build -c pose-cnn-rx5
petalinux-build
tar -tzf images/linux/rootfs.tar.gz | grep -E 'usr/bin/pose_cnn_rx5_(live|board_test)'
```

동일 하드웨어·Device Tree의 앱 업데이트는 새 `image.ub`를 사용합니다. XSA 또는 부트 이미지에 포함된 하드웨어·Device Tree가 바뀌면 BOOT.BIN도 다시 패키징해야 합니다.

## 보드 실행 — Zybo Linux 터미널

정적 검사:

```bash
pose_cnn_rx5_board_test
```

성공하면 `BIT-EXACT PASS`와 `BOARD RX5 CNN PASS`가 출력됩니다.

TX 네이티브 USB/OTG를 Zybo J11에 연결하고 RX 5대를 켠 뒤 장치 번호를 확인합니다.

```bash
ls -l /dev/ttyACM* 2>/dev/null
```

실시간 실행 형식:

```text
pose_cnn_rx5_live TTY INPUT_SCALE [MAX_WINDOWS] [BLOB] [DUMP_BIN]
```

10윈도우 시험:

```bash
pose_cnn_rx5_live /dev/ttyACM0 0.02 10 /usr/share/pose-cnn-rx5/blob_rx5_test.bin /tmp/rx5_precheck.bin 2>&1 | tee /tmp/rx5_precheck.log
wc -c /tmp/rx5_precheck.bin
tail -n 8 /tmp/rx5_precheck.log
```

100윈도우 시험:

```bash
pose_cnn_rx5_live /dev/ttyACM0 0.02 100 /usr/share/pose-cnn-rx5/blob_rx5_test.bin /tmp/rx5_live_100.bin 2>&1 | tee /tmp/rx5_live_100.log
wc -c /tmp/rx5_live_100.bin
tail -n 8 /tmp/rx5_live_100.log
```

`MAX_WINDOWS=0`이면 연속 실행합니다. `DUMP_BIN`에는 입력 윈도우가 저장되고, 자세 좌표는 로그의 `POSE_INT8`, `POSE_FLOAT`에 출력됩니다. 입력 파일 크기는 10윈도우 192,000 bytes, 100윈도우 1,920,000 bytes입니다.

**위 예시의 blob_rx5_test.bin과 입력 스케일 `0.02`는 통합 시험용입니다.** 최종 자세 정확도는 최종 RX5 학습 모델의 blob과 입력 스케일을 적용한 뒤 평가해야 합니다.

## 보드 검증 기록 — 2026-09-30

| 시험 | 결과 |
| --- | --- |
| 정적 검사 | 레지스터, LOAD/INFER, 예상 출력 24/24 bytes 일치 |
| 실시간 100윈도우 | CSI 1,000사이클, 윈도우 100개, 추론 100회 완료 |
| 오류 통계 | watchdog 0회, malformed 0개, checksum error 1개 |
| TX/RX 재연결 | 재연결 후 10윈도우·추론 10회 완료 |
| 전체 전원 재부팅 | 재부팅 후 10윈도우·추론 10회 완료 |
| FPGA 추론 시간 | 관찰값 약 23~24ms/윈도우 |

위 기록은 통합 시험용 모델을 사용한 데이터 경로 및 실행 검증입니다. 자세 정확도 또는 장시간 무오류 동작 보장은 아닙니다. `infer_ms`는 CSI 수집을 포함한 전체 지연시간 및 화면 갱신률과 구분합니다.

## GitHub 업로드

### 2026-10-01 리뷰 수정

- 실시간 앱은 입력 스케일의 전체 문자열, 유한 양수 및 범위를 검사합니다.
- 윈도우 개수는 부호 없는 십진수만 허용하며 잘못된 문자·음수·오버플로를 거부합니다. `0`은 연속 실행입니다.
- [pose_cnn_lock.h](include/pose_cnn_lock.h)의 `/run/pose-cnn-rx5.lock`을 두 앱이 공유하여 동시에 FPGA/DDR을 제어하지 못하도록 합니다. 기존 앱이나 다른 직접 접근 프로그램에는 이 advisory lock이 적용되지 않습니다.
- 하드웨어 BUSY/timeout의 강제 복구는 구현하지 않았습니다. CLEAR를 DMA 중단으로 간주하지 않으며, timeout 후에는 하드웨어 담당자의 reset 절차 확인이 필요합니다.
- 이 수정본은 숫자 인자 검사를 호스트에서 검증했으며 ARM 빌드·보드 회귀 시험은 별도로 필요합니다. 함수 주석 coverage 경고 전체를 해결한 버전은 아닙니다.

`PS` 폴더를 팀 저장소에 복사합니다. C 소스·헤더·레시피·시험 벡터를 함께 올리고, `build/`, `image.ub`, `BOOT.BIN`, SD 백업은 포함하지 않습니다.

## PC 연결 — TCP 기본 경로

현재 live 앱은 TCP 5000(CSI/STATUS/ACK), 5001(Pose)의 서버를 엽니다. `WISE_TCP_BIND`로 PS IPv4 주소를 제한할 수 있습니다. 상태를 유지하기 위해 PS가 3초마다 TX에 `status`를 요청합니다. 네트워크 송신은 별도 스레드와 유한 큐를 사용합니다.

PC에서 `python pc/backend/run_backend.py --ps-host <PS_IP>`를 실행하고 실제 RX 배치 확인 후 API로 위치 추론을 시작합니다. 자세한 [실행 방법](../pc/backend/README.md)과 [바이트 규격](../docs/ps_pc_protocol.md)을 참조하세요.

기존 `CSI_UDP_TARGET=IPv4:port` WCSI v1 디버그 송신은 선택적으로 유지되며 PC 도구는 `pc/backend/tools/udp_receiver.py`로 이동했습니다. TCP Backend는 UDP 패킷을 입력으로 받지 않습니다. `_bypass` 임시 파일명은 일반 live/pipeline 이름으로 정리하고 PetaLinux recipe에 `wise_server.c/.h`와 `-pthread`를 추가했습니다.

호스트 컴파일/전송 회귀 테스트는 완료했으며 이 TCP 추가분의 실제 Zybo/ARM/PetaLinux 전체 빌드는 수행하지 않았습니다. 위 2026-09-30 보드 기록은 이번 TCP 코드의 검증 기록이 아닙니다.
