# RX5 통합 실행 순서

실제 데이터 경로는 **ESP32 수집 → USB → PS C Ridge 위치 + FPGA Pose → Backend API**입니다. PC만으로 API 연결을 확인하는 fake 모드와 실제 보드 실행을 구분합니다.

## 1. 모델과 하드웨어 준비

- [Colab v5](../ml/pose/README.md)에서 최종 RX5 모델을 export합니다. weights NPZ, model JSON, `weights_5rx.bin`, `golden_input.bin`, `golden_pose.bin` 및 manifest를 같은 run으로 유지합니다.
- [INT8 전체 RTL TB](../ml/pose/INT8.md)로 같은 가중치/input/output scale의 golden을 비교합니다.
- [Integration](../integration/README.md)의 순서로 IP·bitstream·XSA를 새로 생성하고 PetaLinux 하드웨어/Device Tree·CSR·DDR를 맞춥니다.

기존 XSA는 내부 bitstream을 포함합니다. 기존 [PS 시험 벡터](../ps/test_vectors/README.md)의 기대 출력은 새 반올림 결과와 다르므로 최신 golden으로 판단하세요. `pose_cnn_rx5_board_test`는 기존 시험 scale을 상수로 확인하는 전용 검사 앱이며 임의 최종 모델의 일반 검증기로 사용하지 않습니다.

## 2. PS 앱 배치와 부팅 자동실행

기본 배포용 코드는 [`ps/petalinux/`](../ps/petalinux/AUTOSTART.md)에 있는 `wisensing-autostart` SysV init 스크립트와 `pose-cnn-rx5.bb`의 `update-rc.d` 등록입니다. **부팅 시 자동 시작되게 고친 코드는 #81에 병합**됐지만, GitHub 소스만 바꾼다고 기존 SD의 `image.ub`/rootfs가 자동 갱신되지는 않습니다. 기존 보드 이미지에 해당 서비스가 포함·활성화되어 있는지 먼저 확인하세요. 이 프로젝트는 **SD 카드를 새로 만드는 절차를 전제로 하지 않습니다.**

```sh
/etc/init.d/wisensing-autostart status
cat /etc/default/wisensing-location
tail -n 80 /tmp/wisensing-autostart.log
```

현재 서비스는 가중치가 `/mnt/wise-boot/weights_5rx.bin`에 있으면 기존 `/media/...` SD FAT 마운트도 재사용하고, USB나 가중치 준비가 늦으면 5초마다 재시도합니다. `WISE_INPUT_SCALE=auto`로 blob 메타데이터의 scale을 사용합니다. **자동실행 서비스가 켜진 상태에서는 아래 앱을 별도로 띄우지 마세요.** USB/FPGA 중복 점유가 생깁니다.

### 자동실행 대신 수동 점검할 때


[PS README](../ps/README.md)를 따라 앱을 PetaLinux에 설치·빌드합니다. PS용 위치 모델 `loc_ridge_rx5.bin`은 PetaLinux recipe에 포함되며, FPGA Pose 가중치 `weights_5rx.bin`은 별도로 배치합니다. 보드에서 TX 네이티브 USB/OTG를 연결하고 `/dev/ttyACM0` 등 실제 장치 번호를 확인합니다. 다른 USB 수집 앱과 PS live가 같은 장치를 동시에 사용하지 않도록 합니다.

수동 실행에서만 최종 가중치의 metadata JSON `activation_scales["encoder.input"]` 또는 `auto`를 PS 인자로 사용합니다. `auto`는 blob에서 scale을 읽으므로 현재 기본 서비스와 동일한 설정입니다. 실행 형식은 다음과 같습니다.

```text
pose_cnn_rx5_live TTY INPUT_SCALE [MAX_WINDOWS] [BLOB] [DUMP_BIN]
pose_cnn_rx5_live /dev/ttyACM0 auto 0 <최종_weights_5rx.bin>
```

`MAX_WINDOWS=0`은 연속 실행입니다. PS는 FPGA에 LOAD 뒤 INFER하고, TCP 5000에서 PS Location(type 5)·FPGA Pose(type 2)·STATUS·ACK를 함께 제공합니다. 3초마다 TX STATUS를 요청합니다. 로그의 RX 수·LOAD/CFG_OK·POSE_INT8/POSE_FLOAT와 PC 네트워크 연결을 확인하세요. 현재 PS가 TX를 제어하며 PC의 5000 연결로 TX 명령을 보내는 기능은 없습니다.

## 3. PC Backend

PC와 PS가 통신 가능한 IPv4 주소를 사용하고 TCP 5000 방화벽 설정을 확인합니다. 아래 `192.168.10.2`는 기본 예시이므로 실제 PS IP로 바꿉니다. 저장소 루트에서:

```bash
python -m venv .venv
# Linux/macOS
source .venv/bin/activate
# Windows PowerShell: .\.venv\Scripts\Activate.ps1
python -m pip install -r pc/backend/requirements.txt
python pc/backend/run_backend.py --ps-host 192.168.10.2
```

위치 추론은 PS의 `loc_ridge_rx5.bin`을 사용하며, Backend의 NPZ/JSON은 기준 모델 및 테스트용으로 보관됩니다. 학습 RX MAC은 저장되어 있지 않으므로 STATUS의 RX index↔MAC을 실제 배치/학습 순서와 직접 비교해야 합니다.

## 4. RX 5대 확인과 위치 확정

TX가 RUN 4/5로 시작한 뒤 RX 다섯 번째가 뒤늦게 살아나면 STATUS에 LIVE 5/5가 보여도 CSI 슬롯은 여전히 4개일 수 있습니다. **#80의 PS 복구**는 RX0~RX4의 connected/live/saved가 모두 준비되면 `WAIT → RUN`을 자동 재시작하고 `RX5 RECOVERY`를 기록합니다. 준비 상태나 자동 복구 로그를 확인하고 배치 서명을 승인하세요. 누락된 RX를 임의 채워서 추론하지 않습니다.

배치 확인 후 새 PS 위치 윈도우 **2회 연속 같은 지점**이어야 Backend가 위치를 확정합니다. 이전 문서의 3회가 아니라 현재 `LocationStabilizer(confirmations=2)`이며, Frontend의 관절 자세 안정화와 독립적입니다.


아래 조회는 PC의 Backend 기본 주소입니다. 다른 장치에서 접근할 때에는 Backend bind 옵션과 주소를 [Backend README](../pc/backend/README.md)에 맞춰 변경합니다.

```bash
curl http://127.0.0.1:8000/health
curl http://127.0.0.1:8000/api/rx-layout
```

배치/순서가 맞는지 확인한 뒤 다음 POST를 실행합니다. 확인 전에는 위치 `status_ready=false`일 수 있으며, 확인 후 다음 STATUS를 받아 준비가 완료됩니다.

```powershell
# 현재 RX 서명 조회 후 MAC/배치/학습 순서를 직접 대조
$layout = Invoke-RestMethod http://127.0.0.1:8000/api/rx-layout
$layout
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8000/api/confirm-rx-layout -ContentType 'application/json' -Body (@{rx_signature=$layout.rx_signature} | ConvertTo-Json)
Invoke-RestMethod http://127.0.0.1:8000/api/snapshot
```

Windows PowerShell의 curl 별칭 때문에 옵션이 다르게 처리되면 `curl.exe`를 사용합니다. 스냅샷에서 위치/Pose의 availability와 stale를 각각 확인하세요. Pose는 model_output 좌표이며 화면의 0..1 좌표로 가정하지 않습니다. Frontend 실행과 화면 연결 점검은 [Frontend README](../pc/frontend/README.md)를 참고하세요.

## PC만으로 확인

PS 대신 가짜 데이터를 사용하는 API 점검입니다. 별도 터미널에서 실행합니다.

```bash
python pc/backend/run_backend.py --fake
```

`/api/snapshot`, FastAPI `/docs`, `/ws`를 사용합니다. fake 결과는 위치 모델·FPGA·실제 RX 배치 검증이 아닙니다.

## 문제를 확인할 위치

| 관찰 | 확인 |
|---|---|
| PS USB 수신 없음 | 자동실행 서비스 중복 여부, TTY 번호, TX USB 연결/전원, 다른 장치 점유, RX live 상태 |
| LOAD/CFG_OK 실패 | blob v2/RX5 크기, 새 bitstream, DDR/CSR/Device Tree |
| PC 연결 불가 | PS IP, live 앱 실행, TCP 5000 서버·방화벽 |
| 위치 준비 안 됨 | STATUS의 RUN RX 수 vs LIVE/SAVED RX 수, `RX5 RECOVERY`, RX0..4/384 bytes, index↔MAC 확인, 다음 STATUS 및 위치 윈도우 2회 |
| Pose만 unavailable | LOAD/INFER·scale·TCP 5000 연결, 최근 Pose 시각 |
| BIT-EXACT 불일치 | 같은 모델/입력/scale·새 반올림 golden·재빌드한 하드웨어 |

테스트/장비 검증 상태와 남은 ESP32 trigger 정합·Pose 윈도우 연속성은 [점검 기록](reviews/2026-10-07-pc-integration.md)을 참고하세요.
