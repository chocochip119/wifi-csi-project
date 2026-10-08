#!/usr/bin/env python3
"""Fake PS for PC-side testing: recorded location CSV -> wire-v2 packets on TCP 5000.

    python pc/backend/tools/replay_ps_server.py a.csv [b.csv ...] [--port 5000] [--speed 1]

Each accepted client gets the next CSV, then the connection closes (exercises the
PC reconnect path); --loop repeats the list. STATUS is SYNTHETIC (placeholder
MACs 02:00:00:00:00:0x, channel 6 HT40+) and only satisfies the PC readiness
check. Not a PS implementation and not a model-accuracy test. Pose (5001) is not sent.
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


class ReplayServer:
    """Connection k replays sessions[k] in real time (x speed), STATUS every status_every_s."""

    def __init__(self, sessions, *, host="127.0.0.1", port=0, speed=1.0, status_every_s=2.0, loop=False):
        self.sessions, self.speed, self.status_every_s, self.loop = sessions, speed, status_every_s, loop
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

        send(wp.TYPE_STATUS, synthetic_status(), ps0)
        next_status = self.status_every_s
        for item in cycles:
            rel_s = (item.ps_us - base) / 1e6 / self.speed
            delay = rel_s - (time.perf_counter() - clock0)
            if delay > 0:
                time.sleep(delay)
            if rel_s >= next_status:
                send(wp.TYPE_STATUS, synthetic_status(), ps0 + int(rel_s * 1e6))
                next_status += self.status_every_s
            send(wp.TYPE_CSI, wp.encode_csi(item.cycle), ps0 + int(rel_s * 1e6))
        return {"packets": seq, "cycles": len(cycles)}


def main():
    parser = argparse.ArgumentParser(description="Replay location CSVs as a fake PS on TCP")
    parser.add_argument("csv", nargs="+", type=Path)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=5000)
    parser.add_argument("--speed", type=float, default=1.0)
    parser.add_argument("--loop", action="store_true", help="repeat the CSV list for new connections")
    args = parser.parse_args()
    sessions = [load_csv_cycles(p) for p in args.csv]
    server = ReplayServer(sessions, host=args.host, port=args.port, speed=args.speed, loop=args.loop).start()
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
