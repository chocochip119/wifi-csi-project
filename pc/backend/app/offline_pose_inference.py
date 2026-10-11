"""Offline RX5 CSV -> deterministic INT8 pose prediction; no live PS/PL dependency.

Consumes model_int8.json/weights_int8.npz from the SAME export as weights_5rx.bin.
Implements the nonoverlapping 10-cycle PS C preprocessing contract and its integer
CNN/LUT/Pool math. CSV camera labels are used for comparison ONLY, never inference.
"""
from __future__ import annotations

import io
import json
import hashlib
import math
import struct
import time
from collections import OrderedDict
from pathlib import Path

import numpy as np
import pandas as pd
from numpy.lib.stride_tricks import sliding_window_view

JOINT_NAMES = (
    'left_shoulder', 'right_shoulder', 'left_elbow', 'right_elbow',
    'left_wrist', 'right_wrist', 'left_hip', 'right_hip',
    'left_knee', 'right_knee', 'left_ankle', 'right_ankle',
)
JOINT_IDS = (11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28)
CHANNELS, SUBCARRIERS, WINDOW = 15, 128, 10
MAX_BYTES = 50 * 1024 * 1024
MAX_WINDOWS = 600


def _normalized(signal):
    # C: float storage, double accumulation, population standard deviation,
    # std < 1e-3 -> denom=1, clipping +/-4, then float output.
    signal = np.asarray(signal, dtype=np.float32)
    vals = signal.astype(np.float64)
    mean = vals.mean()
    std = np.sqrt(((vals - mean) ** 2).mean())
    result = np.clip((vals - mean) / (std if std >= 1e-3 else 1.0), -4, 4)
    return result.astype(np.float32)


def _iq_feature(raw):
    a = json.loads(raw) if isinstance(raw, str) else raw
    a = np.asarray(a)
    if a.shape != (192, 2) or not np.isfinite(a.astype(float)).all():
        raise ValueError('CSI iq_pairs는 192개의 [I,Q] 쌍이어야 합니다.')
    if (a < -128).any() or (a > 127).any() or not np.array_equal(a, a.astype(np.int8)):
        raise ValueError('CSI IQ 값은 signed int8 정수여야 합니다.')
    iq = a.astype(np.int32)
    power = iq[:, 0] * iq[:, 0] + iq[:, 1] * iq[:, 1]
    signal = np.log1p(power.astype(np.float32)).astype(np.float32)
    v = _normalized(signal)[-128:]
    return _normalized(np.concatenate((v[64:128], v[:64])))


def _quantize(x, scale):
    return np.clip(np.rint(np.asarray(x, dtype=np.float32) / np.float32(scale)), -127, 127).astype(np.int8)


def _roundshift(arr, multiplier, shift):
    values = np.asarray(arr, dtype=np.int64) * np.int64(multiplier)
    s = int(shift)
    if s <= 0:
        # Saturating int8 follows immediately; no valid export uses large left shifts.
        if s < -20:
            return np.where(values == 0, 0, np.where(values < 0, -99999, 99999))
        return values * (1 << -s)
    if s > 62:
        # General fallback for extreme legal shifts (avoids int64 add overflow).
        v = np.asarray(values, dtype=object)
        return np.asarray(np.vectorize(lambda q: (1 if q>=0 else -1)*((abs(int(q))+(1 << (s-1))) >> s))(v), dtype=np.int64)
    magnitude = (np.abs(values) + np.int64(1 << (s-1))) >> s
    return np.where(values < 0, -magnitude, magnitude)


def _requant(acc, layer):
    # arr shape: [out_channels, ...].
    result = np.empty(acc.shape, dtype=np.int8)
    for out, (m, s) in enumerate(zip(layer['requant_multiplier'], layer['requant_shift'])):
        result[out] = np.clip(_roundshift(acc[out], m, s), -127, 127).astype(np.int8)
    return result


def _conv(x, w, bias, meta):
    # x [C,H,W], weight [OC,C,KH,KW]. Integer einsum vectorized C inner loop.
    ph, pw = meta['padding']
    arr = np.pad(x.astype(np.int32), ((0,0),(ph,ph),(pw,pw)), mode='constant')
    patches = sliding_window_view(arr, w.shape[-2:], axis=(1,2))
    # [OC, CIN*KH*KW] @ [CIN*KH*KW, H*W]
    mat = patches.transpose(0, 3, 4, 1, 2).reshape(-1, x.shape[1]*x.shape[2])
    acc = (w.astype(np.int32).reshape(w.shape[0], -1) @ mat).astype(np.int64)
    acc += bias.astype(np.int64)[:, None]
    h, width = x.shape[1:]
    return _requant(acc.reshape(w.shape[0], h, width), meta)


def _fc(x, prefix, arrays, meta):
    w = arrays[prefix + '.weight_int8'].astype(np.int32)
    b = arrays[prefix + '.bias_int32'].astype(np.int64)
    acc = (w @ x.astype(np.int32)).astype(np.int64) + b
    return _requant(acc, meta)


def _pool(x, meta):
    out = np.empty((32, 8, 4), dtype=np.int8)
    for row in range(8):
        for col, wstart in enumerate((0, 2, 5, 7)):
            summed = x[:, row*16:(row+1)*16, wstart:wstart+3].astype(np.int32).sum(axis=(1,2))
            v = _roundshift(summed, meta['requant_multiplier'], meta['requant_shift'])
            magnitude = (np.abs(v) + 24) // 48
            out[:, row, col] = np.clip(np.where(v < 0, -magnitude, magnitude), -127, 127)
    return out


class Int8PoseCNN:
    def __init__(self, directory):
        directory = Path(directory)
        info = json.loads((directory / 'model_int8.json').read_text(encoding='utf-8'))
        self.meta = info
        if info.get('node_count') != 5 or info.get('format_version') not in (1,2,3):
            # Require final RX5 exported network. format_version handled below.
            if info.get('node_count') != 5:
                raise ValueError('5RX model_int8.json만 지원합니다.')
        with np.load(directory / 'weights_int8.npz', allow_pickle=False) as npz:
            self.arrays = {k: npz[k].copy() for k in npz.files}
        blob = (directory / 'weights_5rx.bin').read_bytes()
        if len(blob) != 685136:
            raise ValueError('weights_5rx.bin 크기가 685136B가 아닙니다.')
        magic, version, nwords = struct.unpack_from('<III', blob)
        if (magic, version, nwords) != (0x36574C50, 2, 171284):
            raise ValueError('weights_5rx.bin 헤더 버전/크기 불일치')
        self.input_scale, self.output_scale = struct.unpack_from('<ff', blob, 12)
        scales = info['activation_scales']
        if not (math.isclose(self.input_scale, scales['encoder.input'], rel_tol=1e-6)
                and math.isclose(self.output_scale, scales['head.fc3_out'], rel_tol=1e-6)):
            raise ValueError('가중치 BIN과 모델 JSON scale이 다릅니다.')
        self.file_sha256 = hashlib.sha256(blob).hexdigest()
        self.arrays['conv1.weight_int8'].setflags(write=False)

    def infer(self, window):
        if np.asarray(window).shape != (15, 128, 10):
            raise ValueError('Pose CNN 입력은 [15,128,10]이어야 합니다.')
        a, m = self.arrays, self.meta
        x = _quantize(window, self.input_scale)
        pooled = []
        for rx in range(5):
            feats = x[[rx,rx+5,rx+10]]
            c1 = _conv(feats, a['conv1.weight_int8'], a['conv1.bias_int32'], m['layers']['conv1'])
            c1 = a[m['luts']['encoder.gelu1']['array']][c1.astype(np.int16)+128]
            c2 = _conv(c1, a['conv2.weight_int8'], a['conv2.bias_int32'], m['layers']['conv2'])
            c2 = a[m['luts']['encoder.gelu2']['array']][c2.astype(np.int16)+128]
            pooled.append(_pool(c2, m['pool']))
        flat = np.concatenate(pooled, axis=0).reshape(-1)
        a1 = _fc(flat, 'fc1', a, m['layers']['fc1'])
        a1 = a[m['luts']['head.gelu1']['array']][a1.astype(np.int16)+128]
        a2 = _fc(a1, 'fc2', a, m['layers']['fc2'])
        a2 = a[m['luts']['head.gelu2']['array']][a2.astype(np.int16)+128]
        out = _fc(a2, 'fc3', a, m['layers']['fc3'])
        return out.astype(np.float32) * np.float32(self.output_scale), out


def _decode_csv(data):
    if isinstance(data, bytes):
        if len(data) > MAX_BYTES:
            raise ValueError('CSV가 50MB를 초과합니다.')
        text = data.decode('utf-8-sig')
    else:
        text = data
    df = pd.read_csv(io.StringIO(text), encoding='utf-8-sig', low_memory=False)
    required = {'trigger_seq','rx_index','csi_len','iq_pairs'}
    if not required.issubset(df.columns):
        raise ValueError('CSI CSV 필수 열 누락: '+str(sorted(required-set(df.columns))))
    if len(df) > 50000:
        raise ValueError('CSV는 최대 5만 행까지 재생할 수 있습니다.')
    return df


def _windows(df, *, limit=MAX_WINDOWS):
    # Matches PS RX5 pipeline: each trigger is a cycle, missing RX mask zero,
    # carry last valid up to 3 missing cycles, stride exactly 10 cycles.
    all_cycles=[]
    for seq, group in df.groupby('trigger_seq', sort=False):
        if not np.isfinite(float(seq)):
            continue
        rx_feat = np.zeros((5,128),np.float32)
        rx_mask = np.zeros(5, np.float32)
        for row in group.itertuples(index=False):
            try:
                rx = int(row.rx_index)
                if 0 <= rx < 5 and rx_mask[rx] == 0 and int(row.csi_len)==384:
                    rx_feat[rx] = _iq_feature(row.iq_pairs)
                    rx_mask[rx] = 1
            except (ValueError, TypeError, json.JSONDecodeError):
                continue
        all_cycles.append((int(seq), rx_feat, rx_mask, group.iloc[0]))
    if len(all_cycles) < WINDOW:
        raise ValueError('완성된 10개 CSI 트리거가 필요합니다.')
    raw = []
    history = np.zeros((5,128), np.float32)
    known = np.zeros(5, bool)
    gaps = np.full(5,4, np.int32)
    for seq, feats, mask, first in all_cycles:
        raw.append((seq, feats, mask, history.copy(), known.copy(), gaps.copy(), first))
        for rx in range(5):
            if mask[rx]:
                history[rx] = feats[rx]; known[rx]=True; gaps[rx]=0
            else:
                gaps[rx] += 1
    count=min(len(raw)//WINDOW,limit)
    for i in range(count):
        group=raw[i*WINDOW:(i+1)*WINDOW]
        latest=group[-1]
        keep=latest[3].copy()
        known=latest[4].copy()
        gaps=latest[5].copy()
        filled = np.zeros((10,5,128),np.float32)
        masks = np.zeros((10,5),np.float32)
        for tick, (seq, feature, mask,*_) in enumerate(group):
            masks[tick] = mask
            for rx in range(5):
                if mask[rx]:
                    filled[tick,rx] = feature[rx]
                    keep[rx]=feature[rx];known[rx]=True;gaps[rx]=0
                else:
                    if known[rx] and gaps[rx]<3:
                        filled[tick,rx]=keep[rx]
                    gaps[rx]+=1
        channels=np.zeros((15,128,10),np.float32)
        channels[0:5] = filled.transpose(1,2,0)
        channels[5:10,:,1:] = channels[0:5,:,1:] - channels[0:5,:,:-1]
        channels[10:15] = np.broadcast_to(masks.T[:,None,:],(5,128,10))
        yield i, latest[0], channels, latest[-1]


def infer_csv_bytes(data, model_dir, *, max_windows=MAX_WINDOWS):
    started=time.perf_counter()
    model=Int8PoseCNN(model_dir)
    frame=_decode_csv(data)
    frames=[]
    reference_errors=[]
    has_reference = {'frame_width','frame_height'}.issubset(frame.columns) and all(f'{n}_{c}' in frame.columns for n in JOINT_NAMES for c in 'xy')
    for index,seq,window,row in _windows(frame,limit=max_windows):
        pose_float, raw = model.infer(window)
        joints=[{'id':jid,'name':name,'x':float(pose_float[2*i]),'y':float(pose_float[2*i+1])}
                for i,(jid,name) in enumerate(zip(JOINT_IDS,JOINT_NAMES))]
        snapshot={'type':'snapshot','version':1,'seq':index,'pose':{'valid':True,'window_id':index,'end_trigger_seq':seq,
            'coordinate_space':'model_output','joints':joints},
            'location':{'valid':False,'point_id':None,'zone':None},
            'person':{'valid':False,'presence':None,'posture':'unknown'}}
        if has_reference:
            try:
                w,h=float(row.frame_width),float(row.frame_height)
                if w>0 and h>0:
                    truth=np.array([float(getattr(row,f'{n}_{axis}'))/(w if axis=='x' else h)
                                   for n in JOINT_NAMES for axis in 'xy'],dtype=np.float32)
                    if np.isfinite(truth).all():
                        reference_errors.append(float(np.mean(np.abs(truth-pose_float))))
            except (ValueError,TypeError,AttributeError):
                pass
        frames.append(snapshot)
    if not frames:
        raise ValueError('CNN 입력 윈도우가 없습니다.')
    return {'frames':frames,'summary':{'input_rows':len(frame),'windows':len(frames),
      'input_scale':model.input_scale,'output_scale':model.output_scale,
      'cnn':'RX5 INT8 CNN (offline CPU NumPy)', 'model_sha256':model.file_sha256,
      'reference_mae':round(float(np.mean(reference_errors)),6) if reference_errors else None,
      'elapsed_s':round(time.perf_counter()-started,2),'raw_predictions':True}}
