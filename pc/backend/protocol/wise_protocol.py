"""WiSensing PS <-> PC Ethernet protocol v1.1 (wire version 2).

Pure encode/decode. No sockets, no model. See docs/ps_pc_protocol.md.
"""
from __future__ import annotations

from dataclasses import dataclass, field
import struct
import math

MAGIC = b"WISE"
VERSION = 2
HEADER_SIZE = 24
TYPE_CSI, TYPE_POSE, TYPE_STATUS, TYPE_ACK = 1, 2, 3, 4
TYPES = (TYPE_CSI, TYPE_POSE, TYPE_STATUS, TYPE_ACK)

HEADER = struct.Struct("<4sBBHIIQ")          # magic version type header_size payload_size sequence timestamp_us
CSI_HEAD = struct.Struct("<IIBBBBB3x")        # trigger_seq uart_seq active received rx_count valid_mask timeout_fired
RX_HEAD = struct.Struct("<BBbBHH")            # rx_id valid rssi reserved csi_len reserved2
POSE = struct.Struct("<IIIf24b")              # window_id end_trigger_seq infer_us output_scale pose[24]

# TX USB STATUS/ACK payloads, forwarded unchanged by the PS (types 3/4).
# Same layout as the Studio reference parser vendor/sync_csi_input.py.
STATUS_HEADER = struct.Struct("<8B7I6s2s")
STATUS_NODE = struct.Struct("<4B6sIII")
ACK = struct.Struct("<4BII64s")

MAX_RX = 8
MAX_CSI_BYTES = 1024
MAX_PAYLOAD = CSI_HEAD.size + MAX_RX * (RX_HEAD.size + MAX_CSI_BYTES)

POSE_NAMES = tuple(f"{joint}_{axis}" for joint in (
    "left_shoulder", "right_shoulder", "left_elbow", "right_elbow", "left_wrist", "right_wrist",
    "left_hip", "right_hip", "left_knee", "right_knee", "left_ankle", "right_ankle") for axis in "xy")


class ProtocolError(ValueError):
    pass


def _require(test, message):
    if not test:
        raise ProtocolError(message)


@dataclass
class Header:
    type: int
    payload_size: int
    sequence: int
    timestamp_us: int
    version: int = VERSION


@dataclass
class RxRecord:
    rx_id: int
    valid: bool
    rssi: int
    csi: bytes = b""


@dataclass
class CsiCycle:
    trigger_seq: int
    uart_seq: int
    active_nodes: int
    received_nodes: int
    timeout_fired: bool
    records: list[RxRecord] = field(default_factory=list)


@dataclass
class PoseResult:
    window_id: int
    end_trigger_seq: int
    infer_us: int
    output_scale: float
    pose_int8: tuple[int, ...]

    def pose_float(self) -> list[float]:
        return [value * self.output_scale for value in self.pose_int8]


def pack_header(kind: int, payload_size: int, sequence: int, timestamp_us: int) -> bytes:
    return HEADER.pack(MAGIC, VERSION, kind, HEADER_SIZE, payload_size,
                       sequence & 0xFFFFFFFF, timestamp_us & 0xFFFFFFFFFFFFFFFF)


def unpack_header(data: bytes) -> Header:
    _require(len(data) == HEADER_SIZE, "header must be 24 bytes")
    magic, version, kind, header_size, payload_size, sequence, timestamp_us = HEADER.unpack(data)
    _require(magic == MAGIC, f"bad magic {magic!r}")
    _require(version == VERSION, f"unsupported version {version} (expected {VERSION})")
    _require(header_size == HEADER_SIZE, f"bad header_size {header_size}")
    _require(kind in TYPES, f"unknown packet type {kind}")
    _require(payload_size <= MAX_PAYLOAD, f"payload too large {payload_size}")
    return Header(kind, payload_size, sequence, timestamp_us, version)


def encode_csi(cycle: CsiCycle) -> bytes:
    _require(len(cycle.records) <= MAX_RX, "too many RX records")
    mask, body, seen = 0, [], set()
    for record in cycle.records:
        _require(0 <= record.rx_id < MAX_RX, "rx_id out of range")
        _require(record.rx_id not in seen, "duplicate rx_id")
        seen.add(record.rx_id)
        _require(len(record.csi) % 2 == 0 and len(record.csi) <= MAX_CSI_BYTES, "CSI must be even and <= 1024")
        _require(bool(record.valid) == bool(record.csi), "valid flag and CSI length disagree")
        if record.valid:
            mask |= 1 << record.rx_id
        body.append(RX_HEAD.pack(record.rx_id, int(bool(record.valid)), record.rssi, 0, len(record.csi), 0))
        body.append(bytes(record.csi))
    head = CSI_HEAD.pack(cycle.trigger_seq & 0xFFFFFFFF, cycle.uart_seq & 0xFFFFFFFF, cycle.active_nodes,
                         cycle.received_nodes, len(cycle.records), mask, int(bool(cycle.timeout_fired)))
    result = head + b"".join(body)
    decode_csi(result)
    return result


def decode_csi(payload: bytes) -> CsiCycle:
    _require(len(payload) >= CSI_HEAD.size, "CSI payload too short")
    trigger, uart, active, received, count, mask, timeout = CSI_HEAD.unpack_from(payload)
    _require(count <= MAX_RX and active == count and timeout in (0, 1), "bad CSI head")
    cursor, records, seen, valid_count, mask_seen = CSI_HEAD.size, [], set(), 0, 0
    for _ in range(count):
        _require(len(payload) >= cursor + RX_HEAD.size, "RX record header truncated")
        rx_id, valid, rssi, _, length, _ = RX_HEAD.unpack_from(payload, cursor)
        cursor += RX_HEAD.size
        _require(rx_id < MAX_RX and rx_id not in seen, "invalid or duplicate rx_id")
        _require(valid in (0, 1), "valid must be 0/1")
        _require(bool(valid) == bool(length), "valid flag and csi_len disagree")
        _require(length % 2 == 0 and length <= MAX_CSI_BYTES, "csi_len must be even and <= 1024")
        _require(len(payload) >= cursor + length, "CSI bytes truncated")
        seen.add(rx_id)
        valid_count += valid
        mask_seen |= valid << rx_id
        records.append(RxRecord(rx_id, bool(valid), rssi, bytes(payload[cursor:cursor + length])))
        cursor += length
    _require(cursor == len(payload), "trailing bytes in CSI payload")
    _require(mask == mask_seen, "valid_mask disagrees with records")
    _require(valid_count == received, "received_nodes disagrees with valid records")
    return CsiCycle(trigger, uart, active, received, bool(timeout), records)


def encode_pose(result: PoseResult) -> bytes:
    _require(math.isfinite(result.output_scale) and result.output_scale > 0, "pose scale must be finite and positive")
    _require(len(result.pose_int8) == 24, "pose needs 24 coordinates")
    return POSE.pack(result.window_id, result.end_trigger_seq, result.infer_us,
                     result.output_scale, *result.pose_int8)


def decode_pose(payload: bytes) -> PoseResult:
    _require(len(payload) == POSE.size, f"pose payload must be {POSE.size} bytes")
    window_id, end_seq, infer_us, scale, *pose = POSE.unpack(payload)
    _require(math.isfinite(scale) and scale > 0, "pose scale must be finite and positive")
    return PoseResult(window_id, end_seq, infer_us, scale, tuple(pose))


def _mac_text(raw: bytes) -> str:
    return ":".join(f"{byte:02X}" for byte in raw)


def _second_channel_text(value: int) -> str:
    return {1: "above", 2: "below"}.get(value, "none")


def decode_status(payload: bytes) -> dict:
    """TX STATUS -> the same dict as vendor parse_status (no pyserial needed)."""
    _require(len(payload) >= STATUS_HEADER.size, "status payload too short")
    (mode, wifi_channel, second_channel, protocol_bitmap, connected_count, active_count, saved_count,
     node_entry_count, timeout_us, udp_slot_gap_us, generation, next_trigger_seq, uart_seq,
     trigger_sent_count, cycle_timeout_count, tx_mac, _) = STATUS_HEADER.unpack_from(payload, 0)
    expected = STATUS_HEADER.size + node_entry_count * STATUS_NODE.size
    _require(node_entry_count <= MAX_RX and len(payload) == expected, f"status payload size/count mismatch: expected={expected} got={len(payload)}")
    nodes, cursor = [], STATUS_HEADER.size
    for _ in range(node_entry_count):
        (slot_index, saved_order, connect_order, flags, mac, last_seen_ms, rx_ok,
         rx_timeout) = STATUS_NODE.unpack_from(payload, cursor)
        cursor += STATUS_NODE.size
        nodes.append({"slot_index": slot_index, "saved_order": saved_order, "connect_order": connect_order,
                      "flags": flags, "connected": bool(flags & 0x01), "saved": bool(flags & 0x02),
                      "live": bool(flags & 0x04), "mac": _mac_text(mac), "last_seen_ms": last_seen_ms,
                      "rx_ok": rx_ok, "rx_timeout": rx_timeout})
    return {"mode": "running" if mode else "wait", "wifi_channel": wifi_channel,
            "second_channel": _second_channel_text(second_channel), "protocol_bitmap": protocol_bitmap,
            "connected_count": connected_count, "active_count": active_count, "saved_count": saved_count,
            "timeout_us": timeout_us, "udp_slot_gap_us": udp_slot_gap_us, "generation": generation,
            "next_trigger_seq": next_trigger_seq, "uart_seq": uart_seq,
            "trigger_sent_count": trigger_sent_count, "cycle_timeout_count": cycle_timeout_count,
            "tx_mac": _mac_text(tx_mac), "nodes": nodes}


def decode_ack(payload: bytes) -> dict:
    """TX ACK -> the same dict as vendor parse_ack."""
    _require(len(payload) == ACK.size, f"ack payload must be {ACK.size} bytes")
    ok, mode, wifi_channel, second_channel, timeout_us, udp_slot_gap_us, raw_message = ACK.unpack(payload)
    return {"ok": bool(ok), "mode": "running" if mode else "wait", "wifi_channel": wifi_channel,
            "second_channel": _second_channel_text(second_channel), "timeout_us": timeout_us,
            "udp_slot_gap_us": udp_slot_gap_us,
            "message": raw_message.split(b"\x00", 1)[0].decode("ascii", errors="ignore")}


def frame(kind: int, payload: bytes, sequence: int, timestamp_us: int) -> bytes:
    return pack_header(kind, len(payload), sequence, timestamp_us) + payload
