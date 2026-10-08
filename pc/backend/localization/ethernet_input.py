"""PC-side TCP receiver for the PS bypass (protocol v1.1, wire version 2).

Feeds the packaged 11-class CSI live engine using rows with the same
dict shape as the original serial input.

Time: the PS ``timestamp_us`` (TX cycle parse time) builds windows; it is put
on the PC ``perf_counter_ns`` axis with offset = min(PC receive - PS time) per
connection, so mapped times never lie in the PC future and keep PS spacing.
"""
from __future__ import annotations

import copy
from pathlib import Path
import socket
import threading
import time
from typing import Any, Callable

from protocol import wise_protocol as wp

HERE = Path(__file__).resolve().parent
DEFAULT_MODEL = HERE / "models" / "ridge_portable.npz"


class StreamDecoder:
    """Incremental TCP framing: exactly 24 header bytes, then payload_size bytes."""

    def __init__(self) -> None:
        self.buffer = bytearray()

    def feed(self, data: bytes) -> list[tuple[wp.Header, bytes]]:
        self.buffer += data
        packets = []
        while len(self.buffer) >= wp.HEADER_SIZE:
            header = wp.unpack_header(bytes(self.buffer[:wp.HEADER_SIZE]))
            total = wp.HEADER_SIZE + header.payload_size
            if len(self.buffer) < total:
                break
            packets.append((header, bytes(self.buffer[wp.HEADER_SIZE:total])))
            del self.buffer[:total]
        return packets


class ClockMapper:
    """PS microseconds -> PC perf_counter_ns, offset = running min latency.

    The engine rejects a cycle time that repeats/regresses or precedes the
    STATUS it accepted, so the output is strictly increasing, above the last
    STATUS floor, and never later than the packet's own PC time (now_ns).
    A falling offset (early in a connection) only compresses a few cycles.
    """

    def __init__(self) -> None:
        self.reset()

    def reset(self) -> None:
        self.offset_ns: int | None = None
        self.last_ns: int | None = None
        self.floor_ns = 0

    def set_floor(self, ns: int) -> None:
        self.floor_ns = max(self.floor_ns, int(ns))

    def map(self, ps_us: int, now_ns: int) -> int:
        ps_ns, now_ns = int(ps_us) * 1000, int(now_ns)
        candidate = now_ns - ps_ns
        if self.offset_ns is None or candidate < self.offset_ns:
            self.offset_ns = candidate
        mapped = max(ps_ns + self.offset_ns, self.floor_ns + 1,
                     -1 if self.last_ns is None else self.last_ns + 1)
        mapped = min(mapped, now_ns)
        self.last_ns = mapped
        return mapped


def cycle_rows(cycle: wp.CsiCycle, monotonic_ns: int, wall_time_s: float) -> list[dict[str, Any]]:
    """Present RX only, like the USB reference parser; missing RX is never filled."""
    return [{
        "wall_time_s": wall_time_s,
        "monotonic_ns": int(monotonic_ns),
        "rx_index": record.rx_id,
        "trigger_seq": cycle.trigger_seq,
        "uart_seq": cycle.uart_seq,
        "rssi": record.rssi,
        "csi_len": len(record.csi),
        "csi_raw_hex": record.csi.hex(),
        "active_nodes": cycle.active_nodes,
        "received_nodes": cycle.received_nodes,
        "timeout_fired": int(cycle.timeout_fired),
    } for record in cycle.records if record.valid]


class EthernetInput:
    """TCP client for port 5000 (CSI/STATUS/ACK). Reconnects until stop()."""

    def __init__(self, host: str, port: int, on_sample: Callable[[dict], None],
                 on_event: Callable[[str, Any], None], *, retry_s: float = 1.0,
                 connect_timeout_s: float = 2.0) -> None:
        # STATUS/ACK are decoded by wise_protocol; no Studio/pyserial import here.
        self.host, self.port = host, int(port)
        self.on_sample, self.on_event = on_sample, on_event
        self.retry_s, self.connect_timeout_s = retry_s, connect_timeout_s
        self.clock = ClockMapper()
        self._stop = threading.Event()
        self._sock: socket.socket | None = None
        self._thread: threading.Thread | None = None
        self._lock = threading.Lock()
        self._connected = False
        self._last_error: str | None = None
        self._last_status: dict | None = None
        self._last_status_received_ns: int | None = None
        self._counts = {"connections": 0, "csi_packets": 0, "status_packets": 0, "ack_packets": 0,
                        "pose_packets_ignored": 0, "sequence_gaps": 0, "protocol_errors": 0}
        self._last_sequence: int | None = None
        self._rx_rows: dict[int, int] = {}
        self._csi_lengths: dict[int, int] = {}

    def start(self) -> None:
        if self._thread is not None:
            raise RuntimeError("EthernetInput is single-use; create a new input.")
        self._thread = threading.Thread(target=self._run, name="wise-csi-5000", daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        sock = self._sock
        if sock is not None:
            try:
                sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            sock.close()
        if self._thread is not None and threading.current_thread() is not self._thread:
            self._thread.join(timeout=2.0)

    def snapshot(self) -> dict[str, Any]:
        with self._lock:
            return {"port": f"{self.host}:{self.port}", "connected": self._connected,
                    "status": copy.deepcopy(self._last_status),
                    "status_received_ns": self._last_status_received_ns,
                    "last_error": self._last_error,
                    "counts": dict(self._counts), "received_rows_by_rx": dict(self._rx_rows),
                    "csi_len_by_rx": dict(self._csi_lengths), "clock_offset_ns": self.clock.offset_ns,
                    "timestamp_basis": "PS CLOCK_MONOTONIC at TX cycle parse, offset to PC perf_counter_ns"}

    def _emit(self, kind: str, payload: Any) -> None:
        try:
            self.on_event(kind, payload)
        except Exception:
            pass

    def _run(self) -> None:
        while not self._stop.is_set():
            try:
                sock = socket.create_connection((self.host, self.port), timeout=self.connect_timeout_s)
            except OSError as exc:
                with self._lock:
                    self._last_error = f"connect failed: {exc}"
                self._stop.wait(self.retry_s)
                continue
            sock.settimeout(0.5)
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            self._sock = sock
            if self._stop.is_set():
                sock.close()
                self._sock = None
                break
            self.clock.reset()
            self._last_sequence = None
            with self._lock:
                self._connected, self._last_error = True, None
                self._counts["connections"] += 1
            self._emit("log", f"Connected to {self.host}:{self.port}")
            reason = self._serve(sock)
            sock.close()
            self._sock = None
            with self._lock:
                self._connected = False
                self._last_status = None
                self._last_status_received_ns = None
                if reason and not self._stop.is_set():
                    self._last_error = reason
            if not self._stop.is_set():
                # Worker drops buffered windows and waits for a new STATUS.
                self._emit("closed", reason or "PS connection closed")
                self._stop.wait(self.retry_s)

    def _serve(self, sock: socket.socket) -> str | None:
        decoder = StreamDecoder()
        while not self._stop.is_set():
            try:
                data = sock.recv(65536)
            except socket.timeout:
                continue
            except OSError as exc:
                return f"socket error: {exc}"
            if not data:
                return "PS closed the connection"
            try:
                for header, payload in decoder.feed(data):
                    # Per packet, not per recv() chunk: one chunk can hold many cycles.
                    self._handle(header, payload, time.perf_counter_ns(), time.time_ns() / 1e9)
            except wp.ProtocolError as exc:
                with self._lock:
                    self._counts["protocol_errors"] += 1
                return f"protocol error: {exc}"
        return None

    def _handle(self, header: wp.Header, payload: bytes, recv_ns: int, wall: float) -> None:
        if self._last_sequence is not None and header.sequence != (self._last_sequence + 1) & 0xFFFFFFFF:
            with self._lock:
                self._counts["sequence_gaps"] += 1
        self._last_sequence = header.sequence
        if header.type == wp.TYPE_CSI:
            cycle = wp.decode_csi(payload)
            rows = cycle_rows(cycle, self.clock.map(header.timestamp_us, recv_ns), wall)
            with self._lock:
                self._counts["csi_packets"] += 1
                for row in rows:
                    self._rx_rows[row["rx_index"]] = self._rx_rows.get(row["rx_index"], 0) + 1
                    self._csi_lengths[row["rx_index"]] = row["csi_len"]
            for row in rows:
                self.on_sample(row)
        elif header.type == wp.TYPE_STATUS:
            status = wp.decode_status(payload)
            with self._lock:
                self._counts["status_packets"] += 1
                self._last_status = copy.deepcopy(status)
                self._last_status_received_ns = recv_ns
            self._emit("status", status)
            # The worker stamped STATUS inside _emit; later CSI must not map before it.
            self.clock.set_floor(time.perf_counter_ns())
        elif header.type == wp.TYPE_ACK:
            ack = wp.decode_ack(payload)
            with self._lock:
                self._counts["ack_packets"] += 1
            self._emit("ack", ack)
        else:
            with self._lock:
                self._counts["pose_packets_ignored"] += 1


class PoseInput:
    """TCP client for port 5001; keeps latest_pose only (UI must not wait on location)."""

    def __init__(self, host: str, port: int = 5001, *, retry_s: float = 1.0) -> None:
        self.host, self.port, self.retry_s = host, int(port), retry_s
        self.latest: dict[str, Any] | None = None
        self._sock: socket.socket | None = None
        self.connected = False
        self._stop = threading.Event()
        self._lock = threading.Lock()
        self._thread = threading.Thread(target=self._run, name="wise-pose-5001", daemon=True)

    def start(self) -> "PoseInput":
        self._thread.start()
        return self

    def stop(self) -> None:
        self._stop.set()
        sock = self._sock
        if sock is not None:
            try:
                sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            sock.close()
        if threading.current_thread() is not self._thread:
            self._thread.join(timeout=2.5)

    def latest_pose(self) -> dict[str, Any] | None:
        with self._lock:
            return copy.deepcopy(self.latest)

    def _run(self) -> None:
        while not self._stop.is_set():
            try:
                sock = socket.create_connection((self.host, self.port), timeout=2.0)
            except OSError:
                self._stop.wait(self.retry_s)
                continue
            self._sock = sock
            if self._stop.is_set():
                sock.close()
                break
            self.connected = True
            sock.settimeout(0.5)
            decoder = StreamDecoder()
            try:
                while not self._stop.is_set():
                    try:
                        data = sock.recv(4096)
                    except socket.timeout:
                        continue
                    if not data:
                        break
                    for header, payload in decoder.feed(data):
                        if header.type != wp.TYPE_POSE:
                            continue
                        pose = wp.decode_pose(payload)
                        with self._lock:
                            self.latest = {"window_id": pose.window_id, "end_trigger_seq": pose.end_trigger_seq,
                                           "infer_us": pose.infer_us, "timestamp_us": header.timestamp_us,
                                           "received_ns": time.perf_counter_ns(),
                                           "pose": dict(zip(wp.POSE_NAMES, pose.pose_float()))}
            except (OSError, wp.ProtocolError):
                pass
            finally:
                self.connected = False
                sock.close()
                self._sock = None
                with self._lock:
                    self.latest = None
            self._stop.wait(self.retry_s)


def make_live_session_class():
    """LiveSession whose input is EthernetInput; TX commands belong to the PS."""
    from . import location_live
    from .location_live import LiveSession

    def load_any(path):
        # .npz = portable Ridge (no training-version check); else the Studio joblib loader.
        if str(path).lower().endswith(".npz"):
            from .portable_ridge import PortableRidge
            return PortableRidge(path).as_studio_bundle()
        return studio_load_model(path)

    # In-process only (no file is changed); joblib paths keep the original loader.
    studio_load_model = getattr(location_live, "_studio_load_model", location_live.load_model)
    location_live._studio_load_model = studio_load_model
    location_live.load_model = load_any   # used by LiveSession.__init__ / switch_model

    class EthernetLiveSession(LiveSession):
        def __init__(self, model_path=DEFAULT_MODEL, host="192.168.10.2", csi_port=5000,
                     identity_confirmed=False, **kwargs):
            super().__init__(model_path, f"{host}:{csi_port}", identity_confirmed=identity_confirmed, **kwargs)
            self.host, self.csi_port = host, int(csi_port)

        def start(self):
            if self._started:
                raise RuntimeError("EthernetLiveSession은 단일 사용입니다; 새 객체를 만드세요")
            self._started = True
            self.worker = self._new_worker(self.bundle, self.identity_confirmed)
            self.serial = EthernetInput(self.host, self.csi_port, self._on_sample, self._on_event)
            self.serial.start()
            return self

        def send_command(self, command):
            # The PS pushes STATUS every few seconds; PC never drives the TX.
            self._require_worker()
            if command.strip() != "status":
                raise RuntimeError("보드 경유 구조에서는 TX 명령을 PS가 보냅니다 (v1.1 메모 5절)")

    return EthernetLiveSession
