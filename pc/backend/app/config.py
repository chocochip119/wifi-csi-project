from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import os


ROOT = Path(__file__).resolve().parents[1]


@dataclass(frozen=True)
class Settings:
    ps_host: str = "192.168.10.2"
    # One PS port carries STATUS/ACK, PS location and FPGA pose.
    ps_port: int = 5000
    bind_host: str = "127.0.0.1"
    web_port: int = 8000
    pose_stale_s: float = 2.0
    location_stale_s: float = 2.0
    monitor_interval_s: float = 0.05
    fake: bool = False

    @classmethod
    def from_env(cls) -> "Settings":
        return cls(
            ps_host=os.environ.get("WISE_PS_HOST", "192.168.10.2"),
            ps_port=int(os.environ.get("WISE_PS_PORT", os.environ.get("WISE_CSI_PORT", "5000"))),
            bind_host=os.environ.get("WISE_BIND_HOST", "127.0.0.1"),
            web_port=int(os.environ.get("WISE_WEB_PORT", "8000")),
            pose_stale_s=float(os.environ.get("WISE_POSE_STALE_S", "2.0")),
            location_stale_s=float(os.environ.get("WISE_LOCATION_STALE_S", "2.0")),
            monitor_interval_s=float(os.environ.get("WISE_MONITOR_INTERVAL_S", "0.05")),
            fake=os.environ.get("WISE_FAKE", "0").lower() in {"1", "true", "yes", "on"},
        )
