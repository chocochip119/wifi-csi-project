# WiSensing: FPGA Pose + PS Location 자동 실행 (PetaLinux 2020.2)

`ps` 안의 **통합 프로그램 하나**가 USB CSI 수신, PL CNN Pose,
PS Ridge Location, TCP 5000을 처리합니다. 부팅 서비스 이름은 기존과 같은
`wisensing-autostart`이므로 **같은 서비스를 두 개 실행하지 않습니다.**

## 1. Windows PC (Git 저장소)

기본 보드 프로그램 소스는 저장소 `ps/`, PC 결과 표시는 `pc/backend/`에서 관리합니다.

`petalinux/wisensing-location.conf`는 기본적으로 `WISE_INPUT_SCALE=auto`입니다.
Pose blob(v2) 헤더에서 `encoder.input`을 읽으므로 숫자를 매번 입력하지 않습니다.
`WISE_WEIGHTS`는 부팅 FAT32 파티션의 `/weights_5rx.bin`을 가리키도록 설정합니다.
SD카드에 새 가중치를 넣을 때는 반드시 사용 중인 FPGA bitstream/학습 모델과
호환되는 파일인지 확인하세요.

## 2. Ubuntu VM (Git pull 후 PetaLinux 빌드)

```sh
cd ~/workspace/wifi-csi/wifi-csi-location-test
git pull --ff-only
SRC="$PWD/ps"
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
실제 가중치 파일은 별도로 유지해야 합니다. 보드 Linux는 INITRD(rootfs in RAM)
방식이므로, 자동 시작 스크립트가 `/dev/mmcblk0p1` 또는 `/dev/mmcblk1p1`의
FAT32 부팅 파티션을 **읽기 전용**으로 `/mnt/wise-boot`에 마운트합니다.
가중치는 SD카드 FAT32 최상위 경로 `/weights_5rx.bin`에 배치합니다.
Linux 앱은 `/mnt/wise-boot/weights_5rx.bin`을 읽습니다.
`vfat` 커널 지원이 없거나 경로를 찾지 못하면 재시도 로그를 남기며 대기합니다.

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
- SD카드 파일 교체는 전원 종료 후 PC에서 수행하세요. 보드가 켜진 상태에서
  가중치를 교체하려면 서비스를 중지하고 안전하게 언마운트한 뒤 진행합니다.
- 수동 확인: `cat /proc/filesystems | grep vfat`, `mount | grep wise-boot`,
  `ls -lh /mnt/wise-boot/weights_5rx.bin`.
- 자동실행을 중지: `/etc/init.d/wisensing-autostart stop`
- 수동 시험 전 반드시 자동실행을 중지해 **USB/FPGA 중복 점유**를 피합니다.
- PC에서는 새 프로토콜에 맞춰 `pc/backend/run_backend.py --ps-host <ZYBO_IP>` 실행.

보드 실제 실행과 최종 이미지 빌드는 별도로 검증해야 합니다.
