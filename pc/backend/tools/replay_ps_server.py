#!/usr/bin/env python3
"""Fake PS for PC-side testing: recorded location CSV -> wire-v2 packets on TCP 5000.

    python pc/backend/tools/replay_ps_server.py a.csv [b.csv ...] [--port 5000] [--speed 1] [--forward-csi]

Each accepted client gets the next CSV, then the connection closes (exercises the
PC reconnect path); --loop repeats the list. STATUS is SYNTHETIC (placeholder
MACs 02:00:00:00:00:0x, channel 6 HT40+) and only satisfies the PC readiness
check. Location (type 5) is computed here with the PC Python live engine, which
tests/test_ps_location_parity.py checks against the PS C engine. Raw CSI is sent
only with --forward-csi, like WISE_FORWARD_CSI=1 on the PS. Pose is not sent.
CSV columns used: csi_host_time, trigger_seq, rx_index, rssi, csi_len, iq_pairs.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
from pathlib import Path
import socket
import sys
import threading
import time

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from protocol import wise_protocol as wp  # noqa: E402
from localization.labels import CLASSES  # noqa: E402
from localization.location_core import make_features  # noqa: E402
from localization.location_live import LiveInferenceEngine  # noqa: E402
from localization.location_model import predict_windows  # noqa: E402
from localization.portable_ridge import PortableRidge  # noqa: E402

DEFAULT_MODEL = Path(__file__).resolve().parents[1] / "localization" / "models" / "localization" / "ridge_portable.npz"


@dataclass
class TimedCycle:
    ps_us: int
    cycle: wp.CsiCycle


def load_csv_cycles(path: Path, ps_start_us: int = 1_000_000) -> list[TimedCycle]:
    """Group a recorded CSV by trigger_seq. Missing RX stays valid=0 (never filled)."""
    frame = pd.read_csv(path, encoding="utf-8-sig", usecols=["csi_host_time", "trigger_seq", "rx_index",
                                                             "rssi", "csi_len", "iq_pairs"])
    stamp = pd.to_datetime(frame["csi_host_time"], format="mixed", utc=True)
    frame["t_us"] = ((stamp - stamp.min()).dt.total_seconds() * 1e6).round().astype(np.int64)
    cycles = []
    for seq, group in frame.groupby("trigger_seq", sort=False):
        by_rx = {}
        for row in group.itertuples(index=False):
            raw = np.asarray(json.loads(row.iq_pairs), dtype=np.int8).reshape(-1).tobytes()
            if len(raw) != int(row.csi_len):
                raise ValueError(f"{path.name}: iq_pairs length != csi_len at trigger {seq}")
            by_rx[int(row.rx_index)] = wp.RxRecord(int(row.rx_index), True, int(row.rssi), raw)
        records = [by_rx.get(rx, wp.RxRecord(rx, False, 0, b"")) for rx in range(5)]
        cycle = wp.CsiCycle(int(seq), int(seq) & 0xFFFFFFFF, 5, sum(r.valid for r in records), False, records)
        cycles.append(TimedCycle(ps_start_us + int(group["t_us"].min()), cycle))
    cycles.sort(key=lambda c: c.ps_us)
    # CSV host time is 1 ms; USB bursts share a tick. A live PS (us clock) sees
    # distinct times, so add the rank inside one tick in microseconds.
    previous, rank = None, 0
    for item in cycles:
        rank = rank + 1 if item.ps_us == previous else 0
        previous = item.ps_us
        item.ps_us += rank
    return cycles


def synthetic_status(generation: int = 1) -> bytes:
    """Placeholder TX STATUS (running, 5 RX live). MACs/channel are NOT real devices."""
    head = wp.STATUS_HEADER.pack(1, 6, 1, 7, 5, 5, 5, 5, 5000, 1000, generation, 0, 0, 0, 0,
                                 bytes.fromhex("02000000ff00"), b"\0\0")
    nodes = b"".join(wp.STATUS_NODE.pack(i, i, i, 0x07, bytes.fromhex(f"0200000000{i:02x}"), 0, 0, 0)
                     for i in range(5))
    return head + nodes


class LocationStandIn:
    """PS location engine stand-in: same window/Ridge path as ps/src/loc_ridge.c."""

    def __init__(self, model: PortableRidge):
        self.model, self.results, self._scores, self.window_id = model, [], [], 0
        self.engine = LiveInferenceEngine(model.as_studio_bundle(), identity_confirmed=True, enabled=True,
                                          predictor=self._predict, on_prediction=self._done)

    def _predict(self, bundle, windows):
        self._scores.append(self.model.decision_function(make_features(windows, bundle["config"]))[-1])
        return predict_windows(bundle, windows)

    def _done(self, prediction):
        scores = [0.0] * len(CLASSES)
        for label, value in zip(self.model.classes_, self._scores.pop()):
            scores[CLASSES.index(label)] = float(value)
        self.window_id += 1
        self.results.append(wp.LocationResult(
            self.window_id, 0, int(prediction.get("infer_ms", 0) * 1000), prediction["point_id"],
            prediction["occupied"], prediction["window_cycles"], prediction["representative_x_cm"],
            prediction["representative_y_cm"], prediction["window_start_ns"] // 1000,
            prediction["window_end_ns"] // 1000, tuple(scores)))

    def status(self, payload: bytes, t_ns: int):
        self.engine.set_status(wp.decode_status(payload), t_ns)

    def cycle(self, cycle: wp.CsiCycle, t_ns: int):
        for record in cycle.records:
            if record.valid:
                self.engine.feed({"monotonic_ns": t_ns, "uart_seq": cycle.uart_seq,
                                  "trigger_seq": cycle.trigger_seq, "rx_index": record.rx_id,
                                  "rssi": record.rssi, "csi_len": len(record.csi),
                                  "csi_raw_hex": record.csi.hex(), "active_nodes": cycle.active_nodes,
                                  "received_nodes": cycle.received_nodes}, t_ns)
                self.engine.tick(t_ns)
        done, self.results = self.results, []
        for result in done:
            result.end_trigger_seq = cycle.trigger_seq
        return done


class ReplayServer:
    """Connection k replays sessions[k] in real time (x speed), STATUS every status_every_s."""

    def __init__(self, sessions, *, host="127.0.0.1", port=0, speed=1.0, status_every_s=2.0, loop=False,
                 model_path=DEFAULT_MODEL, forward_csi=False):
        self.sessions, self.speed, self.status_every_s, self.loop = sessions, speed, status_every_s, loop
        self.model = PortableRidge(model_path)
        self.forward_csi = forward_csi
        self.listener = socket.create_server((host, port))
        self.address = self.listener.getsockname()
        self.sent = []
        self.thread = threading.Thread(target=self._run, name="fake-ps", daemon=True)

    def start(self):
        self.thread.start()
        return self

    def _run(self):
        index = 0
        while index < len(self.sessions):
            conn, _ = self.listener.accept()
            with conn:
                try:
                    self.sent.append(self._serve(conn, self.sessions[index]))
                except OSError as exc:      # PC disconnected
                    self.sent.append({"error": str(exc)})
            index += 1
            if self.loop and index == len(self.sessions):
                index = 0
        self.listener.close()

    def _serve(self, conn, cycles):
        seq, base = 0, cycles[0].ps_us
        clock0 = time.perf_counter()
        ps0 = int(time.monotonic_ns() // 1000)     # this process plays the PS CLOCK_MONOTONIC

        def send(kind, payload, ts_us):
            nonlocal seq
            conn.sendall(wp.frame(kind, payload, seq, ts_us))
            seq += 1

        location = LocationStandIn(self.model)
        locations = 0
        send(wp.TYPE_STATUS, synthetic_status(), ps0)
        location.status(synthetic_status(), ps0 * 1000)
        next_status = self.status_every_s
        for item in cycles:
            rel_s = (item.ps_us - base) / 1e6 / self.speed
            delay = rel_s - (time.perf_counter() - clock0)
            if delay > 0:
                time.sleep(delay)
            now_us = ps0 + int(rel_s * 1e6)
            if rel_s >= next_status:
                send(wp.TYPE_STATUS, synthetic_status(), now_us)
                location.status(synthetic_status(), now_us * 1000)
                next_status += self.status_every_s
            if self.forward_csi:
                send(wp.TYPE_CSI, wp.encode_csi(item.cycle), now_us)
            for result in location.cycle(item.cycle, now_us * 1000 + 1):
                send(wp.TYPE_LOCATION, wp.encode_location(result), now_us)
                locations += 1
        return {"packets": seq, "cycles": len(cycles), "locations": locations}


def main():
    parser = argparse.ArgumentParser(description="Replay location CSVs as a fake PS on TCP")
    parser.add_argument("csv", nargs="+", type=Path)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=5000)
    parser.add_argument("--speed", type=float, default=1.0)
    parser.add_argument("--loop", action="store_true", help="repeat the CSV list for new connections")
    parser.add_argument("--model", type=Path, default=DEFAULT_MODEL, help="Portable Ridge .npz for location")
    parser.add_argument("--forward-csi", action="store_true", help="also send raw CSI (type 1)")
    args = parser.parse_args()
    sessions = [load_csv_cycles(p) for p in args.csv]
    server = ReplayServer(sessions, host=args.host, port=args.port, speed=args.speed, loop=args.loop,
                          model_path=args.model, forward_csi=args.forward_csi).start()
    print(f"fake PS listening on {server.address[0]}:{server.address[1]} "
          f"({len(sessions)} CSV, synthetic STATUS). Ctrl+C to stop.", flush=True)
    try:
        while server.thread.is_alive():
            server.thread.join(0.5)
    except KeyboardInterrupt:
        pass
    print(json.dumps(server.sent))


if __name__ == "__main__":
    main()
