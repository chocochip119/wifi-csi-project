"""PsLink against a Python stand-in PS server (portable; the C bridge tests need Linux)."""
import socket
import threading
import time

import pytest

from app.config import Settings
from app.ps_link import PsLink
from app.service import BackendService
from protocol import wise_protocol as wp
from tests.test_transport import status_payload, until


class FakePs:
    def __init__(self):
        self.listener = socket.socket()
        self.listener.bind(('127.0.0.1', 0))
        self.listener.listen(1)
        self.port = self.listener.getsockname()[1]
        self.client = None
        self.sequence = 0
        self.accepted = threading.Event()
        threading.Thread(target=self._accept, daemon=True).start()

    def _accept(self):
        self.client, _ = self.listener.accept()
        self.accepted.set()

    def send(self, kind, payload):
        self.client.sendall(wp.frame(kind, payload, self.sequence, int(time.monotonic() * 1e6)))
        self.sequence += 1

    def close(self):
        if self.client is not None:
            self.client.close()
        self.listener.close()


def location(point='p03', window_id=1):
    xy = (None, None) if point == 'empty' else (150, 30)
    return wp.encode_location(wp.LocationResult(window_id, 500, 210, point, point != 'empty', 19, *xy,
                                                1_000_000, 3_000_000, tuple(float(i) for i in range(11))))


@pytest.fixture
def fake_ps():
    ps = FakePs()
    yield ps
    ps.close()


def test_single_port_carries_status_pose_location_and_ignores_csi(fake_ps):
    link = PsLink('127.0.0.1', fake_ps.port, retry_s=0.05).start()
    try:
        assert fake_ps.accepted.wait(3)
        fake_ps.send(wp.TYPE_STATUS, status_payload())
        fake_ps.send(wp.TYPE_POSE, wp.encode_pose(wp.PoseResult(7, 123, 23000, 0.01, tuple(range(-12, 12)))))
        fake_ps.send(wp.TYPE_LOCATION, location())
        fake_ps.send(wp.TYPE_CSI, wp.encode_csi(wp.CsiCycle(1, 2, 1, 1, False, [wp.RxRecord(0, True, -40, b'\1\2')])))
        until(lambda: link.snapshot()['counts']['csi_packets_ignored'] == 1)
        snap = link.snapshot()
        assert snap['connected'] and snap['status']['active_count'] == 5
        assert snap['counts']['sequence_gaps'] == 0
        loc = link.latest_location()
        assert loc['point_id'] == 'p03' and loc['representative_x_cm'] == 150 and loc['infer_ms'] == 0.21
        assert loc['scores']['empty'] == 10.0
        assert link.latest_pose()['window_id'] == 7
        fake_ps.client.close()
        until(lambda: not link.connected)
        assert link.latest_location() is None and link.latest_pose() is None
        assert link.snapshot()['status'] is None
    finally:
        link.stop()
    assert not link._thread.is_alive()


def test_backend_shows_ps_location_after_confirmation(fake_ps):
    service = BackendService(Settings(ps_host='127.0.0.1', ps_port=fake_ps.port, monitor_interval_s=0.01))
    service.start()
    try:
        assert fake_ps.accepted.wait(3)
        fake_ps.send(wp.TYPE_STATUS, status_payload())
        snap = until(lambda: service.snapshot() if service.snapshot()['system']['status_ready'] else None)
        fake_ps.send(wp.TYPE_LOCATION, location('p05'))
        time.sleep(0.05)
        assert not service.snapshot()['location']['valid']          # not confirmed yet
        assert service.confirm_rx_layout(snap['system']['rx_signature'])['ok']
        # LocationStabilizer publishes a point after 3 consecutive PS windows agree.
        for window in range(2, 5):
            fake_ps.send(wp.TYPE_LOCATION, location('p05', window))
            time.sleep(0.1)
        snap = until(lambda: service.snapshot() if service.snapshot()['location']['valid'] else None)
        assert snap['location']['point_id'] == 'p05' and snap['location']['zone'] == 5
        assert snap['system']['identity_confirmed'] and snap['system']['pose_connected']
        for window in range(5, 8):
            fake_ps.send(wp.TYPE_LOCATION, location('empty', window))
            time.sleep(0.1)
        snap = until(lambda: service.snapshot() if service.snapshot()['location']['point_id'] == 'empty' else None)
        assert snap['person'] == {'valid': True, 'presence': False, 'posture': 'unknown'}
    finally:
        service.stop()


def test_replay_tool_sends_ps_style_location(tmp_path):
    import json
    import numpy as np
    import pandas as pd
    from tools.replay_ps_server import ReplayServer, load_csv_cycles

    rng = np.random.default_rng(3)
    rows, start = [], pd.Timestamp('2026-10-12T09:00:00Z')
    for k in range(60):                                  # 3 s at 20 Hz, replayed in real time
        stamp = (start + pd.Timedelta(milliseconds=50 * k)).isoformat()
        for rx in range(5):
            iq = rng.integers(-30, 30, size=(192, 2)).tolist()
            rows.append({'csi_host_time': stamp, 'trigger_seq': 1000 + k, 'rx_index': rx,
                         'rssi': -50 - rx, 'csi_len': 384, 'iq_pairs': json.dumps(iq)})
    path = tmp_path / 'session.csv'
    pd.DataFrame(rows).to_csv(path, index=False)
    # --speed also compresses the PS clock, so windows need real-time replay.
    server = ReplayServer([load_csv_cycles(path)]).start()
    link = PsLink('127.0.0.1', server.address[1], retry_s=10).start()
    try:
        until(lambda: server.sent, timeout=6)
        assert server.sent[0]['locations'] >= 2
        until(lambda: link.snapshot()['counts']['location_packets'] == server.sent[0]['locations'])
        assert link.snapshot()['counts']['csi_packets_ignored'] == 0
    finally:
        link.stop()
