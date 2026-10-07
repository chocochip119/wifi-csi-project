"""Export one RX5 input and expected INT8 pose for RTL/board comparison."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np

from int8_reference import ROUNDING_CONTRACT, fast_cnn_int8_forward, quantize_to_int8


def export_golden(x_float, arrays, metadata, output_dir, *, source_commit):
    x_float = np.asarray(x_float, dtype=np.float32)
    if x_float.shape != (1, 15, 128, 10) or not np.isfinite(x_float).all():
        raise ValueError("golden input must be finite [1,15,128,10] for RX5")
    if int(metadata["node_count"]) != 5:
        raise ValueError("golden export requires RX5 metadata")
    for name in ("encoder.input", "head.fc3_out"):
        scale = float(metadata["activation_scales"][name])
        if not np.isfinite(scale) or scale <= 0:
            raise ValueError(f"invalid scale: {name}")
    _, dumps = fast_cnn_int8_forward(x_float, arrays, metadata, dump_intermediates=True)
    pose = dumps["pose_int8"]
    if pose.shape != (1, 24):
        raise ValueError("golden pose must contain 24 int8 coordinates")
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    q_input = quantize_to_int8(x_float, metadata["activation_scales"]["encoder.input"])
    files = {"golden_input.bin": q_input.tobytes(order="C"),
             "golden_pose.bin": pose.astype(np.int8).tobytes(order="C")}
    for name, data in files.items():
        (output_dir / name).write_bytes(data)
    np.savez_compressed(output_dir / "golden_intermediates.npz", **dumps)
    manifest = {
        "rounding_contract": ROUNDING_CONTRACT,
        "reference_commit": source_commit,
        "input_shape": list(q_input.shape),
        "pose_shape": list(pose.shape),
        "input_scale": float(metadata["activation_scales"]["encoder.input"]),
        "output_scale": float(metadata["activation_scales"]["head.fc3_out"]),
        "files": {name: {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
                  for name, data in files.items()},
    }
    (output_dir / "golden_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest
