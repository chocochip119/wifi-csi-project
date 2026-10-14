"""Portable Ridge (.npz + .json) -> PS location model binary (WLOC v1).

Usage (repository root):
    python ps/tools/export_loc_model.py pc/backend/localization/models/localization/ridge_portable.npz ps/models/loc_ridge_rx5.bin

Layout, little-endian (read by ps/src/loc_ridge.c):
    0   "WLOC", u32 version=1, u32 n_classes, u32 n_features, u32 n_rx,
        u32 csi_len, u32 drop_pairs, u32 min_window_cycles
    32  f64 window_s, f64 min_interval_s, f64 min_window_span_s, f64 train_stride_s
    64  u32 has_mac_mapping, u8 mac[5][6] (RX index order), zero pad to 128
    128 class table in estimator order: u8 code, u8 has_xy, i16 x_cm, i16 y_cm, u16 0
        then f64 scaler_mean[nf], scaler_scale[nf], coef[nc][nf], intercept[nc]
    end u32 CRC32 (zlib) of everything before it
Class code = index in labels.CLASSES (p01..p10, empty), as on the TCP wire.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import struct
import sys
import zlib

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "pc" / "backend"))

from localization.labels import CLASSES  # noqa: E402
from localization.portable_ridge import PortableRidge  # noqa: E402

VERSION = 1
HEADER = struct.Struct("<4s7I4dI30s")
HEADER_BYTES = 128
CLASS = struct.Struct("<BBhhH")


def build(model: PortableRidge) -> bytes:
    cfg = model.config
    if cfg.get("layout_id") != "layout_02" or cfg.get("mode") != "window":
        raise ValueError("PS engine supports layout_02 window models only")
    if list(cfg["rx_ids"]) != list(range(5)):
        raise ValueError("PS engine expects RX index order 0..4")
    mapping = cfg.get("rx_mac_by_index")
    macs = b"\0" * 30
    if mapping:
        macs = b"".join(bytes.fromhex(str(mapping[str(i)]).replace(":", "").replace("-", ""))
                        for i in range(5))
    header = HEADER.pack(b"WLOC", VERSION, len(model.classes_), model.n_features, len(cfg["rx_ids"]),
                         cfg["csi_len"], cfg["drop_pairs"], cfg["min_window_cycles"],
                         cfg["window_s"], cfg["min_interval_s"], cfg["min_window_span_s"], cfg["stride_s"],
                         int(bool(mapping)), macs)
    header += b"\0" * (HEADER_BYTES - len(header))
    table = b""
    for label in model.classes_:
        if label not in CLASSES:
            raise ValueError(f"unknown class {label!r}")
        xy = model.points_cm.get(label)
        table += CLASS.pack(CLASSES.index(label), int(xy is not None),
                            *(int(v) for v in (xy or (-32768, -32768))), 0)
    arrays = [model.mean, model.scale, model.coef, model.intercept]
    if model.coef.shape != (len(model.classes_), model.n_features):
        raise ValueError("coef shape mismatch")
    body = header + table + b"".join(np.ascontiguousarray(a, dtype="<f8").tobytes() for a in arrays)
    return body + struct.pack("<I", zlib.crc32(body) & 0xFFFFFFFF)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("npz", type=Path)
    parser.add_argument("out", type=Path)
    args = parser.parse_args(argv)
    data = build(PortableRidge(args.npz))
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_bytes(data)
    print(f"wrote {args.out} ({len(data)} bytes, crc32={zlib.crc32(data[:-4]) & 0xFFFFFFFF:08x})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
