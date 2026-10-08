"""Dynamic training-run GUI/controller checks. No Tk window, fitting or COM."""
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from desktop_controller import DesktopController
from live_recording import TrialRecorder
from csi_live_gui import visible_prediction, inspect_run_selection, prediction_text, truth_label, EMPTY_CHOICE, DesktopApp


class FakeCatalog:
    def __init__(self, root):
        self.root = Path(root)
        self.entries = [dict(id=f'new_{family}', family=family, variant='amp_rssi', selected=family == 'ridge',
                             path=f'models/{family}.joblib', sha256='a'*64) for family in ('knn', 'ridge', 'mlp')]
        self.data = {'default_id': 'new_ridge'}
        self.by_id = {e['id']: e for e in self.entries}
    def path(self, entry):
        return self.root / entry['path']
    def verify_all(self):
        return {'models': 3}


class FakeSession:
    def __init__(self, model_path, port, baudrate=115200, **callbacks):
        self.model_path, self.callbacks, self.calls = model_path, callbacks, []
        self.state = dict(stopped=False, status_ready=True, inference_running=False,
                          prediction=None, serial={'connected': True}, callback_errors={})
    def start(self):
        self.calls.append(('start',))
    def stop(self):
        self.state['stopped'] = True
        self.state['serial']['connected'] = False
    def snapshot(self):
        return self.state.copy()
    def send_command(self, command):
        self.calls.append(('command', command))
    def start_inference(self, **kw):
        self.state['inference_running'] = True
    def stop_inference(self):
        self.state['inference_running'] = False
    def switch_model(self, path):
        self.stop_inference()
        self.model_path = path


def event(a, b):
    return dict(point_id='p01', window_start_ns=a, window_end_ns=b, latest_sample_ns=b-100_000_000,
                valid_cycles=20, representative_x_cm=30, representative_y_cm=30)


class DesktopChecks(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.folder = Path(temp.name)
        self.control = DesktopController(self.folder, catalog=FakeCatalog(self.folder),
            session_factory=FakeSession, recorder=TrialRecorder(self.folder / 'live_results'))
        self.addCleanup(self.control.close)
        self.model = 'new_ridge'
        guard = patch('serial.Serial', side_effect=AssertionError('Real COM forbidden'))
        guard.start()
        self.addCleanup(guard.stop)

    def connect_and_start(self):
        self.control.connect(self.model, 'MOCK_ONLY')
        self.control.start_inference(self.model, True)

    def test_no_old_models_or_automatic_tx_commands(self):
        self.assertIsNone(self.control.session)
        with self.assertRaisesRegex(RuntimeError, '첫 연결'):
            self.control.apply_model(self.model)
        self.control.connect(self.model, 'MOCK_ONLY')
        self.assertEqual(self.control.session.calls, [('start',)])
        with self.assertRaises(ValueError):
            self.control.start_inference(self.model, False)
        self.assertFalse(self.control.session.state['inference_running'])
        self.control.start_inference(self.model, True)
        self.assertFalse(any(c[0] == 'command' for c in self.control.session.calls))
        with self.assertRaises(ValueError):
            self.control.command('save_nodes')

    def test_selection_requires_apply_and_finishes_old_model_trial(self):
        self.connect_and_start()
        with self.assertRaises(RuntimeError):
            self.control.start_inference('new_knn', True)
        self.control.start_trial(self.model, True, 'p01', 5)
        r = self.control.recorder
        self.control.session.callbacks['on_prediction'](event(r.begin_ns, r.begin_ns+2_000_000_000))
        self.control.apply_model('new_knn')
        result = self.control.snapshot()['result']
        self.assertEqual(result['model']['id'], self.model)
        self.assertEqual(result['predictions'], 1)
        self.assertEqual(result['end_reason'], 'model_switch')
        self.assertFalse(self.control.session.state['inference_running'])
        self.assertTrue(Path(result['folder']).is_relative_to(self.folder / 'live_results'))

    def test_deadline_and_logging_error_end_trial(self):
        self.connect_and_start()
        self.control.start_trial(self.model, True, 'p01', 5)
        with patch('live_recording.time.perf_counter_ns', return_value=self.control.recorder.deadline_ns+1):
            snapshot = self.control.snapshot()
        self.assertFalse(snapshot['recording']['active'])
        self.assertEqual(snapshot['result']['end_reason'], 'duration_complete')
        self.control.start_trial(self.model, True, 'p01', 5)
        self.control.session.state['callback_errors'] = {'prediction': 1}
        snapshot = self.control.snapshot()
        self.assertEqual(snapshot['result']['status'], 'failed')
        self.assertEqual(snapshot['result']['end_reason'], 'logging_error')

    def test_disconnect_stops_session_if_record_close_fails(self):
        self.connect_and_start()
        with patch.object(self.control.recorder, 'finish', side_effect=OSError('write failed')):
            with self.assertRaises(OSError):
                self.control.disconnect()
        self.assertTrue(self.control.session.state['stopped'])

    def test_cached_prediction_hidden_during_actions_and_stale_input(self):
        state = dict(inference_running=True, serial={'connected': True},
                     prediction={'point_id': 'p05', 'monotonic_ns': 10_000_000_000})
        self.assertEqual(visible_prediction(state, False, 11_000_000_000)['point_id'], 'p05')
        self.assertIsNone(visible_prediction(state, True, 11_000_000_000))
        self.assertIsNone(visible_prediction(state, False, 12_000_000_001))
        state['serial']['connected'] = False
        self.assertIsNone(visible_prediction(state, False, 11_000_000_000))

    def test_empty_display_recording_and_unavailable_are_distinct(self):
        self.assertEqual(truth_label(EMPTY_CHOICE), 'empty')
        self.assertEqual(truth_label('empty'), 'empty')
        self.assertEqual(truth_label('미지정 / 관찰만'), '')
        self.assertIn('사람 없음', prediction_text({'point_id': 'empty'}))
        self.assertIn('좌표 없음', prediction_text({'point_id': 'empty'}))
        self.assertIn('입력 부족', prediction_text(None))
        self.connect_and_start()
        self.control.start_trial(self.model, True, 'empty', 5, subject='not a subject')
        r = self.control.recorder
        pred = event(r.begin_ns, r.begin_ns + 2_000_000_000)
        pred.update(point_id='empty', representative_x_cm=None, representative_y_cm=None)
        self.control.session.callbacks['on_prediction'](pred)
        self.control.finish_trial()
        result = self.control.snapshot()['result']
        self.assertEqual(result['truth'], 'empty')
        self.assertEqual(result['subject'], 'none')
        self.assertEqual(result['class_recall'], 1)
        state = dict(inference_running=True, serial={'connected': True},
                     prediction={**pred, 'monotonic_ns': 10_000_000_000})
        self.assertIsNone(visible_prediction(state, False, 12_000_000_001))

    def test_empty_map_clears_previous_point_highlight(self):
        class Canvas:
            def __init__(self): self.colours = []
            def delete(self, *_): self.colours.clear()
            def create_text(self, *args, **kw): pass
            def create_rectangle(self, *args, **kw): pass
            def create_oval(self, *args, **kw): self.colours.append(kw['fill'])
        app = type('MapOnly', (), {'map': Canvas()})()
        DesktopApp.draw_map(app, 'p05')
        self.assertEqual(app.map.colours.count('#008594'), 1)
        DesktopApp.draw_map(app, 'empty')
        self.assertEqual(app.map.colours.count('#008594'), 0)
        self.assertEqual(len(app.map.colours), 10)

    def test_seated_p10_highlights_ring_not_p05_circle(self):
        class Canvas:
            def __init__(self): self.ovals, self.texts = [], []
            def delete(self, *_): self.ovals.clear(); self.texts.clear()
            def create_text(self, *args, **kw): self.texts.append(kw['text'])
            def create_rectangle(self, *args, **kw): pass
            def create_oval(self, *args, **kw): self.ovals.append((kw['fill'], kw['outline']))
        app = type('MapOnly', (), {'map': Canvas()})()
        DesktopApp.draw_map(app, 'p10')
        self.assertEqual([o for o in app.map.ovals if o[0] == '#008594'], [])
        self.assertIn(('', '#008594'), app.map.ovals)
        self.assertIn('p10 앉기', app.map.texts)
        self.assertEqual(truth_label('p10(p05 앉기)'), 'p10')
        self.assertIn('p05 앉기', prediction_text({'point_id': 'p10'}))

    def test_run_folder_and_catalogued_model_resolve_dynamically(self):
        fit = self.folder / 'fit'
        (fit / 'models').mkdir(parents=True)
        (fit / 'model_catalog.json').write_text('{}')
        selected = fit / 'models' / 'mlp.joblib'
        selected.write_bytes(b'not deserialized in this test')
        root, _, model_id, _ = inspect_run_selection(str(self.folder), catalog_factory=FakeCatalog)
        self.assertEqual(root, fit)
        self.assertEqual(model_id, 'new_ridge')
        root, _, model_id, _ = inspect_run_selection(str(selected), catalog_factory=FakeCatalog)
        self.assertEqual(root, fit)
        self.assertEqual(model_id, 'new_mlp')
        unlisted = fit / 'models' / 'other.joblib'
        unlisted.write_bytes(b'not trusted')
        with self.assertRaisesRegex(ValueError, '목록'):
            inspect_run_selection(str(unlisted), catalog_factory=FakeCatalog)
        with self.assertRaises(ValueError):
            inspect_run_selection('', catalog_factory=FakeCatalog)


if __name__ == '__main__':
    unittest.main(verbosity=2)
