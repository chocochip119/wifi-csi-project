# ps_location: FPGA Pose + PS Location 자동 실행 (PetaLinux 2020.2)

`ps_location/ps` 안의 **통합 프로그램 하나**가 USB CSI 수신, PL CNN Pose,
PS Ridge Location, TCP 5000을 처리합니다. 부팅 서비스 이름은 기존과 같은
`wisensing-autostart`이므로 **같은 서비스를 두 개 실행하지 않습니다.**

## 1. Windows PC (Git 저장소)

이 폴더의 파일 수정 → `git diff` 검토 → commit/push. `ps/`, `pc/`, `ps_onlysw/`는 수정하지 않습니다.

`petalinux/wisensing-location.conf`의 `WISE_INPUT_SCALE`을 **현재 Pose 가중치의
`activation_scales["encoder.input"]` 값으로 수정**합니다. `WISE_WEIGHTS`도
보드에서 실제 존재하는 가중치 경로로 지정합니다. 값이 비어 있으면 서비스는
잘못된 scale로 추론하지 않고 대기합니다.

## 2. Ubuntu VM (Git pull 후 PetaLinux 빌드)

```sh
cd ~/workspace/wifi-csi/wifi-csi-location-test
git pull --ff-only
SRC="$PWD/ps_location/ps"
PROJ=~/workspace/wifi-csi/2020-Zybo-Z7-OS-CDC
source /home/jw/tools/petalinux/2020.2/settings.sh
bash "$SRC/petalinux/install_app.sh" "$PROJ"
cd "$PROJ"
petalinux-build -c pose-cnn-rx5
petalinux-build
```

`install_app.sh`는 기존 `pose-cnn-rx5` recipe를 타임스탬프 백업합니다.
현재 VM의 **기존 `wisensing-autostart`와 같은 init.d 이름**을 사용하지만,
새 rootfs 안에서는 Ridge 통합 앱을 실행하도록 교체합니다.

빌드 후 `images/linux/rootfs.tar.gz` 안에 다음이 있는지 확인합니다:

- `/etc/init.d/wisensing-autostart`
- `/etc/default/wisensing-location`
- `/usr/bin/pose_cnn_rx5_live`
- `/usr/share/pose-cnn-rx5/loc_ridge_rx5.bin`

## 3. 보드 배포와 확인

먼저 기존 SD 카드/`image.ub`를 백업합니다. 현재 하드웨어·Device Tree가
동일하다면 새 `image.ub`로 앱 포함 rootfs를 갱신합니다. 필요한 `BOOT.BIN`이나
실제 가중치 파일은 별도로 유지해야 합니다.

보드 재부팅 후 root로:

```sh
/etc/init.d/wisensing-autostart status
cat /etc/default/wisensing-location
tail -n 80 /tmp/wisensing-autostart.log
ps | grep pose_cnn_rx5_live
```

기대 로그: `CNN LOAD PASS`, `Location Ridge model=...`,
`WISE TCP listening :5000`, `LOC window=... class=...`.

- USB가 늦게 인식되거나 가중치가 없으면 supervisor가 5초 간격으로 재시도합니다.
- 자동실행을 중지: `/etc/init.d/wisensing-autostart stop`
- 수동 시험 전 반드시 자동실행을 중지해 **USB/FPGA 중복 점유**를 피합니다.
- PC에서는 새 프로토콜에 맞춰 `ps_location/pc/backend/run_backend.py --ps-host <ZYBO_IP>` 실행.

보드 실제 실행과 최종 이미지 빌드는 별도로 검증해야 합니다.
