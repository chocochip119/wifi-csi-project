#!/usr/bin/env python3
"""Windows-only one-click WiSensing supervisor (Python standard library).

Owns only the Backend and Vite processes it starts. Zybo is never modified.
"""
from __future__ import annotations

import argparse
import hmac
import ipaddress
import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / ".wisensing_runtime"
SESSION = RUNTIME / "session.json"
BACKEND_PORT = 8000
FRONTEND_PORT = 5173
CONTROL_PORT = 8765
CONTROL_URL = f"http://127.0.0.1:{CONTROL_PORT}/stop"
FRONTEND_ORIGINS = {f"http://127.0.0.1:{FRONTEND_PORT}", f"http://localhost:{FRONTEND_PORT}"}
CHILDREN: list[tuple[subprocess.Popen, object]] = []


def port_used(port: int) -> bool:
    with socket.socket() as sock:
        sock.settimeout(0.5)
        return sock.connect_ex(("127.0.0.1", port)) == 0


def wait_http(url: str, process: subprocess.Popen, timeout: float) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f"서버가 종료됨: {url}, exit={process.returncode}")
        try:
            with urllib.request.urlopen(url, timeout=1) as response:
                if response.status == 200:
                    return True
        except (urllib.error.URLError, TimeoutError, OSError):
            pass
        time.sleep(0.4)
    raise TimeoutError(f"서버 시작 시간 초과: {url}")


def start_child(command: list[str], cwd: Path, log_name: str, env: dict | None = None) -> subprocess.Popen:
    logfile = (RUNTIME / log_name).open("a", encoding="utf-8")
    try:
        flags = getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
        process = subprocess.Popen(command, cwd=str(cwd), stdout=logfile,
                                   stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                                   env=env, creationflags=flags)
        CHILDREN.append((process, logfile))
        return process
    except Exception:
        logfile.close()
        raise


def stop_children() -> None:
    # Never kill processes that were running before this launcher started.
    for process, logfile in reversed(CHILDREN):
        if process.poll() is None:
            try:
                if os.name == "nt":
                    subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                   timeout=8, check=False)
                else:
                    process.terminate()
            except (OSError, subprocess.TimeoutExpired):
                pass
            try:
                process.wait(timeout=4)
            except subprocess.TimeoutExpired:
                process.kill()
        logfile.close()
    CHILDREN.clear()


def stop_running_session() -> int:
    try:
        session = json.loads(SESSION.read_text(encoding="utf-8"))
        token = session["token"]
        request = urllib.request.Request(CONTROL_URL, data=b"{}",
                                         headers={"Origin": f"http://127.0.0.1:{FRONTEND_PORT}",
                                                  "X-WiSensing-Token": token},
                                         method="POST")
        with urllib.request.urlopen(request, timeout=4) as response:
            if response.status != 200:
                raise RuntimeError(f"HTTP {response.status}")
        print("[WiSensing] 종료 요청 완료")
        return 0
    except (OSError, ValueError, KeyError, urllib.error.URLError, RuntimeError) as exc:
        print(f"[WiSensing] 실행 중인 앱을 종료할 수 없습니다: {exc}")
        print("이미 종료됐다면 문제없습니다. 다른 프로그램의 서버는 강제로 종료하지 않습니다.")
        return 1


def make_handler(token: str):
    class ControlHandler(BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass

        def cors(self):
            origin = self.headers.get("Origin", "")
            if origin in FRONTEND_ORIGINS:
                self.send_header("Access-Control-Allow-Origin", origin)
                self.send_header("Vary", "Origin")

        def reply(self, status: int, message: str):
            data = json.dumps({"ok": status == 200, "message": message}).encode("utf-8")
            self.send_response(status)
            self.cors()
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def authorized_origin(self):
            return (self.headers.get("Host") == f"127.0.0.1:{CONTROL_PORT}"
                    and self.headers.get("Origin") in FRONTEND_ORIGINS)

        def do_OPTIONS(self):
            if not self.authorized_origin() or self.path != "/stop":
                self.reply(403, "Forbidden")
                return
            self.send_response(204)
            self.cors()
            self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "X-WiSensing-Token")
            self.send_header("Access-Control-Max-Age", "600")
            self.end_headers()

        def do_POST(self):
            if self.path != "/stop" or not self.authorized_origin():
                self.reply(403, "Forbidden")
                return
            received = self.headers.get("X-WiSensing-Token", "")
            if not hmac.compare_digest(received, token):
                self.reply(403, "Invalid session")
                return
            self.reply(200, "Stopping WiSensing")
            threading.Thread(target=self.server.shutdown, daemon=True).start()

        def do_GET(self):
            self.reply(404, "Not found")
    return ControlHandler


def run(ps_host: str) -> int:
    if os.name != "nt":
        print("[WiSensing] 이 원클릭 실행기는 Windows 전용입니다.")
        return 1
    ipaddress.ip_address(ps_host)
    python = ROOT / ".venv" / "Scripts" / "python.exe"
    if not python.is_file():
        print(f"[WiSensing] Python 환경을 찾지 못했습니다: {python}")
        print("먼저 저장소 루트의 .venv와 Backend 의존성을 준비해 주세요.")
        return 1
    npm = shutil.which("npm.cmd") or shutil.which("npm")
    if not npm:
        print("[WiSensing] npm을 찾지 못했습니다. Node.js LTS 설치 후 다시 실행해 주세요.")
        return 1
    for port in (BACKEND_PORT, FRONTEND_PORT, CONTROL_PORT):
        if port_used(port):
            print(f"[WiSensing] 포트 {port}가 이미 사용 중입니다.")
            print("이전에 직접 실행한 Backend/Vite를 종료한 다음 다시 실행해 주세요.")
            print("기존 프로그램을 강제로 종료하지는 않습니다.")
            return 1

    RUNTIME.mkdir(parents=True, exist_ok=True)
    token = secrets.token_urlsafe(32)
    session = {"token": token, "control_port": CONTROL_PORT}
    server: ThreadingHTTPServer | None = None
    try:
        server = ThreadingHTTPServer(("127.0.0.1", CONTROL_PORT), make_handler(token))
        server.daemon_threads = True
        SESSION.write_text(json.dumps(session), encoding="utf-8")
        env = os.environ.copy()
        env.pop("WISE_FAKE", None)
        env["PYTHONUNBUFFERED"] = "1"
        backend = start_child([str(python), "-u", str(ROOT / "pc" / "backend" / "run_backend.py"),
                              "--ps-host", ps_host, "--host", "127.0.0.1", "--port", str(BACKEND_PORT)],
                             ROOT, "backend.log", env)
        print("[WiSensing] Python Backend 시작 중...")
        wait_http(f"http://127.0.0.1:{BACKEND_PORT}/health", backend, 35)

        frontend_dir = ROOT / "pc" / "frontend"
        vite = frontend_dir / "node_modules" / "vite" / "bin" / "vite.js"
        if not vite.is_file():
            print("[WiSensing] 최초 실행: npm ci 설치 중...")
            with (RUNTIME / "npm-install.log").open("a", encoding="utf-8") as logfile:
                result = subprocess.run([npm, "ci"], cwd=frontend_dir,
                                        stdout=logfile, stderr=subprocess.STDOUT,
                                        timeout=180, check=False)
            if result.returncode != 0:
                raise RuntimeError("npm ci 실패. .wisensing_runtime/npm-install.log 확인")
        frontend = start_child([npm, "run", "dev", "--", "--host", "127.0.0.1", "--strictPort"],
                               frontend_dir, "frontend.log", env)
        print("[WiSensing] 3D Frontend 시작 중...")
        wait_http(f"http://127.0.0.1:{FRONTEND_PORT}/", frontend, 45)

        url = f"http://127.0.0.1:{FRONTEND_PORT}/#wise-launcher={token}"
        print(f"[WiSensing] 실행 완료: {ps_host} (실제 장비 연결)")
        print("[WiSensing] 브라우저의 '프로그램 종료' 또는 WiSensing_Stop.bat 사용")
        webbrowser.open(url)
        server.serve_forever(poll_interval=0.2)
        print("[WiSensing] 정상 종료 중...")
        return 0
    except (OSError, RuntimeError, TimeoutError, subprocess.TimeoutExpired,
            urllib.error.URLError) as exc:
        print(f"[WiSensing] 시작 실패: {exc}")
        print(f"[WiSensing] 로그 위치: {RUNTIME}")
        return 1
    finally:
        if server:
            server.server_close()
        stop_children()
        if SESSION.exists():
            try:
                if json.loads(SESSION.read_text(encoding="utf-8")).get("token") == token:
                    SESSION.unlink()
            except (OSError, ValueError):
                pass


def main():
    parser = argparse.ArgumentParser(description="WiSensing one-click Windows launcher")
    parser.add_argument("--ps-host", default="10.10.20.41", help="Zybo IPv4 address")
    parser.add_argument("--stop", action="store_true", help="Stop a session started by this launcher")
    args = parser.parse_args()
    try:
        return stop_running_session() if args.stop else run(args.ps_host)
    except ValueError as exc:
        print(f"[WiSensing] Invalid IP address: {exc}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
