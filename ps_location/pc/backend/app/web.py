from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager
from typing import Any

from fastapi import Body, FastAPI, WebSocket, WebSocketDisconnect, Request, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from .config import Settings, ROOT
from .service import BackendService


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or Settings.from_env()
    service = BackendService(settings)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        service.start()
        app.state.service = service
        try:
            yield
        finally:
            service.stop()

    app = FastAPI(title="WiSensing Backend", version="1.0", lifespan=lifespan)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @app.get("/health")
    async def health() -> dict[str, Any]:
        snap = service.snapshot()
        return {
            "ok": True,
            "fake": settings.fake,
            "ps_connected": snap["system"]["ps_connected"],
            "status_ready": snap["system"]["status_ready"],
            "inference_running": snap["system"]["inference_running"],
        }

    @app.get("/api/snapshot")
    async def snapshot() -> dict[str, Any]:
        return service.snapshot()

    @app.post("/api/offline-pose")
    async def offline_pose(request: Request) -> dict[str, Any]:
        """Local CSV replay, NOT live FPGA inference. Does not change PS/TCP state."""
        from .offline_pose_inference import MAX_BYTES, infer_csv_bytes
        raw = await request.body()
        if not raw or len(raw) > MAX_BYTES:
            raise HTTPException(status_code=413, detail="CSV는 1~50MB만 허용됩니다.")
        model_dir = ROOT / 'localization' / 'models' / 'pose_int8'
        try:
            return await asyncio.to_thread(infer_csv_bytes,raw,model_dir)
        except (ValueError, OSError, UnicodeDecodeError, KeyError) as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

    @app.get("/api/rx-layout")
    async def rx_layout() -> dict[str, Any]:
        return service.rx_layout()

    @app.post("/api/confirm-rx-layout")
    async def confirm_rx_layout(payload: dict[str, Any] | None = Body(default=None)) -> dict[str, Any]:
        return service.confirm_rx_layout((payload or {}).get('rx_signature'))

    @app.post("/api/inference/stop")
    async def stop_inference() -> dict[str, Any]:
        return service.stop_inference()

    @app.websocket("/ws")
    async def websocket_endpoint(ws: WebSocket):
        await ws.accept()
        last_seq = -1
        try:
            while True:
                snap = service.snapshot()
                if snap["seq"] != last_seq:
                    await ws.send_json(snap)
                    last_seq = snap["seq"]

                try:
                    message = await asyncio.wait_for(ws.receive_json(), timeout=0.05)
                except asyncio.TimeoutError:
                    continue

                kind = message.get("type") if isinstance(message, dict) else None
                if kind == "confirm_rx_layout":
                    result = service.confirm_rx_layout(message.get('rx_signature'))
                    await ws.send_json({"type": "command_result", "command": kind, **result})
                elif kind == "stop_inference":
                    result = service.stop_inference()
                    await ws.send_json({"type": "command_result", "command": kind, **result})
                elif kind == "ping":
                    await ws.send_json({"type": "pong"})
                else:
                    await ws.send_json({"type": "command_result", "command": kind, "ok": False,
                                        "message": "unknown command"})
        except WebSocketDisconnect:
            return

    return app
