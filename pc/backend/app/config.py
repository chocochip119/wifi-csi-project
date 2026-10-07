from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import os


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MODEL = ROOT / "localization" / "models" / "ridge_portable.npz"


@dataclass(frozen=True)
class Settings:
    ps_host: str = "192.168.10.2"
    csi_port: int = 5000
    pose_port: int = 5001
    bind_host: str = "127.0.0.1"
    web_port: int = 8000
    model_path: Path = DEFAULT_MODEL
    pose_stale_s: float = 2.0
    monitor_interval_s: float = 0.10
    fake: bool = False

    @classmethod
    def from_env(cls) -> "Settings":
        model = Path(os.environ.get("WISE_MODEL_PATH", DEFAULT_MODEL)).resolve()
        return cls(
            ps_host=os.environ.get("WISE_PS_HOST", "192.168.10.2"),
            csi_port=int(os.environ.get("WISE_CSI_PORT", "5000")),
            pose_port=int(os.environ.get("WISE_POSE_PORT", "5001")),
            bind_host=os.environ.get("WISE_BIND_HOST", "127.0.0.1"),
            web_port=int(os.environ.get("WISE_WEB_PORT", "8000")),
            model_path=model,
            pose_stale_s=float(os.environ.get("WISE_POSE_STALE_S", "2.0")),
            monitor_interval_s=float(os.environ.get("WISE_MONITOR_INTERVAL_S", "0.10")),
            fake=os.environ.get("WISE_FAKE", "0").lower() in {"1", "true", "yes", "on"},
        )
