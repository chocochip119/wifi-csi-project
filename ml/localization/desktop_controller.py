"""Desktop actions using the existing inference and trial-recording contracts.

This controller is owned by one background thread. Serial/model callbacks only
call the existing, locked TrialRecorder. Importing this file opens no devices.
"""
from pathlib import Path


class DesktopController:
    def __init__(self, root, *, catalog=None, session_factory=None, recorder=None):
        self.root = Path(root).resolve()
        if catalog is None:
            from live_catalog import ModelCatalog
            catalog = ModelCatalog(self.root)
        if session_factory is None:
            from location_live import LiveSession
            session_factory = LiveSession
        if recorder is None:
            from live_recording import TrialRecorder
            recorder = TrialRecorder(self.root / 'live_results')
        self.catalog = catalog
        self.session_factory = session_factory
        self.recorder = recorder
        self.session = None
        self.active_entry = None

    def _session(self):
        if self.session is None or self.session.snapshot().get('stopped'):
            raise RuntimeError('먼저 TX COM 포트에 연결하세요.')
        return self.session

    def _selected(self, model_id):
        if self.active_entry is None or model_id != self.active_entry['id']:
            raise RuntimeError('선택한 모델을 먼저 적용하세요.')

    def connect(self, model_id, port, baudrate=115200):
        port = port.strip()
        if not port:
            raise ValueError('TX 데이터 포트 번호를 입력하세요. 예: COM8')
        if int(baudrate) <= 0:
            raise ValueError('baud는 양수여야 합니다.')
        if self.session is not None:
            old = self.session.snapshot()
            if not old.get('stopped') and not old.get('serial', {}).get('last_error'):
                raise RuntimeError('이미 연결 중입니다. 먼저 연결 해제를 누르세요.')
            self.disconnect()
        entry = self.catalog.by_id[model_id]
        session = self.session_factory(
            self.catalog.path(entry), port, int(baudrate), inference_stride_s=.5,
            on_prediction=self.recorder.on_prediction, on_sample=self.recorder.on_sample)
        try:
            session.start()
        except Exception:
            session.stop()
            raise
        self.session = session
        self.active_entry = dict(entry)
        return '연결 요청됨. Status와 RX 5개를 확인하세요.'

    def command(self, command):
        if command not in ('status', 'mode run', 'mode wait'):
            raise ValueError('이 화면은 Status / TX Run / TX Wait만 전송합니다.')
        session = self._session()
        # Send first: a refused command (e.g. Ethernet, where the PS owns the TX)
        # must not end the running trial. A sent TX command still ends it.
        session.send_command(command)
        if command != 'status':
            self.finish_trial('tx_command')
        return '전송: CMD ' + command

    def apply_model(self, model_id):
        if self.session is None or self.session.snapshot().get('stopped'):
            raise RuntimeError('첫 연결은 모델을 선택한 뒤 연결을 누르세요. 선택 모델이 자동 적용됩니다. 이 버튼은 연결 후 모델 변경용입니다.')
        session = self._session()
        entry = self.catalog.by_id[model_id]
        path = self.catalog.path(entry)
        self.finish_trial('model_switch')
        session.switch_model(path)
        self.active_entry = dict(entry)
        return '모델 적용 완료. 배치를 확인하고 추론 시작을 누르세요.'

    def start_inference(self, model_id, confirmed):
        if not confirmed:
            raise ValueError('학습 당시 배치·RX 번호 순서·HT40 설정을 확인한 뒤 체크하세요.')
        session = self._session()
        self._selected(model_id)
        self.finish_trial('inference_restart')
        session.start_inference(identity_confirmed=True)
        return '추론 시작 요청됨. 유효한 2초 입력 이후 사람 없음 또는 예측 지점을 표시합니다.'

    def stop_inference(self):
        session = self._session()
        self.finish_trial('inference_stop')
        session.stop_inference()
        return '추론 정지. USB 연결은 유지합니다.'

    def start_trial(self, model_id, confirmed, truth, seconds, subject='', raw=False):
        session = self._session()
        self._selected(model_id)
        state = session.snapshot()
        if not confirmed or not state.get('status_ready') or not state.get('inference_running'):
            raise RuntimeError('Status 준비와 배치 확인 후 추론을 먼저 시작하세요.')
        self.recorder.start(self.active_entry, truth, seconds, subject, raw, status=state)
        try:
            session.stop_inference()
            session.start_inference(identity_confirmed=True)
        except Exception as exc:
            self.recorder.error = '시험 시작 오류: ' + str(exc)
            self.finish_trial('start_error')
            raise
        return '시험 기록 시작. 새 입력 2초를 모은 뒤 예측을 저장합니다.'

    def finish_trial(self, reason='manual_stop'):
        result = self.recorder.finish(reason, status=self.session.snapshot() if self.session else None)
        return '시험 기록 종료: ' + result['folder'] if result else '진행 중인 시험 기록이 없습니다.'

    def disconnect(self):
        try:
            self.finish_trial('disconnected')
        finally:
            if self.session is not None:
                self.session.stop()
        return 'USB 연결 해제됨.'

    def snapshot(self):
        state = self.session.snapshot() if self.session else {
            'reason': '연결 전', 'prediction': None, 'serial': {}, 'counts': {}}
        rec = self.recorder.snapshot()
        if rec['active']:
            before = (self.recorder.meta.get('input_status') or {}).get('callback_errors', {})
            errors = state.get('callback_errors', {})
            if rec['error'] or any(n > before.get(k, 0) for k, n in errors.items()):
                self.recorder.error = rec['error'] or '기록 callback 오류: ' + str(errors)
                self.finish_trial('logging_error')
            elif rec['remaining_s'] <= 0:
                self.finish_trial('duration_complete')
            elif state.get('stopped') or not state.get('serial', {}).get('connected') or state.get('serial', {}).get('last_error'):
                self.finish_trial('connection_error')
            rec = self.recorder.snapshot()
        return dict(state=state, recording=rec, result=self.recorder.last_result,
                    active_model=dict(self.active_entry) if self.active_entry else None)

    def close(self):
        return self.disconnect()
