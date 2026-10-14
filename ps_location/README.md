# PS 위치 추론 이전 개발 버전 (ps_location)

`ps/`와 `pc/backend/`의 현재 기본 구성은 **PS C Ridge 위치 추론 + FPGA Pose + TCP 5000 단일 포트**입니다. 이 폴더는 해당 구성을 기본 경로로 통합하기 전의 개발·검증 버전을 보존합니다.

기존 구조에서는 PS가 원본 CSI를 PC로 보내고 PC Backend가 위치(Ridge)를 계산했습니다. 이 시험판은 **위치 추론까지 PS에서 C로 처리**하고, PS→PC 통신을 **TCP 5000 하나**로 합칩니다.

| | 기존 (`ps/`, `pc/backend/`) | 시험판 (`ps_location/`) |
|---|---|---|
| 위치 계산 | PC Python | PS C (`ps/src/loc_ridge.c`) |
| 자세 계산 | FPGA | FPGA (같음) |
| TCP | 5000: CSI/STATUS/ACK, 5001: Pose | 5000 하나: Location(5)/Pose(2)/STATUS/ACK, 원본 CSI는 `WISE_FORWARD_CSI=1`일 때만 |
| 위치 모델 | PC `ridge_portable.npz` | PS `ps/models/loc_ridge_rx5.bin` (같은 npz에서 변환) |

기준: `main` `7d204f6`의 `ps/`와 `pc/backend/`에 변경을 합쳤습니다(최신 `LocationStabilizer`, 오프라인 Pose API 포함). 바이트 규격은 [docs/ps_pc_protocol.md](docs/ps_pc_protocol.md)(v1.2)에 있습니다.

## 폴더 구성

| 경로 | 내용 |
|---|---|
| `ps/` | 보드 앱 전체. 새 파일: `src/loc_ridge.c`, `include/loc_ridge.h`, `models/loc_ridge_rx5.bin`, `tools/export_loc_model.py`, `tests/loc_ridge_replay.c`. 수정: `src/wise_server.c`, `src/pose_cnn_rx5_live.c`, `petalinux/*` |
| `pc/backend/` | Backend 전체. 새 파일: `app/ps_link.py`(단일 포트 수신), 테스트 2개. 수정: `app/service.py`(PS 결과 표시), `protocol/wise_protocol.py`(type 5) 등 |
| `docs/ps_pc_protocol.md` | 통신 규격 v1.2 |

위치 모델은 `run_20261013_122537_33a43334`(10/13 학습 Ridge)입니다. 검증 창 267개에서 sklearn 원본과 점수 차이 0, 실제 검증 CSI 40창을 C 엔진에 넣었을 때 라벨 40/40 일치(점수 상대 오차 ≤ 6×10⁻⁸)를 확인했습니다.

## 보드 (Ubuntu VM의 PetaLinux)

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
- 채택하면 이 폴더의 `ps/`, `pc/backend/`, `docs/ps_pc_protocol.md`를 저장소 원래 위치로 옮기고 루트 문서(README, architecture, bringup, interface)의 포트 설명을 함께 고칩니다.
