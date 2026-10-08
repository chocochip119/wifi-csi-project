"""Read the existing TX USB protocol without modifying the reference project.

Callbacks run on the serial reader thread. ``wall_time_s`` is the PC time at
cycle parsing, not the ESP32 radio acquisition time. USB buffering is not
corrected here. CSI bytes retain their original on-wire order.
"""
from __future__ import annotations

import copy
import importlib.util
from pathlib import Path
import sys
import threading
import time
from typing import Any, Callable
import uuid


_BUNDLED_REFERENCE = Path(__file__).resolve().parent / "vendor" / "sync_csi_input.py"
# A collection-only export includes an unchanged copy of the USB parser.
# The development checkout continues to use the existing reference source.
if _BUNDLED_REFERENCE.is_file():
    DEFAULT_REFERENCE = _BUNDLED_REFERENCE
else:
    DEFAULT_REFERENCE = (
        Path(__file__).resolve().parents[2]
        / "wifi-csi-pose-main" / "tools" / "sync_csi_input.py"
    )
_IMPORT_LOCK = threading.Lock()


def list_ports() -> list[str]:
    """List ports lazily so importing this module needs no serial hardware."""
    try:
        from serial.tools import list_ports as ports
    except ImportError as exc:
        raise RuntimeError("pyserial is required; install requirements.txt first.") from exc
    return [port.device for port in ports.comports()]


def _load_reference(path: Path) -> Any:
    if path.is_dir():
        path = path / "tools" / "sync_csi_input.py"
    if not path.is_file():
        raise FileNotFoundError(f"Reference USB parser not found: {path}")
    name = f"_localization_usb_reference_{uuid.uuid4().hex}"
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load reference USB parser: {path}")
    module = importlib.util.module_from_spec(spec)
    # dataclasses consult sys.modules while executing the reference source.
    with _IMPORT_LOCK:
        previous = sys.dont_write_bytecode
        sys.dont_write_bytecode = True
        sys.modules[name] = module
        try:
            spec.loader.exec_module(module)
        except ModuleNotFoundError as exc:
            sys.modules.pop(name, None)
            if exc.name == "serial" or (exc.name or "").startswith("serial."):
                raise RuntimeError("pyserial is required; install requirements.txt first.") from exc
            raise
        except BaseException:
            sys.modules.pop(name, None)
            raise
        finally:
            sys.dont_write_bytecode = previous
    return module


def _guard_cycle_parser(module: Any) -> None:
    """Reject byte loss before calling the unchanged reference cycle parser."""
    original = module.parse_cycle

    def parse_cycle(payload: bytes) -> Any:
        wall_time_s = time.time_ns() / 1_000_000_000
        # Preserve the local fix: use one high-resolution clock throughout.
        # Distinct USB cycles can share a tick; use the same high-resolution
        # clock as the inference worker and trial recorder instead.
        monotonic_ns = time.perf_counter_ns()
        if len(payload) < module.CYCLE_HEADER.size:
            raise ValueError("cycle payload too short")
        header = module.CYCLE_HEADER.unpack_from(payload)
        active, received = header[5:7]
        if not 0 <= received <= active <= 8:
            raise ValueError(f"Invalid RX counts: active={active}, received={received}")
        cursor = module.CYCLE_HEADER.size
        present_count = 0
        identities: set[int] = set()
        for _ in range(active):
            if len(payload) < cursor + module.CYCLE_SLOT.size:
                raise ValueError("cycle slot header truncated")
            rx_index, present, _, _, length = module.CYCLE_SLOT.unpack_from(payload, cursor)
            cursor += module.CYCLE_SLOT.size
            if present not in (0, 1) or rx_index in identities:
                raise ValueError("Invalid or duplicate RX slot")
            identities.add(rx_index)
            if len(payload) < cursor + length:
                raise ValueError("cycle CSI payload truncated")
            if length % 2:
                raise ValueError("Odd CSI byte count would be truncated by reference parser")
            if present and length == 0:
                raise ValueError("Present RX has no CSI bytes")
            if not present and length:
                raise ValueError("Missing RX unexpectedly contains CSI bytes")
            present_count += present
            cursor += length
        if cursor != len(payload) or present_count != received:
            raise ValueError("Cycle byte count or received RX count does not match header")
        cycle = original(payload)
        cycle.capture_wall_time_s = wall_time_s
        cycle.capture_monotonic_ns = monotonic_ns
        return cycle

    # Only this privately loaded module is wrapped; the source stays untouched.
    module.parse_cycle = parse_cycle


class _EventSink:
    """The reference reader only needs Queue.put; dispatch without a backlog."""

    def __init__(self, owner: "SerialInput") -> None:
        self.owner = owner

    def put(self, event: tuple[str, Any]) -> None:
        self.owner._handle_event(*event)


class SerialInput:
    def __init__(
        self,
        port: str,
        on_sample: Callable[[dict[str, Any]], None],
        on_event: Callable[[str, Any], None],
        reference_path: Path | None = None,
        baudrate: int = 115200,
    ) -> None:
        self.port = port
        self.baudrate = baudrate
        self.reference_path = Path(reference_path or DEFAULT_REFERENCE).resolve()
        self.on_sample = on_sample
        self.on_event = on_event
        self._reader: Any = None
        self._module: Any = None
        self._started = False
        self._stopping = False
        self._connected = False
        self._closed_emitted = False
        self._last_error: str | None = None
        self._last_status: dict[str, Any] | None = None
        self._observed_ids: set[int] = set()
        self._last_sample_ns: dict[int, int] = {}
        self._received_rows: dict[int, int] = {}
        self._csi_lengths: dict[int, int] = {}
        self._lock = threading.Lock()
        self._write_lock = threading.Lock()

    def start(self) -> None:
        """Connect only. The caller explicitly sends status/mode commands."""
        if self._started:
            raise RuntimeError("SerialInput is single-use; create a new input to reconnect.")
        self._module = _load_reference(self.reference_path)
        _guard_cycle_parser(self._module)
        self._reader = self._module.SerialReader(self.port, self.baudrate, _EventSink(self))
        self._started = True
        self._reader.start()

    def stop(self) -> None:
        """Close the port and wait at most two seconds, never join ourselves."""
        self._stopping = True
        reader = self._reader
        if reader is None:
            return
        reader.stop_event.set()
        self._close_port()
        if threading.current_thread() is not reader:
            reader.join(timeout=2.0)
            if reader.is_alive():
                self._fail("Serial reader did not stop within two seconds")

    def send_command(self, command: str) -> None:
        """Send one original firmware command, for example ``mode run``."""
        command = command.strip()
        if not command or "\n" in command or "\r" in command:
            raise ValueError("Expected one nonempty firmware command without line breaks")
        data = ("CMD " + command + "\n").encode("ascii")
        reader = self._reader
        port = reader.serial_port if reader is not None else None
        if self._stopping or port is None or not getattr(port, "is_open", False):
            raise RuntimeError("USB port is not connected")
        if command.startswith('mode '):
            with self._lock:
                self._last_status = None
        try:
            with self._write_lock:
                written = port.write(data)
            if written != len(data):
                raise OSError(f"Incomplete serial write: {written}/{len(data)} bytes")
        except Exception as exc:
            message = f"Serial command failed: {exc}"
            self._fail(message)
            raise RuntimeError(message) from exc

    def snapshot(self) -> dict[str, Any]:
        with self._lock:
            return {
                "port": self.port,
                "baudrate": self.baudrate,
                "reference_path": str(self.reference_path),
                "connected": self._connected,
                "status": copy.deepcopy(self._last_status),
                "observed_rx_ids": sorted(self._observed_ids),
                "last_sample_monotonic_ns": dict(self._last_sample_ns),
                "received_rows_by_rx": dict(self._received_rows),
                "csi_len_by_rx": dict(self._csi_lengths),
                "last_error": self._last_error,
                "timestamp_basis": "PC time at USB cycle parsing; no transport delay correction",
                "monotonic_clock": "time.perf_counter_ns",
            }

    def _close_port(self) -> None:
        reader = self._reader
        port = reader.serial_port if reader is not None else None
        if port is not None:
            try:
                port.close()
            except Exception:
                pass

    def _fail(self, message: str) -> None:
        with self._lock:
            self._last_error = message
        if self._reader is not None:
            self._reader.stop_event.set()
        try:
            self.on_event("error", message)
        except Exception:
            # A failing UI callback must not prevent the reader's finally/close.
            pass

    def _handle_event(self, kind: str, payload: Any) -> None:
        try:
            if kind == "record":
                return  # Already emitted from its cycle, never duplicate rows.
            if kind == "cycle":
                if self._stopping or self._last_error is not None:
                    return
                for record in payload.records:
                    if self._stopping or self._last_error is not None:
                        return
                    raw = bytes(value & 0xFF for pair in record.iq_pairs for value in pair)
                    if len(raw) != record.csi_len or record.csi_len % 2:
                        raise ValueError("CSI byte count changed during reference parsing")
                    sample = {
                        "wall_time_s": payload.capture_wall_time_s,
                        "monotonic_ns": payload.capture_monotonic_ns,
                        "rx_index": record.rx_index,
                        "trigger_seq": record.trigger_seq,
                        "uart_seq": record.uart_seq,
                        "rssi": record.rssi,
                        "csi_len": record.csi_len,
                        "csi_raw_hex": raw.hex(),
                        "active_nodes": payload.active_nodes,
                        "received_nodes": payload.received_nodes,
                        "timeout_fired": int(payload.timeout_fired),
                    }
                    with self._lock:
                        self._observed_ids.add(record.rx_index)
                        self._last_sample_ns[record.rx_index] = sample["monotonic_ns"]
                        # Count reception before inference can reject a row.
                        # A timing rejection is not evidence of radio loss.
                        self._received_rows[record.rx_index] = self._received_rows.get(record.rx_index, 0) + 1
                        self._csi_lengths[record.rx_index] = record.csi_len
                    self.on_sample(sample)
                return
            if kind == "status":
                with self._lock:
                    self._last_status = copy.deepcopy(payload)
            elif kind == "log":
                if payload.startswith("Connected to "):
                    with self._lock:
                        self._connected = True
                elif payload.startswith(("Serial error:", "Frame parse error", "RX buffer overflow")):
                    if not self._stopping:
                        self._fail(payload)
                    return
            elif kind == "closed":
                self._close_port()
                with self._lock:
                    self._connected = False
                if self._closed_emitted:
                    return
                self._closed_emitted = True
            self.on_event(kind, payload)
        except Exception as exc:
            self._fail(f"Serial callback/decoding error: {exc}")
