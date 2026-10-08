"""Exercise real Tk widgets with synthetic display events; no hardware or fitting."""
from pathlib import Path
import sys
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from csi_live_gui import DesktopApp, EMPTY_CHOICE


class PresenceTkChecks(unittest.TestCase):
    def test_real_widgets_empty_then_disconnected_clear_map(self):
        import tkinter as tk
        try:
            window = tk.Tk()
        except tk.TclError as exc:
            self.skipTest(f'Tk display unavailable: {exc}')
        window.withdraw()
        app = None
        try:
            with patch.object(DesktopApp, 'work', lambda self: None), \
                    patch('serial.Serial', side_effect=AssertionError('Physical COM forbidden')):
                app = DesktopApp(window)
                app.worker.join(timeout=1)
                self.assertIn(EMPTY_CHOICE, app.truth['values'])
                state = dict(inference_running=True, serial={'connected': True}, counts={},
                             prediction={'point_id': 'p05', 'monotonic_ns': time.perf_counter_ns()})
                snapshot = dict(state=state, recording={'active': False}, result=None,
                                active_model={'id': 'synthetic-display-event'})
                app.render(snapshot)
                selected = lambda: [item for item in app.map.find_all()
                                    if app.map.type(item) == 'oval'
                                    and app.map.itemcget(item, 'fill') == '#008594']
                self.assertEqual(len(selected()), 1)
                state['prediction'] = dict(point_id='empty', monotonic_ns=time.perf_counter_ns(),
                                          representative_x_cm=None, representative_y_cm=None)
                app.render(snapshot)
                self.assertIn('사람 없음', app.prediction.get())
                self.assertIn('좌표 없음', app.prediction.get())
                self.assertEqual(len(selected()), 0)
                state['serial']['connected'] = False
                app.render(snapshot)
                self.assertEqual(app.prediction.get(), '입력 부족 / 대기')
                self.assertEqual(len(selected()), 0)
                window.update_idletasks()
        finally:
            if app is not None:
                app.closing.set()
            window.destroy()


if __name__ == '__main__':
    unittest.main(verbosity=2)
