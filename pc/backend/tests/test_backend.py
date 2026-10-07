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
