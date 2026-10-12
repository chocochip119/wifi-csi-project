from __future__ import annotations

import copy
import hashlib
import json
import math
import threading
import time
from typing import Any

from .config import Settings


ZONE_BY_CLASS = {f"p0{i}": i for i in range(1, 10)} | {"p10": 5, "empty": None}
JOINT_IDS = {
    "left_shoulder": 11,
    "right_shoulder": 12,
    "left_elbow": 13,
    "right_elbow": 14,
    "left_wrist": 15,
    "right_wrist": 16,
    "left_hip": 23,
    "right_hip": 24,
    "left_knee": 25,
    "right_knee": 26,
    "left_ankle": 27,
    "right_ankle": 28,
}



class LocationStabilizer:
    """Hold a published point until 3 distinct consecutive window predictions agree.

    A stale/invalid prediction clears immediately. Repeated polls of the same
    model window do not count as new votes. Raw inference remains unmodified.
    """

    def __init__(self, confirmations: int = 3):
        self.confirmations = confirmations
        self.reset()

    def reset(self):
        self.last_stamp = None
        self.stable = None
        self.candidate = None
        self.count = 0

    def update(self, prediction):
        if prediction is None:
            self.reset()
            return None
        stamp = prediction.get("monotonic_ns")
        if stamp is None:
            # Do not fabricate votes from snapshots without model-window identity.
            return prediction
        if stamp == self.last_stamp:
            return self.stable
        self.last_stamp = stamp
        label = str(prediction.get("point_id"))
        if self.stable is not None and label == str(self.stable["point_id"]):
            self.stable = prediction.copy()
            self.candidate = None
            self.count = 0
        else:
            if label == self.candidate:
                self.count += 1
            else:
                self.candidate, self.count = label, 1
            if self.count >= self.confirmations:
                self.stable = prediction.copy()
                self.candidate = None
                self.count = 0
        return self.stable

def _now_ms() -> int:
    return time.time_ns() // 1_000_000


class BackendService:
    """PS location + PS/FPGA pose + TX STATUS -> frontend snapshot.

    Location is computed on the PS (ps/src/loc_ridge.c). The PC only shows it
    after the operator confirms the current RX layout, and while that layout's
    STATUS signature stays the same.
    """

    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self._lock = threading.RLock()
        self._stop = threading.Event()
        self._monitor_thread: threading.Thread | None = None
        self._link = None
        self._confirmed_signature: str | None = None
        self._inference_running = False
        self._seq = 0
        self._location_stabilizer = LocationStabilizer(confirmations=3)
        self._last_error: str | None = None
        self._started = False
        self._snapshot: dict[str, Any] = self._empty_snapshot("Backend 시작 전")

    def _empty_snapshot(self, reason: str) -> dict[str, Any]:
        return {
            "type": "snapshot",
            "version": 1,
            "seq": self._seq,
            "timestamp_ms": _now_ms(),
            "system": {
                "ps_connected": False,
                "csi_connected": False,
                "pose_connected": False,
                "status_ready": False,
                "identity_confirmed": False,
                "inference_running": False,
                "rx_active": 0,
                "rx_total": 5,
                "rx_nodes": [],
                "rx_signature": None,
                "wifi_channel": None,
                "second_channel": None,
                "tx_mac": None,
                "reason": reason,
                "last_error": None,
            },
            "location": {
                "valid": False,
                "point_id": None,
                "zone": None,
                "occupied": None,
                "representative_x_cm": None,
                "representative_y_cm": None,
                "window_cycles": None,
                "reason": reason,
            },
            "person": {
                "valid": False,
                "presence": None,
                "posture": "unknown",
            },
            "pose": {
                "valid": False,
                "window_id": None,
                "end_trigger_seq": None,
                "infer_ms": None,
                "age_ms": None,
                "source_timestamp_us": None,
                "coordinate_space": "model_output",
                "joints": [],
            },
        }

    def start(self) -> None:
        if self._started:
            return
        self._started = True
        self._location_stabilizer.reset()
        self._stop.clear()
        if self.settings.fake:
            self._monitor_thread = threading.Thread(target=self._fake_loop, name="wise-backend-fake", daemon=True)
            self._monitor_thread.start()
            return

        try:
            from .ps_link import PsLink

            self._link = PsLink(self.settings.ps_host, self.settings.ps_port).start()
            self._monitor_thread = threading.Thread(target=self._monitor_loop, name="wise-backend-monitor", daemon=True)
            self._monitor_thread.start()
        except Exception as exc:
            self._last_error = f"backend start failed: {exc}"
            with self._lock:
                self._seq += 1
                self._snapshot = self._empty_snapshot(self._last_error)
                self._snapshot["seq"] = self._seq
                self._snapshot["system"]["last_error"] = self._last_error
            self.stop()
            raise

    def stop(self) -> None:
        self._stop.set()
        link = self._link
        if link is not None:
            try:
                link.stop()
            except Exception:
                pass
        if self._monitor_thread is not None and self._monitor_thread is not threading.current_thread():
            self._monitor_thread.join(timeout=2.0)
        self._started = False
        self._link = self._monitor_thread = None
        self._confirmed_signature = None
        self._inference_running = False

    @staticmethod
    def _rx_signature(status: dict[str, Any] | None) -> str | None:
        """Stable proof of the complete five-RX identity; ignores changing counters."""
        if not status:
            return None
        try:
            from localization.location_live import status_identity
            mapping, radio = status_identity(status)
            nodes = status.get("nodes", [])
            if (status.get("connected_count") != 5 or status.get("saved_count") != 5
                    or len(nodes) != 5 or not all(n.get("saved") for n in nodes)):
                return None
            identity = {"generation": int(status["generation"]),
                        "mapping": sorted(mapping.items()), "radio": radio}
            return hashlib.sha256(
                json.dumps(identity, sort_keys=True, separators=(",", ":")).encode("utf-8")
            ).hexdigest()
        except (KeyError, TypeError, ValueError):
            return None

    @classmethod
    def _current_rx_signature(cls, serial: dict[str, Any]) -> str | None:
        """Only expose an RX identity while its transport and STATUS are fresh."""
        seen = serial.get("status_received_ns")
        if not serial.get("connected") or not isinstance(seen, int):
            return None
        age = time.perf_counter_ns() - seen
        if age < 0 or age > 10_000_000_000:
            return None
        return cls._rx_signature(serial.get("status"))

    def confirm_rx_layout(self, rx_signature: str | None = None) -> dict[str, Any]:
        """Require a matching operator-inspected RX identity before enabling inference."""
        if self.settings.fake:
            return {"ok": True, "message": "fake mode: RX 배치 확인 완료"}
        if self._link is None:
            return {"ok": False, "message": "Backend가 시작되지 않았습니다."}
        serial = self._link.snapshot()
        if not serial.get("connected"):
            return {"ok": False, "message": "PS TCP 연결이 끊겨 RX 배치를 확인할 수 없습니다."}
        if serial.get("status") is None:
            return {"ok": False, "message": "STATUS를 아직 받지 못했습니다."}
        signature = self._current_rx_signature(serial)
        if signature is None:
            return {"ok": False, "message": "최신 STATUS에서 RX0~RX4 connected/live/saved 및 RUN 상태를 확인할 수 없습니다."}
        if not isinstance(rx_signature, str) or rx_signature != signature:
            return {"ok": False, "message": "RX 배치가 바뀌었거나 확인 토큰이 없습니다. 화면에서 다시 대조해 주세요."}
        # Model RX MAC mapping (if trained with one) is enforced by the PS engine.
        with self._lock:
            self._confirmed_signature = signature
            self._inference_running = True
        return {"ok": True, "message": "현재 RX 배치를 확인했습니다. PS 위치 추론 결과를 표시합니다."}

    def stop_inference(self) -> dict[str, Any]:
        if self.settings.fake:
            return {"ok": True, "message": "fake mode"}
        if self._link is None:
            return {"ok": False, "message": "Backend가 시작되지 않았습니다."}
        with self._lock:
            self._inference_running = False
        return {"ok": True, "message": "위치 결과 표시를 정지했습니다. (PS 추론은 계속 실행)"}

    def snapshot(self) -> dict[str, Any]:
        with self._lock:
            return copy.deepcopy(self._snapshot)

    def rx_layout(self) -> dict[str, Any]:
        snap = self.snapshot()
        return {
            "status_ready": snap["system"]["status_ready"],
            "identity_confirmed": snap["system"]["identity_confirmed"],
            "rx_nodes": copy.deepcopy(snap["system"]["rx_nodes"]),
            "rx_signature": snap["system"].get("rx_signature"),
            "wifi_channel": snap["system"]["wifi_channel"],
            "second_channel": snap["system"]["second_channel"],
            "tx_mac": snap["system"]["tx_mac"],
        }

    @staticmethod
    def _rx_nodes(status: dict[str, Any] | None) -> list[dict[str, Any]]:
        if not status:
            return []
        result = []
        for node in status.get("nodes", []):
            rx_index = node.get("saved_order") if node.get("saved") else node.get("slot_index")
            result.append({
                "rx_id": rx_index,
                "slot_index": node.get("slot_index"),
                "saved_order": node.get("saved_order"),
                "mac": node.get("mac"),
                "connected": bool(node.get("connected")),
                "live": bool(node.get("live")),
                "saved": bool(node.get("saved")),
                "last_seen_ms": node.get("last_seen_ms"),
            })
        return sorted(result, key=lambda x: (999 if x["rx_id"] is None else x["rx_id"]))

    @staticmethod
    def _location_state(prediction: dict[str, Any] | None, reason: str) -> tuple[dict[str, Any], dict[str, Any]]:
        if prediction is None:
            return (
                {
                    "valid": False,
                    "point_id": None,
                    "zone": None,
                    "occupied": None,
                    "representative_x_cm": None,
                    "representative_y_cm": None,
                    "window_cycles": None,
                    "reason": reason,
                },
                {"valid": False, "presence": None, "posture": "unknown"},
            )

        point = str(prediction.get("point_id"))
        zone = ZONE_BY_CLASS.get(point)
        occupied = bool(prediction.get("occupied", point != "empty"))
        if not occupied:
            person = {"valid": True, "presence": False, "posture": "unknown"}
        else:
            person = {
                "valid": True,
                "presence": True,
                "posture": "sitting" if point == "p10" else "standing",
            }
        location = {
            "valid": True,
            "point_id": point,
            "zone": zone,
            "occupied": occupied,
            "representative_x_cm": prediction.get("representative_x_cm"),
            "representative_y_cm": prediction.get("representative_y_cm"),
            "window_cycles": prediction.get("window_cycles"),
            "infer_ms": prediction.get("infer_ms"),
            "age_ms": (round(max(0.0, (time.perf_counter_ns() - int(prediction["monotonic_ns"])) / 1_000_000.0), 1)
                       if isinstance(prediction.get("monotonic_ns"), int) else None),
            "reason": reason,
        }
        return location, person

    def _pose_state(self, latest: dict[str, Any] | None) -> dict[str, Any]:
        if latest is None:
            return {
                "valid": False,
                "window_id": None,
                "end_trigger_seq": None,
                "infer_ms": None,
                "age_ms": None,
                "source_timestamp_us": None,
                "coordinate_space": "model_output",
                "joints": [],
            }

        age_ms = max(0.0, (time.perf_counter_ns() - int(latest["received_ns"])) / 1_000_000.0)
        valid = age_ms <= self.settings.pose_stale_s * 1000.0
        pose = latest.get("pose") or {}
        joints = []
        for name, joint_id in JOINT_IDS.items():
            x = pose.get(f"{name}_x")
            y = pose.get(f"{name}_y")
            if x is None or y is None or not math.isfinite(float(x)) or not math.isfinite(float(y)):
                continue
            joints.append({"id": joint_id, "name": name, "x": float(x), "y": float(y)})
        return {
            "valid": bool(valid and len(joints) == 12),
            "window_id": latest.get("window_id"),
            "end_trigger_seq": latest.get("end_trigger_seq"),
            "infer_ms": None if latest.get("infer_us") is None else float(latest["infer_us"]) / 1000.0,
            "age_ms": round(age_ms, 1),
            "source_timestamp_us": latest.get("timestamp_us"),
            "coordinate_space": "model_output",
            "joints": joints,
        }

    def _location_from_link(self, link, serial: dict[str, Any], signature: str | None,
                            confirmed: bool, running: bool) -> tuple[dict[str, Any] | None, str]:
        """Show a PS result only for the confirmed layout and only while it is fresh."""
        if link is None or not serial.get("connected"):
            return None, "PS 연결 대기"
        if signature is None:
            return None, "TX STATUS 확인 대기 (RX 5대 RUN/saved 필요)"
        if not confirmed:
            return None, "RX 배치 확인 필요"
        if not running:
            return None, "위치 결과 표시 정지됨"
        prediction = link.latest_location()
        if prediction is None:
            return None, "PS 위치 추론 대기 (2초 창 수집 중)"
        age_ms = (time.perf_counter_ns() - int(prediction["monotonic_ns"])) / 1_000_000.0
        if not 0 <= age_ms <= self.settings.location_stale_s * 1000.0:
            return None, "PS 위치 결과가 오래되었습니다 (CSI 끊김 또는 창 재수집)"
        if prediction["point_id"] == "empty":
            return prediction, "사람 없음(empty) 분류 결과 · 좌표 없음"
        return prediction, "사람 있음 · PS 위치 추론 결과 (좌표는 해당 지점의 대표값)"

    def _monitor_loop(self) -> None:
        while not self._stop.wait(self.settings.monitor_interval_s):
            try:
                link = self._link
                serial = link.snapshot() if link is not None else {}
                status = serial.get("status")
                signature = self._current_rx_signature(serial)
                with self._lock:
                    confirmed = signature is not None and signature == self._confirmed_signature
                    running = self._inference_running
                prediction, reason = self._location_from_link(link, serial, signature, confirmed, running)
                latest_pose = link.latest_pose() if link is not None else None

                # Do not re-vote the same inference window during 100 ms UI polls.
                stable_prediction = self._location_stabilizer.update(prediction)
                location, person = self._location_state(stable_prediction, reason)
                pose = self._pose_state(latest_pose)
                system = {
                    "ps_connected": bool(serial.get("connected")),
                    "csi_connected": bool(serial.get("connected")),
                    "pose_connected": bool(serial.get("connected")),
                    "status_ready": signature is not None,
                    "identity_confirmed": confirmed,
                    "inference_running": running,
                    "rx_active": int(status.get("active_count", 0)) if status else 0,
                    "rx_total": 5,
                    "rx_nodes": self._rx_nodes(status),
                    "rx_signature": signature,
                    "wifi_channel": status.get("wifi_channel") if status else None,
                    "second_channel": status.get("second_channel") if status else None,
                    "tx_mac": status.get("tx_mac") if status else None,
                    "reason": reason,
                    "last_error": serial.get("last_error") or self._last_error,
                }
                with self._lock:
                    self._seq += 1
                    self._snapshot = {
                        "type": "snapshot",
                        "version": 1,
                        "seq": self._seq,
                        "timestamp_ms": _now_ms(),
                        "system": system,
                        "location": location,
                        "person": person,
                        "pose": pose,
                    }
            except Exception as exc:
                self._last_error = f"monitor error: {exc}"

    def _fake_loop(self) -> None:
        # Frontend integration test only. This does not validate the model.
        phase = 0
        points = ["p01", "p05", "p10", "p09", "empty"]
        while not self._stop.wait(self.settings.monitor_interval_s):
            t = time.monotonic()
            point = points[int(t // 3) % len(points)]
            prediction = None if point is None else {
                "point_id": point,
                "occupied": point != "empty",
                "representative_x_cm": None,
                "representative_y_cm": None,
                "window_cycles": 20,
            }
            location, person = self._location_state(prediction, "FAKE MODE")
            base_joints = {
                "left_shoulder":  (0.40, 0.20),
                "right_shoulder": (0.60, 0.20),
                "left_elbow":     (0.30, 0.36),
                "right_elbow":    (0.70, 0.36),
                "left_wrist":     (0.23, 0.52),
                "right_wrist":    (0.77, 0.52),
                "left_hip":       (0.42, 0.52),
                "right_hip":      (0.58, 0.52),
                "left_knee":      (0.41, 0.73),
                "right_knee":     (0.59, 0.73),
                "left_ankle":     (0.40, 0.94),
                "right_ankle":    (0.60, 0.94),
            }

            joints = []
            sway = 0.008 * math.sin(t * 2.0)

            for name, joint_id in JOINT_IDS.items():
                x, y = base_joints[name]

                joints.append({
                    "id": joint_id,
                    "name": name,
                    "x": x + sway,
                    "y": y,
                })
            pose = {
                "valid": point == "p05",
                "window_id": phase,
                "end_trigger_seq": phase * 10,
                "infer_ms": 24.0,
                "age_ms": 0.0,
                "source_timestamp_us": None,
                "coordinate_space": "fake_normalized",
                "joints": joints,
            }
            system = {
                "ps_connected": True,
                "csi_connected": True,
                "pose_connected": True,
                "status_ready": True,
                "identity_confirmed": True,
                "inference_running": True,
                "rx_active": 5,
                "rx_total": 5,
                "rx_nodes": [
                    {"rx_id": i, "slot_index": i, "saved_order": i, "mac": f"00:00:00:00:00:{i:02X}",
                     "connected": True, "live": True, "saved": True, "last_seen_ms": 0}
                    for i in range(5)
                ],
                "wifi_channel": 11,
                "second_channel": "above",
                "tx_mac": "00:00:00:00:00:FF",
                "reason": "FAKE MODE",
                "last_error": None,
            }
            with self._lock:
                phase += 1
                self._seq += 1
                self._snapshot = {
                    "type": "snapshot",
                    "version": 1,
                    "seq": self._seq,
                    "timestamp_ms": _now_ms(),
                    "system": system,
                    "location": location,
                    "person": person,
                    "pose": pose,
                }
