"""Location live GUI with USB or PS-bypass Ethernet input.

    python ml/localization/tools/csi_live_gui_ethernet.py --run-dir <runs/run_...> [--port 192.168.10.2:5000]

Runs the unchanged location GUI (ml/localization/csi_live_gui.py) and swaps only
the session factory:  "COM8"               -> USB LiveSession (TX directly on the PC)
                      "192.168.10.2:5000"  -> Ethernet session from pc/backend (TX -> PS -> TCP 5000)
TCP parsing/receiving is not duplicated here: it comes from pc/backend/localization
and pc/backend/protocol. The PS sends TX commands, so TX Run/Wait report an error
on Ethernet. The board accepts one PC per port: do not run the Backend on the same
5000 port at the same time. Trial records go to ml/localization/live_results/.
Needs the training environment (exact versions) because the GUI loads joblib runs.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import sys
import traceback

sys.dont_write_bytecode = True
LOCATION = Path(__file__).resolve().parents[1]          # ml/localization (flat modules)
BACKEND = LOCATION.parents[1] / "pc" / "backend"        # localization/, protocol/ packages
sys.path[:0] = [str(LOCATION), str(BACKEND)]

import location_live  # noqa: E402
from localization.ethernet_input import make_live_session_class  # noqa: E402

USB_SESSION = location_live.LiveSession
ETHERNET_SESSION = make_live_session_class()
DEFAULT_ENDPOINT = "192.168.10.2:5000"
RESULTS = LOCATION / "live_results"


def parse_endpoint(text):
    """(host, port) for Ethernet input, None for a serial port name."""
    value = str(text).strip()
    if value.lower().startswith("tcp://"):
        value = value[6:]
    if not value or value.upper().startswith("COM") or value.startswith("/dev/"):
        return None
    host, _, port = value.rpartition(":") if ":" in value else (value, "", "5000")
    if not host or not port.isdigit() or not 0 < int(port) < 65536:
        raise ValueError("Ethernet 주소는 IP:포트 형식입니다. 예: 192.168.10.2:5000")
    return host, int(port)


def session_factory(model_path, port, baudrate=115200, **kwargs):
    endpoint = parse_endpoint(port)
    if endpoint is None:
        return USB_SESSION(model_path, port, baudrate, **kwargs)
    host, csi_port = endpoint
    return ETHERNET_SESSION(model_path=model_path, host=host, csi_port=csi_port, **kwargs)


# desktop_controller resolves location_live.LiveSession when a controller is built.
location_live.LiveSession = session_factory

import desktop_controller  # noqa: E402
from live_recording import TrialRecorder  # noqa: E402


class Controller(desktop_controller.DesktopController):
    def __init__(self, root, *, catalog=None, session_factory=None, recorder=None):
        super().__init__(root, catalog=catalog, session_factory=session_factory,
                         recorder=recorder or TrialRecorder(RESULTS))


desktop_controller.DesktopController = Controller

import csi_live_gui as gui  # noqa: E402


class EthernetApp(gui.DesktopApp):
    def __init__(self, window, initial_port="", initial_run_dir=""):
        super().__init__(window, initial_port=initial_port, initial_run_dir=initial_run_dir)
        window.title(window.title() + " · USB / Ethernet(PS)")
        self._relabel(window)
        self.message.set("연결 칸에 COM 번호(USB) 또는 PS IP:포트(Ethernet, 예: 192.168.10.2:5000)를 넣으세요. "
                         "Ethernet에서는 TX Run/Wait을 PS가 담당합니다.")

    def _relabel(self, widget):
        for child in widget.winfo_children():
            try:
                if child.winfo_class() == "TLabel" and child.cget("text") == "TX COM":
                    child.configure(text="TX COM 또는 PS IP:포트")
            except Exception:
                pass
            self._relabel(child)

    def open_results(self):
        RESULTS.mkdir(exist_ok=True)
        os.startfile(RESULTS)


def main():
    parser = argparse.ArgumentParser(description="Location live GUI, USB or Ethernet (PS bypass)")
    parser.add_argument("--port", default=DEFAULT_ENDPOINT,
                        help="Pre-fill: COMx for USB, or PS IP:port for Ethernet (no automatic connection)")
    parser.add_argument("--run-dir", default="", help="Training run folder (runs are not stored in the repository)")
    args = parser.parse_args()
    print("Python:", sys.executable, flush=True)
    print("Trial records:", RESULTS, flush=True)
    try:
        import tkinter as tk
        window = tk.Tk()
        app = EthernetApp(window, initial_port=args.port, initial_run_dir=args.run_dir)
        try:
            window.mainloop()
        finally:
            app.closing.set()
            app.worker.join(timeout=5)
        return 1 if app.failed else 0
    except Exception:
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
