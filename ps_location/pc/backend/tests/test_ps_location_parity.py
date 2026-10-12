"""PS C location engine (ps/src/loc_ridge.c) == PC live engine on the same TX USB stream.

One synthetic replay (STATUS/CYCLE/ACK with timestamps, including 4-RX cycles,
a CSI gap, a repeated trigger, ACK changes and a generation change) is fed to
both engines. Windows, labels, cycle counts and Ridge scores must match.
"""
from __future__ import annotations

from pathlib import Path
import shutil
import struct
import subprocess
import sys

import numpy as np
import pytest

from localization.labels import CLASSES
from localization.location_core import make_features
from localization.location_live import LiveInferenceEngine
from localization.location_model import predict_windows
from localization.portable_ridge import PortableRidge
from protocol import wise_protocol as wp

ROOT = Path(__file__).resolve().parents[3]
MODEL_NPZ = ROOT / "pc/backend/localization/models/localization/ridge_portable.npz"
sys.path.insert(0, str(ROOT / "ps" / "tools"))
import export_loc_model  # noqa: E402

STATUS_HEAD = struct.Struct("<8B7I6s2s")
STATUS_NODE = struct.Struct("<4B6sIII")
ACK = struct.Struct("<4BII64s")
MACS = [bytes([0x24, 0x6F, 0x28, 0x10, 0x20, 0x30 + i]) for i in range(5)]
SAVED_ORDER = [2, 0, 4, 1, 3]      # slot -> RX index, exercises the saved-order mapping


def status_payload(generation, uart_seq, channel=6):
    head = STATUS_HEAD.pack(1, channel, 1, 0x0F, 5, 5, 5, 5, 20000, 2000, generation, 0, uart_seq, 0, 0,
                            bytes.fromhex("246F28AABBCC"), b"\0\0")
    nodes = b"".join(STATUS_NODE.pack(slot, SAVED_ORDER[slot], slot, 0x07, MACS[slot], 0, 0, 0)
                     for slot in range(5))
    return head + nodes


def ack_payload(channel=6):
    return ACK.pack(1, 1, channel, 1, 20000, 2000, b"ok".ljust(64, b"\0"))


def cycle_payload(trigger, records):
    """records: one (rx, rssi, csi bytes or None) per active slot; None = RX timed out.
    TX USB layout: 32-byte head + 6-byte slot header + CSI per slot."""
    head = bytearray(32)
    struct.pack_into("<I", head, 4, trigger)
    received = sum(csi is not None for _, _, csi in records)
    head[28], head[29], head[30] = len(records), received, int(received != len(records))
    body = b"".join(struct.pack("<BBbBH", rx, int(csi is not None), rssi, 0, len(csi or b"")) + (csi or b"")
                    for rx, rssi, csi in records)
    return bytes(head) + body


def scenario(seed=7):
    rng = np.random.default_rng(seed)
    events, t, trigger, uart, generation = [], 5_000_000_000, 100, 0, 1
    next_status = t
    end = t + 32_000_000_000
    sigma = 20.0
    duplicate_done = gap_done = ack_ok_done = ack_change_done = gen_done = False
    while t < end:
        rel = (t - 5_000_000_000) / 1e9
        if t >= next_status:
            uart += 1
            if rel >= 26 and not gen_done:
                generation, gen_done = 2, True
            events.append((1, t, status_payload(generation, uart)))
            next_status += 1_000_000_000
            t += 1_000_000
        if rel >= 20 and not ack_ok_done:
            events.append((3, t, ack_payload())); ack_ok_done = True; t += 1_000_000
        if rel >= 22 and not ack_change_done:
            events.append((3, t, ack_payload(channel=11))); ack_change_done = True; t += 1_000_000
        if int(rel) % 4 == 0:
            sigma = float(rng.uniform(8, 40))
        records = []
        for rx in range(5):
            iq = np.clip(np.rint(rng.normal(0, sigma, 384)), -128, 127).astype(np.int8)
            missing = rx == 3 and 8.0 <= rel < 8.15   # RX3 timeout -> incomplete cycle
            records.append((rx, int(rng.integers(-75, -35)), None if missing else iq.tobytes()))
        rng.shuffle(records)
        events.append((2, t, cycle_payload(trigger, records)))
        if rel >= 16 and not duplicate_done:
            duplicate_done = True            # same trigger again -> chronology reject
        else:
            trigger += 1
        uart += 1
        if 28 <= rel < 31:
            t += int(rng.integers(220_000_000, 260_000_000))   # ~4 Hz -> too few cycles per window
        else:
            t += int(rng.integers(30_000_000, 55_000_000))
        if rel >= 12 and not gap_done:
            gap_done, t = True, t + 1_500_000_000
    return events


def write_replay(events, path):
    with open(path, "wb") as f:
        for kind, t, payload in events:
            f.write(struct.pack("<BQI", kind, t, len(payload)) + payload)


def python_run(events, model):
    scores, results = [], []

    def predictor(bundle, windows):
        x = make_features(windows, bundle["config"])
        scores.append(model.decision_function(x)[-1])
        return predict_windows(bundle, windows)

    engine = LiveInferenceEngine(model.as_studio_bundle(), identity_confirmed=True, enabled=True,
                                 predictor=predictor, on_prediction=results.append)
    uart = 0
    for kind, t, payload in events:
        if kind == 1:
            engine.set_status(wp.decode_status(payload), t)
        elif kind == 3:
            engine.handle_ack(wp.decode_ack(payload))
        else:
            uart += 1
            trigger = struct.unpack_from("<I", payload, 4)[0]
            cursor = 32
            for _ in range(payload[28]):
                rx, present, rssi, _, n = struct.unpack_from("<BBbBH", payload, cursor)
                csi = payload[cursor + 6:cursor + 6 + n]
                cursor += 6 + n
                if present:
                    engine.feed({"monotonic_ns": t, "uart_seq": uart, "trigger_seq": trigger, "rx_index": rx,
                                 "rssi": rssi, "csi_len": n, "csi_raw_hex": csi.hex(),
                                 "active_nodes": payload[28], "received_nodes": payload[29]}, t)
                    engine.tick(t)
    # Map the estimator-ordered scores to wire class codes.
    order = [CLASSES.index(c) for c in model.classes_]
    coded = []
    for row in scores:
        out = np.zeros(len(CLASSES))
        out[order] = row
        coded.append(out)
    return results, coded


@pytest.fixture(scope="module")
def replay_binary(tmp_path_factory):
    gcc = shutil.which("gcc")
    if gcc is None:
        pytest.skip("gcc not available")
    out = tmp_path_factory.mktemp("loc") / "loc_ridge_replay"
    subprocess.run([gcc, "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-I" + str(ROOT / "ps/include"),
                    str(ROOT / "ps/src/loc_ridge.c"), str(ROOT / "ps/tests/loc_ridge_replay.c"), "-lm",
                    "-o", str(out)], check=True)
    return out


def test_exported_model_matches_committed_binary():
    built = export_loc_model.build(PortableRidge(MODEL_NPZ))
    assert built == (ROOT / "ps/models/loc_ridge_rx5.bin").read_bytes()


def test_c_engine_matches_pc_live_engine(replay_binary, tmp_path):
    model = PortableRidge(MODEL_NPZ)
    events = scenario()
    write_replay(events, tmp_path / "replay.bin")
    proc = subprocess.run([str(replay_binary), str(ROOT / "ps/models/loc_ridge_rx5.bin"),
                           str(tmp_path / "replay.bin")], capture_output=True, text=True, check=True)
    lines = proc.stdout.split("\n")
    c_rows = [line.split() for line in lines if line.startswith("R ")]
    stats = dict(item.split("=") for item in next(l for l in lines if l.startswith("S ")).split()[1:])

    py_results, py_scores = python_run(events, model)

    # The scenario must exercise every reset path, not just steady state.
    assert int(stats["chronology"]) >= 1 and int(stats["gaps"]) >= 1 and int(stats["invalid"]) >= 1
    assert int(stats["ack_resets"]) >= 1 and int(stats["short"]) >= 1
    assert len(py_results) >= 30
    assert len(c_rows) == len(py_results) == len(py_scores)
    for c, py, score in zip(c_rows, py_results, py_scores):
        code, occupied, cycles = int(c[3]), int(c[4]), int(c[5])
        x, y, start_us, end_us = int(c[6]), int(c[7]), int(c[8]), int(c[9])
        assert CLASSES[code] == py["point_id"]
        assert bool(occupied) == py["occupied"]
        assert cycles == py["window_cycles"]
        assert abs(start_us * 1000 - py["window_start_ns"]) <= 1000
        assert abs(end_us * 1000 - py["window_end_ns"]) <= 1000
        if py["representative_x_cm"] is None:
            assert x == y == -32768
        else:
            assert (x, y) == (py["representative_x_cm"], py["representative_y_cm"])
        np.testing.assert_allclose(np.array(c[10:], dtype=float), score, rtol=1e-5, atol=1e-4)
