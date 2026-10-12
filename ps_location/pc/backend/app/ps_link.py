"""Single TCP client for the PS (default port 5000).

The PS computes location (type 5) and pose (type 2) and forwards TX STATUS/ACK
(types 3/4) on one connection. Raw CSI (type 1) only appears when the PS runs
with WISE_FORWARD_CSI=1; it is counted and ignored here. All cached state is
dropped on disconnect so a lost link is never shown as a result.
"""
from __future__ import annotations

import copy
import socket
import threading
import time
from typing import Any

from localization.ethernet_input import StreamDecoder
from protocol import wise_protocol as wp


class PsLink:
    def __init__(self, host: str, port: int = 5000, *, retry_s: float = 1.0,
                 connect_timeout_s: float = 2.0) -> None:
        self.host, self.port = host, int(port)
        self.retry_s, self.connect_timeout_s = retry_s, connect_timeout_s
        self._stop = threading.Event()
        self._lock = threading.Lock()
        self._sock: socket.socket | None = None
        self._thread = threading.Thread(target=self._run, name=f"wise-ps-{self.port}", daemon=True)
        self._connected = False
        self._last_error: str | None = None
        self._status: dict | None = None
        self._status_received_ns: int | None = None
        self._pose: dict | None = None
        self._location: dict | None = None
        self._last_sequence: int | None = None
        self._counts = {"connections": 0, "status_packets": 0, "ack_packets": 0, "pose_packets": 0,
                        "location_packets": 0, "csi_packets_ignored": 0, "sequence_gaps": 0,
                        "protocol_errors": 0}

    def start(self) -> "PsLink":
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
        if threading.current_thread() is not self._thread and self._thread.is_alive():
            self._thread.join(timeout=2.5)

    @property
    def connected(self) -> bool:
        with self._lock:
            return self._connected

    def snapshot(self) -> dict[str, Any]:
        with self._lock:
            return {"port": f"{self.host}:{self.port}", "connected": self._connected,
                    "status": copy.deepcopy(self._status), "status_received_ns": self._status_received_ns,
                    "last_error": self._last_error, "counts": dict(self._counts)}

    def latest_pose(self) -> dict[str, Any] | None:
        with self._lock:
            return copy.deepcopy(self._pose)

    def latest_location(self) -> dict[str, Any] | None:
        with self._lock:
            return copy.deepcopy(self._location)

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
            self._last_sequence = None
            with self._lock:
                self._connected, self._last_error = True, None
                self._counts["connections"] += 1
            reason = self._serve(sock)
            sock.close()
            self._sock = None
            with self._lock:
                self._connected = False
                self._status = self._status_received_ns = None
                self._pose = self._location = None
                if reason and not self._stop.is_set():
                    self._last_error = reason
            if not self._stop.is_set():
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
                    self._handle(header, payload, time.perf_counter_ns())
            except wp.ProtocolError as exc:
                with self._lock:
                    self._counts["protocol_errors"] += 1
                return f"protocol error: {exc}"
        return None

    def _handle(self, header: wp.Header, payload: bytes, recv_ns: int) -> None:
        gap = self._last_sequence is not None and header.sequence != (self._last_sequence + 1) & 0xFFFFFFFF
        self._last_sequence = header.sequence
        if header.type == wp.TYPE_STATUS:
            status = wp.decode_status(payload)
            with self._lock:
                self._counts["status_packets"] += 1
                self._status, self._status_received_ns = status, recv_ns
        elif header.type == wp.TYPE_POSE:
            pose = wp.decode_pose(payload)
            with self._lock:
                self._counts["pose_packets"] += 1
                self._pose = {"window_id": pose.window_id, "end_trigger_seq": pose.end_trigger_seq,
                              "infer_us": pose.infer_us, "timestamp_us": header.timestamp_us,
                              "received_ns": recv_ns, "pose": dict(zip(wp.POSE_NAMES, pose.pose_float()))}
        elif header.type == wp.TYPE_LOCATION:
            loc = wp.decode_location(payload)
            with self._lock:
                self._counts["location_packets"] += 1
                self._location = {"point_id": loc.point_id, "occupied": loc.occupied,
                                  "representative_x_cm": loc.x_cm, "representative_y_cm": loc.y_cm,
                                  "window_cycles": loc.window_cycles, "window_id": loc.window_id,
                                  "end_trigger_seq": loc.end_trigger_seq,
                                  "infer_ms": round(loc.infer_us / 1000.0, 3),
                                  "window_start_us": loc.window_start_us, "window_end_us": loc.window_end_us,
                                  "scores": dict(zip(wp.LOCATION_CLASSES, loc.scores)),
                                  "monotonic_ns": recv_ns}
        elif header.type == wp.TYPE_ACK:
            wp.decode_ack(payload)
            with self._lock:
                self._counts["ack_packets"] += 1
        else:
            with self._lock:
                self._counts["csi_packets_ignored"] += 1
        if gap:
            with self._lock:
                self._counts["sequence_gaps"] += 1
