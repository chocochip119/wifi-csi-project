from __future__ import annotations

import argparse
import csv
import json
import math
import random
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import numpy as np


POSE_FIELDS = [
    "left_shoulder_x",
    "left_shoulder_y",
    "right_shoulder_x",
    "right_shoulder_y",
    "left_elbow_x",
    "left_elbow_y",
    "right_elbow_x",
    "right_elbow_y",
    "left_wrist_x",
    "left_wrist_y",
    "right_wrist_x",
    "right_wrist_y",
    "left_hip_x",
    "left_hip_y",
    "right_hip_x",
    "right_hip_y",
    "left_knee_x",
    "left_knee_y",
    "right_knee_x",
    "right_knee_y",
    "left_ankle_x",
    "left_ankle_y",
    "right_ankle_x",
    "right_ankle_y",
]
ESP32_40MHZ_SIGNED_AXIS = list(range(-64, 64))


@dataclass
class FrameRecord:
    feature: np.ndarray
    label: np.ndarray
    width: int
    height: int
    trigger_seq: int


def _signed_axis_indices_to_positions(indices: list[int], axis: list[int]) -> np.ndarray:
    index_to_pos = {value: position for position, value in enumerate(axis)}
    return np.asarray([index_to_pos[index] for index in indices], dtype=np.int32)


ESP32_HT40_ABOVE_NONSTBC_LAYOUT = {
    "axis": ESP32_40MHZ_SIGNED_AXIS,
    "segments": [
        {
            "name": "lltf",
            "raw_indices": list(range(0, 64)),
        },
        {
            "name": "htltf",
            "raw_indices": list(range(0, 64)) + list(range(-64, 0)),
        },
    ],
}

for _segment in ESP32_HT40_ABOVE_NONSTBC_LAYOUT["segments"]:
    _segment["positions"] = _signed_axis_indices_to_positions(
        _segment["raw_indices"],
        ESP32_HT40_ABOVE_NONSTBC_LAYOUT["axis"],
    )
    _segment["length"] = len(_segment["raw_indices"])

ESP32_HTLTF_HT40_ABOVE_NONSTBC_LAYOUT = {
    "axis": ESP32_40MHZ_SIGNED_AXIS,
    "segment": {
        "name": "htltf",
        "raw_indices": list(range(0, 64)) + list(range(-64, 0)),
    },
}
ESP32_HTLTF_HT40_ABOVE_NONSTBC_LAYOUT["segment"]["positions"] = _signed_axis_indices_to_positions(
    ESP32_HTLTF_HT40_ABOVE_NONSTBC_LAYOUT["segment"]["raw_indices"],
    ESP32_HTLTF_HT40_ABOVE_NONSTBC_LAYOUT["axis"],
)
ESP32_HTLTF_HT40_ABOVE_NONSTBC_LAYOUT["segment"]["length"] = len(
    ESP32_HTLTF_HT40_ABOVE_NONSTBC_LAYOUT["segment"]["raw_indices"]
)


def _is_pose_complete(row: dict[str, str]) -> bool:
    return bool(row.get("frame_width")) and bool(row.get("frame_height")) and all(row.get(field) for field in POSE_FIELDS)


def _parse_label(row: dict[str, str]) -> tuple[np.ndarray, int, int]:
    width = int(row["frame_width"])
    height = int(row["frame_height"])
    values: list[float] = []
    for field in POSE_FIELDS:
        raw = row[field]
        coord = float(raw)
        if field.endswith("_x"):
            values.append(coord / max(width, 1))
        else:
            values.append(coord / max(height, 1))
    return np.asarray(values, dtype=np.float32), width, height


class InvalidCSI(ValueError):
    """An unusable CSI record that must not set an RX presence mask."""

    def __init__(self, reason: str, message: str) -> None:
        super().__init__(message)
        self.reason = reason


def _validate_pair_count(pair_count: int, subcarrier_remap: str) -> None:
    supported = {
        "none": None,
        "esp32_ht40_above_nonstbc": (64, 128, 192),
        "esp32_htltf_ht40_above_nonstbc": (128, 192),
    }
    if subcarrier_remap not in supported:
        raise ValueError(f"Unsupported subcarrier_remap={subcarrier_remap!r}")
    allowed = supported[subcarrier_remap]
    if pair_count <= 0 or (allowed is not None and pair_count not in allowed):
        raise InvalidCSI("length", f"Invalid IQ pair count {pair_count} for {subcarrier_remap}.")


def _decode_iq_pairs(
    raw_pairs: str,
    *,
    pair_count: int | None = None,
    subcarrier_remap: str = "none",
) -> list[list[int]]:
    if not isinstance(raw_pairs, str) or not raw_pairs.strip():
        raise InvalidCSI("empty", "CSI field is empty.")
    try:
        parsed = json.loads(raw_pairs)
    except ValueError as exc:
        raise InvalidCSI("format", "CSI is not valid JSON.") from exc
    if not isinstance(parsed, list):
        raise InvalidCSI("format", "CSI must be an array of [I, Q] pairs.")
    if not parsed:
        raise InvalidCSI("empty", "CSI pair array is empty.")
    _validate_pair_count(len(parsed), subcarrier_remap)
    if pair_count is not None and len(parsed) != pair_count:
        raise InvalidCSI("length", f"Expected {pair_count} IQ pairs, received {len(parsed)}.")
    for pair in parsed:
        if not isinstance(pair, list) or len(pair) != 2:
            raise InvalidCSI("format", "Each CSI entry must be an [I, Q] pair.")
        # bool is an int subclass, but is not a signed-byte CSI measurement.
        if any(type(value) is not int or not -128 <= value <= 127 for value in pair):
            raise InvalidCSI("value", "I/Q values must be signed INT8 integers (-128..127).")
    return parsed


def _infer_pair_count(
    files: list[Path],
    pattern_hint: str = "iq_pairs",
    subcarrier_remap: str = "none",
) -> int:
    for csv_path in files:
        with csv_path.open("r", encoding="utf-8-sig", newline="") as handle:
            reader = csv.DictReader(handle)
            for row in reader:
                raw_pairs = row.get(pattern_hint, "")
                try:
                    parsed = _decode_iq_pairs(raw_pairs, subcarrier_remap=subcarrier_remap)
                except InvalidCSI:
                    continue
                return len(parsed)
    raise ValueError("Could not infer CSI pair count: no valid signed INT8 CSI record found.")


def _normalize_feature_vector(values: np.ndarray, valid_length: int) -> np.ndarray:
    if valid_length <= 0:
        return values
    mean = float(values[:valid_length].mean())
    std = float(values[:valid_length].std())
    denom = std if std >= 1e-3 else 1.0
    values = (values - mean) / denom
    np.clip(values, -4.0, 4.0, out=values)
    return values


def _remap_esp32_ht40_above_nonstbc(values: np.ndarray) -> np.ndarray:
    if len(values) not in (64, 128, 192):
        raise ValueError(
            "esp32_ht40_above_nonstbc remap expects 64, 128, or 192 IQ pairs, "
            f"but received {len(values)}"
        )

    axis_length = len(ESP32_HT40_ABOVE_NONSTBC_LAYOUT["axis"])
    if len(values) == 64:
        enabled_segments = [ESP32_HT40_ABOVE_NONSTBC_LAYOUT["segments"][0]]
    elif len(values) == 128:
        enabled_segments = [ESP32_HT40_ABOVE_NONSTBC_LAYOUT["segments"][1]]
    else:
        enabled_segments = ESP32_HT40_ABOVE_NONSTBC_LAYOUT["segments"]

    remapped_parts: list[np.ndarray] = []
    cursor = 0
    for segment in enabled_segments:
        segment_length = int(segment["length"])
        raw_chunk = values[cursor : cursor + segment_length]
        cursor += segment_length

        axis_values = np.zeros(axis_length, dtype=np.float32)
        axis_values[segment["positions"]] = raw_chunk
        remapped_parts.append(axis_values)

    return np.concatenate(remapped_parts, axis=0)


def _remap_esp32_htltf_ht40_above_nonstbc(values: np.ndarray) -> np.ndarray:
    axis_length = len(ESP32_HTLTF_HT40_ABOVE_NONSTBC_LAYOUT["axis"])
    segment = ESP32_HTLTF_HT40_ABOVE_NONSTBC_LAYOUT["segment"]
    segment_length = int(segment["length"])

    if len(values) == segment_length:
        raw_chunk = values
    elif len(values) > segment_length:
        # Raw combined CSI stores LLTF first, then HT-LTF. Keep only HT-LTF.
        raw_chunk = values[-segment_length:]
    else:
        raise ValueError(
            "esp32_htltf_ht40_above_nonstbc remap expects at least 128 IQ pairs, "
            f"but received {len(values)}"
        )

    axis_values = np.zeros(axis_length, dtype=np.float32)
    axis_values[segment["positions"]] = raw_chunk
    return axis_values


def _parse_iq_pairs(raw_pairs: str, pair_count: int, subcarrier_remap: str) -> np.ndarray:
    _validate_pair_count(pair_count, subcarrier_remap)
    parsed = _decode_iq_pairs(raw_pairs, pair_count=pair_count, subcarrier_remap=subcarrier_remap)
    values = np.zeros(pair_count, dtype=np.float32)
    limit = pair_count
    for index in range(limit):
        i_val, q_val = parsed[index]
        power = float(i_val * i_val + q_val * q_val)
        values[index] = math.log1p(power)

    values = _normalize_feature_vector(values, valid_length=limit)
    if subcarrier_remap == "esp32_htltf_ht40_above_nonstbc":
        remapped = _remap_esp32_htltf_ht40_above_nonstbc(values[:limit].copy())
        remapped = _normalize_feature_vector(remapped, valid_length=len(remapped))
        return remapped
    if subcarrier_remap == "esp32_ht40_above_nonstbc":
        remapped = _remap_esp32_ht40_above_nonstbc(values[:limit].copy())
        remapped = _normalize_feature_vector(remapped, valid_length=len(remapped))
        return remapped
    return values


def _new_csi_quality(node_count: int) -> dict:
    return {
        "invalid_rx_rows": 0,
        "invalid_trigger_rows": 0,
        "rx": {
            str(index): {"accepted_rows": 0, "rejected_rows": 0, "missing_frames": 0, "reasons": {}}
            for index in range(node_count)
        },
    }


def _collect_grouped_files(input_dir: Path, pattern: str) -> dict[str, list[Path]]:
    grouped: dict[str, list[Path]] = {}
    for path in sorted(candidate for candidate in input_dir.rglob(pattern) if candidate.is_file()):
        parent = path.parent
        group_name = "." if parent == input_dir else parent.relative_to(input_dir).as_posix()
        grouped.setdefault(group_name, []).append(path)
    return grouped


def _split_group_files(
    files: list[Path],
    train_ratio: float,
    val_ratio: float,
    seed: int,
    test_files_per_group: int,
) -> dict[str, list[Path]]:
    if not 0.0 < train_ratio < 1.0:
        raise ValueError("train_ratio must be between 0 and 1.")
    if not 0.0 <= val_ratio < 1.0:
        raise ValueError("val_ratio must be between 0 and 1.")
    if test_files_per_group < 0:
        raise ValueError("test_files_per_group must be 0 or greater.")

    shuffled = list(files)
    random.Random(seed).shuffle(shuffled)
    test_count = min(test_files_per_group, len(shuffled))

    test_files = shuffled[:test_count]
    remaining = shuffled[test_count:]
    train_files: list[Path] = []
    val_files: list[Path] = []

    if remaining:
        train_weight = 1.0 if val_ratio == 0.0 else train_ratio / (train_ratio + val_ratio)
        train_count = int(len(remaining) * train_weight)
        if train_count <= 0:
            train_count = 1
        if train_count >= len(remaining) and len(remaining) > 1:
            train_count = len(remaining) - 1
        train_files = remaining[:train_count]
        val_files = remaining[train_count:]

    return {
        "train": sorted(train_files),
        "val": sorted(val_files),
        "test": sorted(test_files),
    }


def _split_grouped_files(
    grouped_files: dict[str, list[Path]],
    train_ratio: float,
    val_ratio: float,
    seed: int,
    test_files_per_group: int,
) -> tuple[dict[str, list[Path]], dict[str, dict[str, list[str]]]]:
    split_map: dict[str, list[Path]] = {"train": [], "val": [], "test": []}
    group_split_map: dict[str, dict[str, list[str]]] = {}

    for group_index, (group_name, files) in enumerate(sorted(grouped_files.items())):
        group_splits = _split_group_files(
            files,
            train_ratio=train_ratio,
            val_ratio=val_ratio,
            seed=seed + group_index,
            test_files_per_group=test_files_per_group,
        )
        group_split_map[group_name] = {}
        for split_name in ("train", "val", "test"):
            split_files = group_splits[split_name]
            split_map[split_name].extend(split_files)
            group_split_map[group_name][split_name] = [str(path) for path in split_files]

    return {split_name: sorted(files) for split_name, files in split_map.items()}, group_split_map


def _finalize_group(
    group_rows: list[dict[str, str]],
    node_count: int,
    pair_count: int,
    output_pair_count: int,
    subcarrier_remap: str,
    previous_base: np.ndarray | None,
    csi_quality: dict | None = None,
    trigger_seq: int | None = None,
) -> tuple[FrameRecord | None, np.ndarray | None]:
    if not group_rows:
        return None, previous_base

    pose_row = next((row for row in group_rows if _is_pose_complete(row)), None)
    if pose_row is None:
        return None, previous_base

    label, width, height = _parse_label(pose_row)
    base = np.zeros((node_count, output_pair_count), dtype=np.float32)
    mask = np.zeros(node_count, dtype=np.float32)
    has_valid_csi = False

    for row in group_rows:
        try:
            rx_index = int(row["rx_index"])
        except (KeyError, TypeError, ValueError):
            if csi_quality is not None:
                csi_quality["invalid_rx_rows"] += 1
            continue
        if rx_index < 0 or rx_index >= node_count:
            if csi_quality is not None:
                csi_quality["invalid_rx_rows"] += 1
            continue
        raw_pairs = row.get("iq_pairs", "")
        rx_quality = csi_quality["rx"][str(rx_index)] if csi_quality is not None else None
        try:
            candidate = _parse_iq_pairs(raw_pairs, pair_count, subcarrier_remap=subcarrier_remap)
            if candidate.shape != (output_pair_count,) or not np.isfinite(candidate).all():
                raise InvalidCSI("feature", "CSI preprocessing returned invalid feature shape or values.")
        except InvalidCSI as exc:
            if rx_quality is not None:
                rx_quality["rejected_rows"] += 1
                rx_quality["reasons"][exc.reason] = rx_quality["reasons"].get(exc.reason, 0) + 1
            continue
        base[rx_index] = candidate
        mask[rx_index] = 1.0
        has_valid_csi = True
        if rx_quality is not None:
            rx_quality["accepted_rows"] += 1

    if csi_quality is not None:
        for rx_index in range(node_count):
            if mask[rx_index] == 0:
                csi_quality["rx"][str(rx_index)]["missing_frames"] += 1

    if not has_valid_csi:
        return None, previous_base

    delta = np.zeros_like(base) if previous_base is None else base - previous_base
    mask_plane = np.repeat(mask[:, None], output_pair_count, axis=1)
    feature = np.concatenate([base, delta, mask_plane], axis=0)

    frame = FrameRecord(
        feature=feature.astype(np.float32, copy=False),
        label=label.astype(np.float32, copy=False),
        width=width,
        height=height,
        trigger_seq=int(group_rows[0]["trigger_seq"]) if trigger_seq is None else trigger_seq,
    )
    return frame, base


def _iter_file_frames(
    csv_path: Path,
    node_count: int,
    pair_count: int,
    output_pair_count: int,
    subcarrier_remap: str,
    csi_quality: dict | None = None,
) -> Iterable[FrameRecord]:
    previous_base: np.ndarray | None = None
    current_trigger: int | None = None
    group_rows: list[dict[str, str]] = []

    with csv_path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            raw_trigger = (row.get("trigger_seq") or "").strip()
            if not raw_trigger.isascii() or not raw_trigger.isdecimal() or len(raw_trigger) > 10:
                if csi_quality is not None:
                    csi_quality["invalid_trigger_rows"] += 1
                continue
            trigger_seq = int(raw_trigger)
            if trigger_seq > 0xFFFFFFFF:
                if csi_quality is not None:
                    csi_quality["invalid_trigger_rows"] += 1
                continue
            if current_trigger is None:
                current_trigger = trigger_seq
            if trigger_seq != current_trigger:
                frame, previous_base = _finalize_group(
                    group_rows,
                    node_count,
                    pair_count,
                    output_pair_count,
                    subcarrier_remap,
                    previous_base,
                    csi_quality,
                    trigger_seq=current_trigger,
                )
                if frame is not None:
                    yield frame
                group_rows = []
                current_trigger = trigger_seq
            group_rows.append(row)

    frame, _ = _finalize_group(
        group_rows,
        node_count,
        pair_count,
        output_pair_count,
        subcarrier_remap,
        previous_base,
        csi_quality,
        trigger_seq=current_trigger,
    )
    if frame is not None:
        yield frame


def _save_split(
    split_name: str,
    files: list[Path],
    output_dir: Path,
    node_count: int,
    pair_count: int,
    output_pair_count: int,
    subcarrier_remap: str,
) -> dict[str, object]:
    features: list[np.ndarray] = []
    labels: list[np.ndarray] = []
    file_ids: list[int] = []
    trigger_seq: list[int] = []
    frame_size: list[tuple[int, int]] = []
    csi_quality = _new_csi_quality(node_count)

    for file_index, csv_path in enumerate(files):
        print(f"[{split_name}] processing {csv_path.name}")
        frame_count_before = len(features)
        for frame in _iter_file_frames(
            csv_path,
            node_count=node_count,
            pair_count=pair_count,
            output_pair_count=output_pair_count,
            subcarrier_remap=subcarrier_remap,
            csi_quality=csi_quality,
        ):
            features.append(frame.feature)
            labels.append(frame.label)
            file_ids.append(file_index)
            trigger_seq.append(frame.trigger_seq)
            frame_size.append((frame.width, frame.height))
        print(f"[{split_name}] {csv_path.name}: +{len(features) - frame_count_before} frames")

    output_dir.mkdir(parents=True, exist_ok=True)
    split_path = output_dir / f"{split_name}.npz"
    if features:
        np.savez_compressed(
            split_path,
            features=np.stack(features).astype(np.float32),
            labels=np.stack(labels).astype(np.float32),
            file_ids=np.asarray(file_ids, dtype=np.int32),
            trigger_seq=np.asarray(trigger_seq, dtype=np.int64),
            frame_size=np.asarray(frame_size, dtype=np.int32),
        )
    else:
        np.savez_compressed(
            split_path,
            features=np.zeros((0, node_count * 3, output_pair_count), dtype=np.float32),
            labels=np.zeros((0, len(POSE_FIELDS)), dtype=np.float32),
            file_ids=np.zeros((0,), dtype=np.int32),
            trigger_seq=np.zeros((0,), dtype=np.int64),
            frame_size=np.zeros((0, 2), dtype=np.int32),
        )

    return {
        "files": len(files),
        "frames": len(features),
        "csi_quality": csi_quality,
    }


def prepare_dataset(
    input_dir: Path,
    output_dir: Path,
    pattern: str,
    node_count: int,
    pair_count: int,
    subcarrier_remap: str,
    train_ratio: float,
    val_ratio: float,
    seed: int,
    test_files_per_group: int = 1,
) -> None:
    grouped_files = _collect_grouped_files(input_dir, pattern)
    files = sorted(path for group_files in grouped_files.values() for path in group_files)
    if not files:
        raise FileNotFoundError(
            f"No CSV files found under {input_dir} or its subdirectories with pattern {pattern!r}."
        )

    if pair_count < 0:
        raise ValueError("pair_count must be 0 (auto) or a positive integer.")
    if pair_count == 0:
        pair_count = _infer_pair_count(files, subcarrier_remap=subcarrier_remap)
    _validate_pair_count(pair_count, subcarrier_remap)

    output_pair_count = pair_count
    axis_metadata: dict[str, object] = {
        "mode": subcarrier_remap,
        "raw_pair_count": pair_count,
        "output_pair_count": pair_count,
    }
    if subcarrier_remap == "esp32_htltf_ht40_above_nonstbc":
        output_pair_count = len(ESP32_HTLTF_HT40_ABOVE_NONSTBC_LAYOUT["axis"])
        axis_metadata = {
            "mode": subcarrier_remap,
            "raw_pair_count": pair_count,
            "output_pair_count": output_pair_count,
            "signed_axis": ESP32_HTLTF_HT40_ABOVE_NONSTBC_LAYOUT["axis"],
            "segments": [
                {
                    "name": str(ESP32_HTLTF_HT40_ABOVE_NONSTBC_LAYOUT["segment"]["name"]),
                    "raw_indices": list(ESP32_HTLTF_HT40_ABOVE_NONSTBC_LAYOUT["segment"]["raw_indices"]),
                }
            ],
        }
    elif subcarrier_remap == "esp32_ht40_above_nonstbc":
        # 64/128-pair inputs contain one LTF segment; 192 contains both.
        output_pair_count = len(ESP32_HT40_ABOVE_NONSTBC_LAYOUT["axis"]) * (2 if pair_count == 192 else 1)
        enabled_segments = ESP32_HT40_ABOVE_NONSTBC_LAYOUT["segments"]
        if pair_count == 64:
            enabled_segments = enabled_segments[:1]
        elif pair_count == 128:
            enabled_segments = enabled_segments[1:]
        axis_metadata = {
            "mode": subcarrier_remap,
            "raw_pair_count": pair_count,
            "output_pair_count": output_pair_count,
            "signed_axis": ESP32_HT40_ABOVE_NONSTBC_LAYOUT["axis"],
            "segments": [
                {
                    "name": str(segment["name"]),
                    "raw_indices": list(segment["raw_indices"]),
                }
                for segment in enabled_segments
            ],
        }

    split_map, group_split_map = _split_grouped_files(
        grouped_files,
        train_ratio=train_ratio,
        val_ratio=val_ratio,
        seed=seed,
        test_files_per_group=test_files_per_group,
    )
    output_dir.mkdir(parents=True, exist_ok=True)

    split_summary: dict[str, dict[str, object]] = {}
    for split_name, split_files in split_map.items():
        split_summary[split_name] = _save_split(
            split_name=split_name,
            files=split_files,
            output_dir=output_dir,
            node_count=node_count,
            pair_count=pair_count,
            output_pair_count=output_pair_count,
            subcarrier_remap=subcarrier_remap,
        )

    metadata = {
        "input_dir": str(input_dir),
        "pattern": pattern,
        "groups": {
            group_name: [str(path) for path in group_files]
            for group_name, group_files in sorted(grouped_files.items())
        },
        "split_strategy": {
            "mode": "per_parent_directory",
            "train_ratio": train_ratio,
            "val_ratio": val_ratio,
            "test_files_per_group": test_files_per_group,
        },
        "node_count": node_count,
        "pair_count": output_pair_count,
        "raw_pair_count": pair_count,
        "feature_channels": node_count * 3,
        "subcarrier_remap": subcarrier_remap,
        "subcarrier_axis": axis_metadata,
        "pose_fields": POSE_FIELDS,
        "csi_validation": {
            "iq_dtype": "signed_int8",
            "pair_count_policy": "exact",
            "invalid_rx_policy": "leave_base_and_mask_zero",
            "quality_scope": "trigger groups with complete pose labels; before forward_fill",
        },
        "splits": {
            split_name: {
                "files": [str(path) for path in split_map[split_name]],
                "summary": split_summary[split_name],
            }
            for split_name in ("train", "val", "test")
        },
        "group_splits": group_split_map,
    }
    (output_dir / "metadata.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    print(json.dumps(metadata, indent=2))


def main() -> int:
    parser = argparse.ArgumentParser(description="Prepare pose training NPZ caches from validated CSI CSV files.")
    parser.add_argument("--input-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, default=Path(__file__).resolve().parent / "data_cache")
    parser.add_argument("--pattern", default="sync_csi_pose*.csv")
    parser.add_argument("--node-count", type=int, default=3)
    parser.add_argument("--pair-count", type=int, default=0, help="0 infers the count from the first valid record.")
    parser.add_argument("--subcarrier-remap", choices=("none", "esp32_ht40_above_nonstbc", "esp32_htltf_ht40_above_nonstbc"),
                        default="esp32_htltf_ht40_above_nonstbc")
    parser.add_argument("--train-ratio", type=float, default=0.8)
    parser.add_argument("--val-ratio", type=float, default=0.2)
    parser.add_argument("--test-files-per-group", type=int, default=1)
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()
    if args.node_count <= 0:
        parser.error("--node-count must be positive")
    if args.pair_count < 0:
        parser.error("--pair-count must be 0 or positive")
    prepare_dataset(
        input_dir=args.input_dir.resolve(), output_dir=args.output_dir.resolve(),
        pattern=args.pattern, node_count=args.node_count, pair_count=args.pair_count,
        subcarrier_remap=args.subcarrier_remap, train_ratio=args.train_ratio,
        val_ratio=args.val_ratio, seed=args.seed, test_files_per_group=args.test_files_per_group,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
