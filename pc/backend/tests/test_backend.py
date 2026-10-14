import time
import pytest
from fastapi.testclient import TestClient
from app.config import Settings
from app.service import BackendService, JOINT_IDS
from app.web import create_app


def test_http_and_websocket_fake_lifecycle():
    with TestClient(create_app(Settings(fake=True,monitor_interval_s=0.01))) as client:
        assert client.get('/health').json()['fake']
        assert client.post('/api/confirm-rx-layout').json()['ok']
        assert client.get('/api/rx-layout').status_code == 200
        with client.websocket_connect('/ws') as ws:
            assert ws.receive_json()['type'] == 'snapshot'
            ws.send_json({'type':'ping'})
            for _ in range(20):
                if ws.receive_json()['type'] == 'pong': break
            else: pytest.fail('missing pong')
        assert client.post('/api/inference/stop').json()['ok']


def test_pose_stale_and_nan_are_invalid():
    service = BackendService(Settings())
    data = {'received_ns':time.perf_counter_ns()-3_000_000_000,
            'pose':{f'{joint}_{axis}':0.5 for joint in JOINT_IDS for axis in 'xy'}}
    assert not service._pose_state(data)['valid']
    data['received_ns'] = time.perf_counter_ns()
    data['pose']['left_shoulder_x'] = float('nan')
    pose = service._pose_state(data)
    assert not pose['valid'] and len(pose['joints']) == 11


def test_real_start_connects_link_and_stop_releases_threads():
    service = BackendService(Settings(ps_host='127.0.0.1',ps_port=1,monitor_interval_s=0.01))
    service.start()
    link = service._link
    assert link is not None
    time.sleep(0.05)
    assert not service.snapshot()['location']['valid']
    service.stop()
    assert not service._started and service._link is None
    assert not link._thread.is_alive()


def _status():
    nodes = [{
        'slot_index': i, 'saved_order': i, 'connected': True,
        'live': True, 'saved': True, 'mac': f'02:00:00:00:00:{i:02X}',
    } for i in range(5)]
    return {
        'mode': 'running', 'active_count': 5, 'connected_count': 5, 'saved_count': 5,
        'generation': 1, 'nodes': nodes, 'tx_mac': 'AA:BB:CC:DD:EE:FF',
        'wifi_channel': 11, 'second_channel': 'above', 'protocol_bitmap': 7,
        'timeout_us': 50000, 'udp_slot_gap_us': 1000,
    }


class DummyLink:
    def __init__(self, status):
        self.serial = {'connected': True, 'status': status, 'status_received_ns': time.perf_counter_ns()}
        self.location = None

    def snapshot(self):
        return self.serial

    def latest_location(self):
        return None if self.location is None else dict(self.location)

    def latest_pose(self):
        return None


def test_real_rx_confirmation_requires_fresh_verified_layout():
    """Require a fresh 5-RX STATUS and the same operator-confirmed identity."""
    service = BackendService(Settings())
    status = _status()
    link = DummyLink(status)
    serial = link.serial
    service._link = link
    token = service._current_rx_signature(serial)
    assert token and len(token) == 64
    assert not service.confirm_rx_layout()['ok']
    assert not service.confirm_rx_layout('wrong-token')['ok']
    assert service._confirmed_signature is None
    assert service.confirm_rx_layout(token)['ok']
    assert service._confirmed_signature == token and service._inference_running

    service._confirmed_signature = None
    serial['status_received_ns'] -= 20_000_000_000
    assert not service.confirm_rx_layout(token)['ok']
    serial['status_received_ns'] = time.perf_counter_ns()
    status['nodes'][4]['saved'] = False
    assert not service.confirm_rx_layout(token)['ok']
    status['nodes'][4]['saved'] = True
    status['generation'] += 1
    assert not service.confirm_rx_layout(token)['ok']
    status['nodes'][0]['mac'] = '04:00:00:00:00:00'
    new_token = service._current_rx_signature(serial)
    assert new_token and new_token != token
    assert not service.confirm_rx_layout(token)['ok']
    assert service._confirmed_signature is None


def test_ps_location_shown_only_when_confirmed_running_and_fresh():
    service = BackendService(Settings())
    link = DummyLink(_status())
    service._link = link
    signature = service._current_rx_signature(link.serial)

    def shown():
        confirmed = signature == service._confirmed_signature
        prediction, _ = service._location_from_link(link, link.serial, signature, confirmed,
                                                    service._inference_running)
        return prediction

    link.location = {'point_id': 'p10', 'occupied': True, 'representative_x_cm': 90,
                     'representative_y_cm': 90, 'window_cycles': 20, 'infer_ms': 0.2,
                     'monotonic_ns': time.perf_counter_ns()}
    assert shown() is None                       # layout not confirmed yet
    assert service.confirm_rx_layout(signature)['ok']
    location, person = service._location_state(shown(), 'ok')
    assert location['valid'] and location['zone'] == 5 and person['posture'] == 'sitting'
    link.location['monotonic_ns'] -= 3_000_000_000
    assert shown() is None                       # stale PS result
    link.location['monotonic_ns'] = time.perf_counter_ns()
    assert service.stop_inference()['ok'] and shown() is None
    service._inference_running = True
    link.serial['status']['generation'] += 1     # new STATUS identity needs a new confirmation
    signature = service._current_rx_signature(link.serial)
    assert shown() is None
