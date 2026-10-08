#!/bin/sh
# Zybo/PetaLinux에서 실행. PS 앱/가중치는 기존 GitHub ps/ 코드의 빌드 결과를 사용한다.
# 예: sh run_pose_live.sh /dev/ttyACM0 0.03125 /root/weights_5rx.bin
set -eu
if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
  echo '사용법: sh run_pose_live.sh TTY FINAL_ENCODER_INPUT_SCALE FINAL_WEIGHTS_BLOB [MAX_WINDOWS]' >&2
  exit 2
fi
TTY=$1
SCALE=$2
BLOB=$3
WINDOWS=${4:-0}
if [ ! -c "$TTY" ]; then echo "[FAIL] USB TTY 장치 없음: $TTY" >&2; exit 2; fi
if [ ! -r "$BLOB" ]; then echo "[FAIL] 가중치 파일을 읽을 수 없음: $BLOB" >&2; exit 2; fi
if ! command -v pose_cnn_rx5_live >/dev/null 2>&1; then
  echo '[FAIL] pose_cnn_rx5_live가 없습니다. PetaLinux 앱 설치/rootfs 포함을 확인하세요.' >&2
  exit 2
fi
case "$WINDOWS" in *[!0-9]*|'') echo '[FAIL] MAX_WINDOWS는 음이 아닌 정수여야 합니다.' >&2; exit 2;; esac
if ! awk -v s="$SCALE" 'BEGIN {exit !(s+0 > 0 && s ~ /^[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?$/)}'; then
  echo '[FAIL] INPUT_SCALE 값이 양수로 해석되지 않습니다.' >&2; exit 2
fi
BYTES=$(wc -c < "$BLOB" | tr -d ' ')
if [ "$BYTES" != '685136' ]; then
  echo "[FAIL] RX5 blob 크기 오류: $BYTES (예상 685136)" >&2
  exit 2
fi
if [ "$(id -u)" != '0' ]; then
  echo '[FAIL] /dev/mem 사용에 root 권한이 필요합니다.' >&2
  exit 2
fi
echo "[WISE] TTY=$TTY / scale=$SCALE / blob=$BLOB / MAX_WINDOWS=$WINDOWS"
echo '[WISE] 외부 코드에서 같은 TTY나 FPGA를 동시에 접근하지 마세요.'
echo '[WISE] 성공 기대 로그: CNN LOAD PASS, WISE TCP listening..., STATUS, POSE_FLOAT'
exec pose_cnn_rx5_live "$TTY" "$SCALE" "$WINDOWS" "$BLOB"
