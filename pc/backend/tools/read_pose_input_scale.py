#!/usr/bin/env python3
"""최종 CNN 메타데이터의 encoder.input scale 읽기.
위치 모델(Portable Ridge)의 스케일과 혼동하지 않는다.
"""
import argparse
import json
import math
from pathlib import Path
import struct

ap = argparse.ArgumentParser(description='최종 Pose 모델 encoder.input 스케일 검사')
ap.add_argument('model_json', type=Path, help='최종 Pose CNN export 메타데이터 JSON')
ap.add_argument('--blob', type=Path, help='같은 run에서 export된 weights_5rx.bin')
args = ap.parse_args()
data = json.loads(args.model_json.read_text(encoding='utf-8'))
scales = data.get('activation_scales', {})
val = scales.get('encoder.input')
if val is None and isinstance(scales.get('encoder'), dict):
    val = scales['encoder'].get('input')
try:
    scale = float(val)
except (TypeError, ValueError):
    ap.error('activation_scales["encoder.input"]을 찾을 수 없습니다. JSON 내용과 최종 run을 확인하세요.')
if not math.isfinite(scale) or scale <= 0:
    ap.error('encoder.input scale이 유한한 양수가 아닙니다.')
if args.blob:
    contents = args.blob.read_bytes()
    if len(contents) != 685136:
        ap.error(f'가중치 크기 오류: {len(contents)} != 685136 (RX5 blob)')
    magic, version, words = struct.unpack_from('<III', contents)
    if (magic, version, words) != (0x36574C50, 2, 171284):
        ap.error(f'blob header 오류: magic=0x{magic:08X}, version={version}, words={words}')
    print(f'[OK] RX5 weights blob: {args.blob} ({len(contents)} bytes, header v2)')
print(f'[OK] 최종 encoder.input INPUT_SCALE = {scale:.12g}')
print('보드에서: pose_cnn_rx5_live /dev/ttyACM0',f'{scale:.12g}', '0 /root/weights_5rx.bin')
