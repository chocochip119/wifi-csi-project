from __future__ import annotations

import argparse
import os
from pathlib import Path

import uvicorn


def main() -> None:
    parser = argparse.ArgumentParser(description="WiSensing PC Backend")
    parser.add_argument("--ps-host", default=os.environ.get("WISE_PS_HOST", "192.168.10.2"))
    parser.add_argument("--csi-port", type=int, default=int(os.environ.get("WISE_CSI_PORT", "5000")))
    parser.add_argument("--pose-port", type=int, default=int(os.environ.get("WISE_POSE_PORT", "5001")))
    parser.add_argument("--host", default=os.environ.get("WISE_BIND_HOST", "127.0.0.1"), help="Backend bind host")
    parser.add_argument("--port", type=int, default=int(os.environ.get("WISE_WEB_PORT", "8000")))
    parser.add_argument("--model", default=os.environ.get("WISE_MODEL_PATH"))
    parser.add_argument("--fake", action="store_true", help="PS 없이 Frontend 연동용 가짜 데이터")
    args = parser.parse_args()

    os.environ["WISE_PS_HOST"] = args.ps_host
    os.environ["WISE_CSI_PORT"] = str(args.csi_port)
    os.environ["WISE_POSE_PORT"] = str(args.pose_port)
    os.environ["WISE_BIND_HOST"] = args.host
    os.environ["WISE_WEB_PORT"] = str(args.port)
    if args.model:
        os.environ["WISE_MODEL_PATH"] = str(Path(args.model).resolve())
    if args.fake:
        os.environ["WISE_FAKE"] = "1"

    # Import after setting env so app factory sees CLI values.
    from .config import Settings
    from .web import create_app

    settings = Settings.from_env()
    app = create_app(settings)
    uvicorn.run(app, host=settings.bind_host, port=settings.web_port, reload=False)


if __name__ == "__main__":
    main()
