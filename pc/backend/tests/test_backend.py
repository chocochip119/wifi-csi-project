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


def test_real_start_loads_model_and_stop_releases_threads():
    service = BackendService(Settings(ps_host='127.0.0.1',csi_port=1,pose_port=2))
    service.start()
    assert service._live.bundle['feature_count'] == 955
    service.stop()
    assert not service._started


def test_start_failure_is_retryable_and_cleans_up(tmp_path):
    service = BackendService(Settings(model_path=tmp_path/'absent.npz'))
    with pytest.raises(FileNotFoundError): service.start()
    assert not service._started and service._live is None and service._pose is None


def test_real_rx_confirmation_requires_fresh_verified_layout():
    """Require a fresh 5-RX STATUS and the same operator-confirmed identity."""
    from localization.location_live import status_identity

    service = BackendService(Settings())
    nodes = [{
        'slot_index': i, 'saved_order': i, 'connected': True,
        'live': True, 'saved': True, 'mac': f'02:00:00:00:00:{i:02X}',
    } for i in range(5)]
    status = {
        'mode': 'running', 'active_count': 5, 'connected_count': 5, 'saved_count': 5,
        'generation': 1, 'nodes': nodes, 'tx_mac': 'AA:BB:CC:DD:EE:FF',
        'wifi_channel': 11, 'second_channel': 'above', 'protocol_bitmap': 7,
        'timeout_us': 50000, 'udp_slot_gap_us': 1000,
    }
    mapping, radio = status_identity(status)
    config = {'layout_id': 'layout_02', 'rx_mac_by_index': mapping, 'radio': radio}
    calls = []
    serial = {'connected': True, 'status': status, 'status_received_ns': time.perf_counter_ns()}

    class DummyLive:
        bundle = {'config': config}

        def snapshot(self):
            return {'serial': serial}

        def start_inference(self, *, identity_confirmed):
            calls.append(identity_confirmed)

    service._live = DummyLive()
    token = service._current_rx_signature(serial)
    assert token and len(token) == 64
    assert not service.confirm_rx_layout()['ok']
    assert not service.confirm_rx_layout('wrong-token')['ok']
    assert not calls
    assert service.confirm_rx_layout(token)['ok']
    assert calls == [True]

    calls.clear()
    serial['status_received_ns'] -= 20_000_000_000
    assert not service.confirm_rx_layout(token)['ok']
    assert not calls
    serial['status_received_ns'] = time.perf_counter_ns()
    status['nodes'][4]['saved'] = False
    assert not service.confirm_rx_layout(token)['ok']
    assert not calls
    status['nodes'][4]['saved'] = True
    status['generation'] += 1
    assert not service.confirm_rx_layout(token)['ok']
    assert not calls
    status['nodes'][0]['mac'] = '04:00:00:00:00:00'
    new_token = service._current_rx_signature(serial)
    assert new_token
    assert not service.confirm_rx_layout(new_token)['ok']
    assert not calls
