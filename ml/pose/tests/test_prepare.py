"""Regression tests for raw CSI validation and the resulting presence masks.

Runs on a fresh checkout with only numpy and pytest; no training package needed.
"""

import csv
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

import numpy as np
import pytest


PREPARE_PATH = Path(__file__).resolve().parents[1] / "prepare.py"
SPEC = importlib.util.spec_from_file_location("pose_prepare_under_test", PREPARE_PATH)
prepare = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = prepare
SPEC.loader.exec_module(prepare)
MODE = "esp32_htltf_ht40_above_nonstbc"


def iq_json(count=192):
    return json.dumps([[(index % 256) - 128, ((index * 3) % 256) - 128] for index in range(count)])


def row(rx=0, raw=None, trigger=0):
    return {
        "trigger_seq": str(trigger), "rx_index": str(rx),
        "iq_pairs": iq_json() if raw is None else raw,
        "frame_width": "640", "frame_height": "480",
        **{field: "320" if field.endswith("_x") else "240" for field in prepare.POSE_FIELDS},
    }


def write_csv(path, rows):
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(row()))
        writer.writeheader()
        writer.writerows(rows)


def finalize(rows, quality=None, previous=None):
    return prepare._finalize_group(rows, 3, 192, 128, MODE, previous, quality)


@pytest.mark.parametrize("raw, reason", [
    ("", "empty"), ("   ", "empty"), ("[]", "empty"),
    ("null", "format"), ("{}", "format"), ("false", "format"),
    ("12", "format"), ('"CSI"', "format"), ("[", "format"),
    ("[0]", "format"), ("[[1]]", "format"), ("[[1,2,3]]", "format"),
    ("[[null,0]]", "value"), ('[["1",0]]', "value"),
    ("[[true,0]]", "value"), ("[[1.0,0]]", "value"),
    ("[[128,0]]", "value"), ("[[-129,0]]", "value"),
    ("[[NaN,0]]", "value"), ("[[Infinity,0]]", "value"),
])
def test_invalid_payloads_raise_categorized_value_error(raw, reason):
    with pytest.raises(prepare.InvalidCSI) as caught:
        prepare._decode_iq_pairs(raw)
    assert isinstance(caught.value, ValueError)
    assert caught.value.reason == reason


@pytest.mark.parametrize("count", [64, 127, 129, 191, 193, 256])
def test_default_remap_rejects_unsupported_lengths(count):
    with pytest.raises(prepare.InvalidCSI, match="pair count"):
        prepare._parse_iq_pairs(iq_json(count), count, MODE)


@pytest.mark.parametrize("received, expected", [(128, 192), (192, 128)])
def test_supported_but_mismatched_lengths_are_not_padded_or_truncated(received, expected):
    with pytest.raises(prepare.InvalidCSI, match="Expected"):
        prepare._parse_iq_pairs(iq_json(received), expected, MODE)


@pytest.mark.parametrize("count", [128, 192])
def test_valid_signed_byte_features_remain_finite(count):
    features = prepare._parse_iq_pairs(iq_json(count), count, MODE)
    assert features.shape == (128,)
    assert features.dtype == np.float32
    assert np.isfinite(features).all()
    assert np.abs(features).max() <= 4


def test_empty_rx_and_absent_rx_stay_masked_but_measured_zero_is_valid():
    quality = prepare._new_csi_quality(3)
    zeros = json.dumps([[0, 0]] * 192)
    frame, base = finalize([row(0, zeros), row(1, "[]")], quality)
    np.testing.assert_array_equal(base, 0)
    np.testing.assert_array_equal(frame.feature[6], 1)
    np.testing.assert_array_equal(frame.feature[7:9], 0)
    assert quality["rx"]["0"]["accepted_rows"] == 1
    assert quality["rx"]["0"]["missing_frames"] == 0
    assert quality["rx"]["1"]["reasons"] == {"empty": 1}
    assert quality["rx"]["1"]["missing_frames"] == 1
    assert quality["rx"]["2"]["missing_frames"] == 1
    assert quality["rx"]["2"]["rejected_rows"] == 0


def test_invalid_payloads_do_not_abort_other_receivers():
    bad_pairs = [[0, 0]] * 192
    bad_pairs[10] = ["bad", 0]
    quality = prepare._new_csi_quality(3)
    frame, _ = finalize([row(0, json.dumps(bad_pairs)), row(1), row(2, "null")], quality)
    np.testing.assert_array_equal(frame.feature[6:, 0], [0, 1, 0])
    assert quality["rx"]["0"]["reasons"] == {"value": 1}
    assert quality["rx"]["2"]["reasons"] == {"format": 1}


def test_rejected_duplicate_does_not_overwrite_a_valid_receiver():
    frame, _ = finalize([row(0), row(0, "[]")])
    expected = prepare._parse_iq_pairs(iq_json(), 192, MODE)
    np.testing.assert_array_equal(frame.feature[0], expected)
    np.testing.assert_array_equal(frame.feature[6], 1)


def test_all_invalid_receivers_skip_frame_and_preserve_previous_base():
    previous = np.ones((3, 128), dtype=np.float32)
    frame, returned = finalize([row(0, "[]"), row(1, "null")], previous=previous)
    assert frame is None
    assert returned is previous


@pytest.mark.parametrize("invalid", [np.full(128, np.nan), np.full(128, np.inf), np.zeros(127)])
def test_invalid_feature_output_cannot_set_presence_mask(monkeypatch, invalid):
    monkeypatch.setattr(prepare, "_parse_iq_pairs", lambda *args, **kwargs: invalid)
    quality = prepare._new_csi_quality(3)
    frame, _ = finalize([row()], quality)
    assert frame is None
    assert quality["rx"]["0"]["reasons"] == {"feature": 1}


def test_pair_count_inference_skips_malformed_and_incompatible_records(tmp_path):
    path = tmp_path / "sync_csi_pose.csv"
    write_csv(path, [row(raw=raw) for raw in ["[]", "{", "null", "[[0, 0]]", iq_json()]])
    assert prepare._infer_pair_count([path], subcarrier_remap=MODE) == 192


def test_pair_count_inference_rejects_no_valid_data(tmp_path):
    path = tmp_path / "sync_csi_pose.csv"
    write_csv(path, [row(raw="[]"), row(raw="null")])
    with pytest.raises(ValueError, match="no valid"):
        prepare._infer_pair_count([path], subcarrier_remap=MODE)


@pytest.mark.parametrize("bad_trigger", ["broken", "", "12.0", "-1", "4294967296", "1_0", "１２"])
def test_bad_trigger_rows_are_counted_and_do_not_abort_csv(tmp_path, bad_trigger):
    path = tmp_path / "sync_csi_pose.csv"
    write_csv(path, [row(trigger=0), row(trigger=bad_trigger), row(trigger=1)])
    quality = prepare._new_csi_quality(3)
    frames = list(prepare._iter_file_frames(path, 3, 192, 128, MODE, quality))
    assert [frame.trigger_seq for frame in frames] == [0, 1]
    assert quality["invalid_trigger_rows"] == 1
    assert quality["rx"]["0"]["accepted_rows"] == 2


def test_trigger_grouping_uses_parsed_uint32(tmp_path):
    path = tmp_path / "sync_csi_pose.csv"
    write_csv(path, [row(0, trigger="012"), row(1, trigger="12"), row(2, trigger="4294967295")])
    frames = list(prepare._iter_file_frames(path, 3, 192, 128, MODE))
    assert [frame.trigger_seq for frame in frames] == [12, 4294967295]
    np.testing.assert_array_equal(frames[0].feature[6:, 0], [1, 1, 0])


@pytest.mark.parametrize("count, output_count", [(64, 128), (128, 128), (192, 256)])
def test_combined_remap_declares_actual_segment_shape(tmp_path, count, output_count):
    input_dir = tmp_path / "input"
    input_dir.mkdir()
    write_csv(input_dir / "sync_csi_pose.csv", [row(raw=iq_json(count))])
    output_dir = tmp_path / "cache"
    prepare.prepare_dataset(input_dir, output_dir, "*.csv", 3, count,
                            "esp32_ht40_above_nonstbc", 0.8, 0.2, 42, 0)
    with np.load(output_dir / "train.npz") as cache:
        assert cache["features"].shape == (1, 9, output_count)
        np.testing.assert_array_equal(cache["features"][0, 6], 1)
    metadata = json.loads((output_dir / "metadata.json").read_text())
    assert metadata["pair_count"] == output_count
    assert len(metadata["subcarrier_axis"]["segments"]) == (2 if count == 192 else 1)


def test_cli_exports_masks_labels_and_quality_for_each_split(tmp_path):
    input_dir = tmp_path / "captures"
    input_dir.mkdir()
    for file_index in range(3):
        rows = []
        for trigger in range(12):
            rows.append(row(0, trigger=trigger))
            rows.append(row(1, "[]" if trigger == 2 else iq_json(), trigger))
            if trigger != 3:
                rows.append(row(2, trigger=trigger))
        write_csv(input_dir / f"sync_csi_pose_{file_index}.csv", rows)
    output_dir = tmp_path / "cache"
    result = subprocess.run([sys.executable, str(PREPARE_PATH), "--input-dir", str(input_dir),
                             "--output-dir", str(output_dir)], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    metadata = json.loads((output_dir / "metadata.json").read_text())
    assert metadata["raw_pair_count"] == 192
    assert metadata["pair_count"] == 128
    assert metadata["csi_validation"]["pair_count_policy"] == "exact"
    for split in ("train", "val", "test"):
        with np.load(output_dir / f"{split}.npz") as cache:
            assert cache["features"].shape == (12, 9, 128)
            np.testing.assert_array_equal(cache["labels"], np.full((12, 24), 0.5))
            np.testing.assert_array_equal(cache["features"][2, 7], 0)
            np.testing.assert_array_equal(cache["features"][3, 8], 0)
            np.testing.assert_array_equal(cache["features"][:, 6], 1)
        quality = metadata["splits"][split]["summary"]["csi_quality"]
        assert quality["rx"]["1"]["accepted_rows"] == 11
        assert quality["rx"]["1"]["reasons"] == {"empty": 1}
        assert quality["rx"]["2"]["missing_frames"] == 1
