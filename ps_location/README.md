# PS 위치 추론 이전 개발 버전 (ps_location)

`ps/`와 `pc/backend/`의 현재 기본 구성은 **PS C Ridge 위치 추론 + FPGA Pose + TCP 5000 단일 포트**입니다. 이 폴더는 해당 구성을 기본 경로로 통합하기 전의 개발·검증 버전을 보존합니다.

**이 폴더를 개발하던 당시**에는 PS가 원본 CSI를 PC로 보내고 PC Backend가 위치(Ridge)를 계산했습니다. 그 구성에서 PS C Ridge와 TCP 5000 단일 연결로 전환한 것이 이 시험판이며, **전환 결과는 이미 현재 `ps/`와 `pc/backend/`에 반영**됐습니다. 새 배포·수정에는 이 폴더의 복제 파일 대신 기본 경로를 사용하세요.

| | 이 전환 전의 과거 구성 | `ps_location/`에서 시험 후 **현재 `ps/`에 채택한 구성** |
|---|---|---|
| 위치 계산 | PC Python | PS C Ridge (`ps/src/loc_ridge.c`) |
| 자세 계산 | FPGA | FPGA (같음) |
| TCP | 5000: CSI/STATUS/ACK, 5001: Pose | **5000 하나**: Location(5)/Pose(2)/STATUS/ACK, 원본 CSI는 `WISE_FORWARD_CSI=1`일 때만 |
| 위치 모델 | PC `ridge_portable.npz` | PS `ps/models/loc_ridge_rx5.bin` (같은 NPZ에서 변환) |

전환 당시 통합 기록: `main` `7d204f6`에 기본 경로로 코드를 합쳤습니다. **현재 Backend의 위치 확정은 3회가 아니라 2회**이며, 바이트 규격은 [기본 규격](../docs/ps_pc_protocol.md)(v1.2)을 우선 참고하세요. 이 하위 폴더 문서/코드의 빌드·테스트 결과는 당시 스냅샷입니다.

## 폴더 구성

| 경로 | 내용 |
|---|---|
| `ps/` | 보드 앱 전체. 새 파일: `src/loc_ridge.c`, `include/loc_ridge.h`, `models/loc_ridge_rx5.bin`, `tools/export_loc_model.py`, `tests/loc_ridge_replay.c`. 수정: `src/wise_server.c`, `src/pose_cnn_rx5_live.c`, `petalinux/*` |
| `pc/backend/` | Backend 전체. 새 파일: `app/ps_link.py`(단일 포트 수신), 테스트 2개. 수정: `app/service.py`(PS 결과 표시), `protocol/wise_protocol.py`(type 5) 등 |
| `docs/ps_pc_protocol.md` | 통신 규격 v1.2 |

위치 모델은 `run_20261013_122537_33a43334`(10/13 학습 Ridge)입니다. 검증 창 267개에서 sklearn 원본과 점수 차이 0, 실제 검증 CSI 40창을 C 엔진에 넣었을 때 라벨 40/40 일치(점수 상대 오차 ≤ 6×10⁻⁸)를 확인했습니다.

## 과거 시험판 재현: 보드 (Ubuntu VM의 PetaLinux)

아래 명령은 이전 폴더 자체를 재현해야 할 때만 사용합니다. **현재 보드의 부팅 자동실행 수정(#81)·RX5 자동 복구(#80)는 `../ps/`가 기준**이며, 이 복제본에서 누락될 수 있습니다.

`ps_location/ps`를 VM으로 옮긴 뒤:

```bash
source /home/petalinux/petalinux/2020.2/settings.sh
cd ps_location/ps
bash petalinux/install_app.sh ~/wimotion/projects/pose-cnn-linux
cd ~/wimotion/projects/pose-cnn-linux
petalinux-build -c pose-cnn-rx5 -x clean && petalinux-build -c pose-cnn-rx5 && petalinux-build
```

실행 인자는 기존과 같습니다. 로그에 `Location Ridge model=...`, `WISE TCP listening :5000`, `LOC window=... class=...`가 나오면 됩니다. 환경 변수는 [ps/README.md](ps/README.md)를 참고하세요.

## PC Backend

저장소 루트에서:

```bash
python ps_location/pc/backend/run_backend.py --ps-host <PS_IP>
```

기존 Backend와 같은 HTTP/WebSocket API(8000)를 제공하므로 Frontend는 그대로 씁니다. RX 배치 확인 후 PS 위치 결과를 표시합니다. `--pose-port`, `--model` 옵션은 없습니다.

## 위치 모델 교체

```bash
python ps_location/ps/tools/export_loc_model.py ps_location/pc/backend/localization/models/localization/ridge_portable.npz ps_location/ps/models/loc_ridge_rx5.bin
scp ps_location/ps/models/loc_ridge_rx5.bin root@<ZYBO_IP>:/usr/share/pose-cnn-rx5/
```

Ridge·`amp_rssi`·RX 5대·384 bytes·`layout_02` 모델만 지원합니다.

## 검증

```bash
python -m pytest ps_location/pc/backend/tests -q
```

Windows에서 28개 통과(C 위치 엔진 parity 포함, 호스트 GCC 필요). `tests/test_transport.py`는 Linux/POSIX가 필요해 아직 실행하지 못했습니다. ARM 크로스 컴파일(Vitis 2020.2 gcc 9.2, `-Wall -Wextra -Werror`)은 통과했고, **실제 보드 실행과 PetaLinux 빌드는 아직 확인하지 않았습니다.**

## 남은 일 / 주의

- 기존 `ps_onlysw/`는 2포트 규격이라 이 Backend와 연결되지 않습니다.
- 원본 CSI 수집 도구(`ml/localization/tools/csi_live_gui_ethernet.py`)를 쓰려면 PS를 `WISE_FORWARD_CSI=1`로 실행합니다.
- 기본 경로로의 채택·문서 갱신은 이미 완료되었습니다. 이 폴더를 최신 코드로 덮어쓰거나 역으로 기본 `ps/`·`pc/backend/`를 이전 버전으로 교체하지 마세요.
