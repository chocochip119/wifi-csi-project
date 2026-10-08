"""Software-only replay: no serial ports, TX commands, or model fitting."""
from __future__ import annotations

import copy
import csv
from pathlib import Path
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from location_core import CLASSES, POINTS_CM, DEFAULT_CONFIG, cycle_from_rows, make_features, make_windows
from location_live import LiveInferenceEngine, LiveSession, status_identity, _InferenceWorker
from live_recording import TrialRecorder
from serial_input import SerialInput, DEFAULT_REFERENCE, _load_reference, _guard_cycle_parser
from labels import EMPTY_LABEL, LOCATION_CLASSES


def bundle(**config):
    return dict(config={**copy.deepcopy(DEFAULT_CONFIG), **config}, variant='amp_rssi', family='test_model',
                classes=list(CLASSES), points_cm=copy.deepcopy(POINTS_CM), phase_contract=None)


def status():
    return dict(mode='running', active_count=5, wifi_channel=6, second_channel='above',
                protocol_bitmap=7, timeout_us=5000, udp_slot_gap_us=1000,
                generation=1, tx_mac='AA:BB:CC:DD:EE:FF',
                nodes=[dict(slot_index=i, saved_order=i, saved=True, connected=True, live=True,
                            mac=f'00:11:22:33:44:{i:02X}') for i in range(5)])


def frame(t, seq):
    rows = []
    for rx in range(5):
        iq = np.zeros((192, 2), dtype=np.int8)
        iq[:, 0] = np.arange(192) % 31 + (seq % 7)
        iq[:, 1] = rx + 3
        rows.append(dict(monotonic_ns=int(round(t * 1e9)), uart_seq=seq, trigger_seq=seq,
                         rx_index=rx, rssi=-40-rx-(seq % 4), csi_len=384,
                         csi_raw_hex=iq.tobytes().hex(), active_nodes=5,
                         received_nodes=5, timeout_fired=0))
    return rows


def feed(engine, rows, now_ns=None):
    for row in rows:
        engine.feed(row, row['monotonic_ns'] if now_ns is None else now_ns)


def canonical(rows, config):
    return cycle_from_rows([{**r, 'time_s': r['monotonic_ns']/1e9} for r in rows], config)


class LiveChecks(unittest.TestCase):
    def engine(self, **cfg):
        captures, events = [], []
        def predict(model, windows):
            captures.extend(copy.deepcopy(windows))
            # A deterministic feature-based predictor checks inference inputs,
            # without fitting any estimator or reusing a previous model.
            return [CLASSES[int(np.floor(row[0])) % 5] for row in make_features(windows, model['config'])]
        result = LiveInferenceEngine(bundle(**cfg), identity_confirmed=True,
                                     predictor=predict, on_prediction=events.append)
        self.assertTrue(result.set_status(status(), 9_000_000_000))
        return result, captures, events

    def test_full_window_boundary_features_and_event_metadata(self):
        engine, captures, events = self.engine()
        all_cycles = []
        for n in range(40):
            rows = frame(10 + n*.05, n)
            all_cycles.append(canonical(rows, engine.config))
            feed(engine, rows)
            self.assertIsNone(engine.latest)
        feed(engine, frame(12, 40))
        offline = make_windows(all_cycles, engine.config, start_s=10, end_s=12)
        np.testing.assert_array_equal(make_features(captures, engine.config), make_features(offline, engine.config))
        self.assertEqual(make_features(captures, engine.config).shape, (1, 955))
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]['window_start_ns'], 10_000_000_000)
        self.assertEqual(events[0]['window_end_ns'], 12_000_000_000)
        self.assertEqual(events[0]['latest_sample_ns'], 11_900_000_000)
        self.assertEqual(events[0]['valid_cycles'], 20)
        events[0]['point_id'] = 'mutated'
        self.assertNotEqual(engine.latest['point_id'], 'mutated')

    def test_arrival_counts_and_reason_counts_include_rejected_rows(self):
        engine, _, _ = self.engine()
        feed(engine, frame(10, 0))
        # All five rows are received even though this timestamp is stale.
        feed(engine, frame(10.1, 1), now_ns=13_000_000_000)
        state = engine.snapshot()
        self.assertEqual(state['counts']['received_rows'], 10)
        self.assertEqual([state['counts'][f'received_rx_{r}'] for r in range(5)], [2]*5)
        self.assertEqual(sum(state['reject_reasons'].values()), 5)
        self.assertFalse(state['prediction'])

    def test_empty_requires_full_valid_window_and_has_no_coordinate(self):
        engine, _, events = self.engine()
        engine.predictor = lambda model, windows: [EMPTY_LABEL] * len(windows)
        self.assertIsNone(engine.snapshot()['prediction'])
        for n in range(40):
            feed(engine, frame(10 + n*.05, n))
            self.assertIsNone(engine.snapshot()['prediction'])
        feed(engine, frame(12, 40))
        pred = engine.snapshot()['prediction']
        self.assertEqual(pred['point_id'], EMPTY_LABEL)
        self.assertFalse(pred['occupied'])
        self.assertIsNone(pred['representative_x_cm'])
        self.assertIsNone(pred['representative_y_cm'])
        self.assertEqual(len(events), 1)
        engine.tick(14_100_000_001)
        self.assertIsNone(engine.snapshot()['prediction'])

    def test_missing_rx_never_becomes_empty_prediction(self):
        engine, _, events = self.engine()
        engine.predictor = lambda *_: self.fail('Missing-RX input reached the classifier')
        for n in range(61):
            rows = frame(10 + n*.05, n)[:4]
            for row in rows:
                row['received_nodes'] = 4
                row['timeout_fired'] = 1
            feed(engine, rows)
        self.assertFalse(events)
        self.assertIsNone(engine.snapshot()['prediction'])
        self.assertGreater(engine.counts['rejected_cycles'], 0)

    def test_five_class_model_is_rejected_in_presence_ui(self):
        old = bundle()
        old['classes'] = list(LOCATION_CLASSES)
        with self.assertRaisesRegex(ValueError, '11클래스'):
            LiveInferenceEngine(old)

    def test_fast_usb_cycles_keep_inference_and_trial_on_the_same_clock(self):
        # Reproduce short USB arrivals while the Windows-style coarse clock
        # repeats. Exercise the actual bundled parser and serial adapter,
        # without opening a port, sending commands, or fitting a model.
        parser = _load_reference(DEFAULT_REFERENCE)
        self.addCleanup(sys.modules.pop, parser.__name__, None)
        _guard_cycle_parser(parser)
        engine, captures, events = self.engine()
        base_predictor = engine.predictor
        def empty_prediction(model, windows):
            base_predictor(model, windows)  # Retain feature/capture checks.
            return [EMPTY_LABEL] * len(windows)
        engine.predictor = empty_prediction
        base_ns = 10_005_000_000
        clock_ns = [base_ns]
        with tempfile.TemporaryDirectory() as folder, \
                patch('time.monotonic_ns', side_effect=lambda: clock_ns[0] // 16_000_000 * 16_000_000), \
                patch('time.perf_counter_ns', side_effect=lambda: clock_ns[0]), \
                patch('serial.Serial', side_effect=AssertionError('Real COM open forbidden')):
            recorder = TrialRecorder(folder)
            recorder.start(dict(id='clock-test', sha256='a'*64), EMPTY_LABEL, 5, raw=True)

            def receive(row):
                recorder.on_sample(row)
                engine.feed(row, clock_ns[0])

            def predicted(event):
                events.append(event)
                recorder.on_prediction(event)

            engine.on_prediction = predicted
            reader = SerialInput('MOCK_ONLY', receive, lambda *_: None)
            try:
                for seq in range(601):
                    clock_ns[0] = base_ns + seq * 5_000_000
                    rows = frame(clock_ns[0] / 1e9, seq)
                    payload = parser.CYCLE_HEADER.pack(
                        seq, seq, clock_ns[0] // 1000, clock_ns[0] // 1000,
                        5000, 5, 5, 0, 0)
                    for row in rows:
                        payload += parser.CYCLE_SLOT.pack(row['rx_index'], 1, row['rssi'], 0, 384)
                        payload += bytes.fromhex(row['csi_raw_hex'])
                    reader._handle_event('cycle', parser.parse_cycle(payload))
                self.assertIsNone(reader.snapshot()['last_error'])
                self.assertEqual(reader.snapshot()['received_rows_by_rx'], dict.fromkeys(range(5), 601))
                self.assertEqual(reader.snapshot()['csi_len_by_rx'], dict.fromkeys(range(5), 384))
                self.assertEqual(engine.counts['discontinuities'], 0)
                self.assertEqual(engine.counts['rejected_cycles'], 0)
                self.assertEqual([engine.counts[f'rx_{rx}'] for rx in range(5)], [601]*5)
                self.assertEqual(len(captures), 3)
                self.assertEqual(len(events), 3)
                self.assertEqual(recorder.begin_ns, base_ns)
                self.assertEqual(recorder.snapshot()['remaining_s'], 2)
            finally:
                result = recorder.finish('test_complete')
            self.assertEqual(result['predictions'], 3)
            self.assertEqual(result['raw_rows'], 601*5)
            self.assertEqual(result['elapsed_seconds'], 3)
            self.assertEqual(result['correct'], 3)
            self.assertEqual(result['class_recall'], 1)
            self.assertEqual(result['subject'], 'none')
            with (Path(result['folder']) / 'predictions.csv').open(encoding='utf-8-sig', newline='') as handle:
                predictions = list(csv.DictReader(handle))
            self.assertEqual([row['prediction'] for row in predictions], ['empty']*3)
            self.assertTrue(all(row['representative_x_cm'] == row['representative_y_cm'] == '' for row in predictions))
            with (Path(result['folder']) / 'csi.csv').open(encoding='utf-8-sig', newline='') as handle:
                saved = next(csv.DictReader(handle))
            self.assertEqual(saved['csi_raw_hex'], frame(base_ns / 1e9, 0)[0]['csi_raw_hex'])
            self.assertEqual(int(saved['monotonic_ns']), base_ns)

    def test_missing_duplicate_and_bad_length_cycles_preserve_offline_overlap_parity(self):
        engine, captures, events = self.engine()
        accepted = []
        rejected = {3, 8, 12, 27, 34, 53}
        for n in range(102):
            rows = frame(10 + n*.04, n)
            if n in {3, 27}:  # Actual missing RX as reported by firmware.
                rows = rows[:4]
                for row in rows:
                    row['received_nodes'] = 4
                    row['timeout_fired'] = 1
            elif n in {8, 34}:
                rows[1]['csi_len'] = 382
                rows[1]['csi_raw_hex'] = rows[1]['csi_raw_hex'][:-4]
            elif n in {12, 53}:
                rows.append(copy.deepcopy(rows[0]))
            else:
                accepted.append(canonical(rows, engine.config))
            feed(engine, rows)
        offline = make_windows(accepted, engine.config, start_s=10, end_s=14)
        self.assertEqual(len(captures), 5)
        self.assertEqual(engine.counts['rejected_cycles'], len(rejected))
        self.assertEqual(engine.counts['gaps'], 0)
        self.assertEqual([[c['trigger_seq'] for c in group] for group in captures],
                         [[c['trigger_seq'] for c in group] for group in offline])
        xf, xo = make_features(captures, engine.config), make_features(offline, engine.config)
        np.testing.assert_array_equal(xf, xo)
        expected = [CLASSES[int(np.floor(row[0])) % 5] for row in xo]
        self.assertEqual([e['point_id'] for e in events], expected)
        self.assertEqual([e['window_start_s'] for e in events], [10, 10.5, 11, 11.5, 12])

    def test_complete_cycle_timeout_flag_matches_shared_offline_filter(self):
        engine, captures, _ = self.engine(mode='cycle')
        rows = frame(10, 0)
        for row in rows:
            row['timeout_fired'] = 1
        accepted = canonical(rows, engine.config)
        feed(engine, rows)
        feed(engine, frame(10.1, 1))
        self.assertEqual(len(captures), 1)
        np.testing.assert_array_equal(make_features(captures, engine.config),
                                      make_features([[accepted]], engine.config))


    def test_worker_delay_does_not_close_before_input_boundary(self):
        engine, captures, _ = self.engine()
        for n in range(40):
            rows = frame(10+n*.05, n)
            feed(engine, rows, rows[0]['monotonic_ns']+500_000_000)
            self.assertIsNone(engine.latest)
        feed(engine, frame(12, 40), 12_500_000_000)
        self.assertEqual(len(captures), 1)
        self.assertEqual(len(captures[0]), 20)

    def test_long_gap_immediately_discards_previous_prediction_and_grid(self):
        engine, captures, _ = self.engine()
        for n in range(43):
            feed(engine, frame(10+n*.05, n))
        self.assertIsNotNone(engine.latest)
        feed(engine, frame(13.4, 43))
        self.assertIsNone(engine.latest)
        self.assertFalse(engine.cycles)
        self.assertEqual(engine.counts['gaps'], 1)
        feed(engine, frame(13.5, 44))
        self.assertAlmostEqual(engine.window_start_s, 13.4)
        self.assertEqual(len(captures), 1)

    def test_time_and_trigger_regressions_clear_buffer(self):
        for row in (frame(10.05, 3)[0], frame(10.2, 0)[0], frame(10.2, 1)[0]):
            engine, _, _ = self.engine()
            feed(engine, frame(10, 0))
            feed(engine, frame(10.1, 1))
            feed(engine, [row])
            self.assertFalse(engine.cycles)
            self.assertFalse(engine.pending)
            self.assertIsNone(engine.latest)
            self.assertEqual(engine.counts['discontinuities'], 1)

    def test_trigger_wrap_is_forward_progress(self):
        engine, captures, _ = self.engine(mode='cycle')
        feed(engine, frame(10, 0xFFFFFFFE))
        feed(engine, frame(10.1, 0xFFFFFFFF))
        feed(engine, frame(10.2, 0))
        feed(engine, frame(10.3, 1))
        self.assertEqual(len(captures), 3)
        self.assertEqual(engine.counts['discontinuities'], 0)

    def test_stale_csi_and_status_clear_display(self):
        engine, _, _ = self.engine(mode='cycle')
        feed(engine, frame(10, 0))
        feed(engine, frame(10.1, 1))
        engine.tick(12_100_000_001)
        self.assertIsNone(engine.latest)
        self.assertFalse(engine.pending)
        engine.tick(20_000_000_000)
        self.assertFalse(engine.snapshot()['status_ready'])

    def test_explicit_and_recorded_mac_mapping_enforced(self):
        engine = LiveInferenceEngine(bundle(), predictor=lambda *_: ['p05'])
        self.assertFalse(engine.set_status(status(), 1))
        engine.confirm_identity()
        self.assertTrue(engine.set_status(status(), 2))
        changed = status()
        changed['nodes'][0]['mac'], changed['nodes'][1]['mac'] = changed['nodes'][1]['mac'], changed['nodes'][0]['mac']
        self.assertFalse(engine.set_status(changed, 3))
        self.assertTrue(engine.identity_blocked)
        engine.confirm_identity()
        self.assertTrue(engine.set_status(changed, 4))
        mapping, _ = status_identity(status())
        pinned = LiveInferenceEngine(bundle(rx_mac_by_index=mapping))
        pinned.confirm_identity()
        self.assertFalse(pinned.set_status(changed, 1))

    def test_ack_radio_and_generation_changes_require_new_input(self):
        engine, _, _ = self.engine()
        feed(engine, frame(10, 0))
        feed(engine, frame(10.1, 1))
        unchanged = dict(ok=True, mode='running', wifi_channel=6, second_channel='above',
                         timeout_us=5000, udp_slot_gap_us=1000)
        engine.handle_ack(unchanged)
        self.assertTrue(engine.cycles)
        update = status()
        update['generation'] = 2
        engine.set_status(update, 10_100_000_001)
        self.assertFalse(engine.cycles)
        self.assertFalse(engine.pending)
        feed(engine, frame(10.1, 1), 10_200_000_000)
        self.assertFalse(engine.cycles)
        engine.handle_ack({**unchanged, 'mode': 'wait'})
        self.assertIsNone(engine.mapping)

    def test_stop_restart_cannot_reuse_old_window(self):
        engine, captures, _ = self.engine()
        for n in range(43):
            feed(engine, frame(10+n*.05, n))
        engine.set_enabled(False)
        self.assertFalse(engine.cycles)
        self.assertFalse(engine.pending)
        self.assertIsNone(engine.latest)
        feed(engine, frame(12.2, 44))
        self.assertFalse(engine.pending)
        engine.set_enabled(True)
        for n in range(40):
            feed(engine, frame(12.3+n*.05, 45+n))
            self.assertIsNone(engine.latest)
        feed(engine, frame(14.3, 85))
        self.assertEqual(len(captures), 2)

    def test_model_switch_without_hardware_stops_and_reconfirms(self):
        events, samples = [], []
        with patch('location_live.load_model', return_value=bundle()) as mocked:
            session = LiveSession('old.joblib', 'COM_TEST', identity_confirmed=True,
                                  on_prediction=events.append, on_sample=samples.append)
            self.assertIsNone(session.serial)
            session.switch_model('new.joblib')
            self.assertFalse(session.identity_confirmed)
            self.assertEqual(session.model_path, Path('new.joblib'))
            self.assertEqual(mocked.call_count, 2)
            self.assertIsNone(session.snapshot()['prediction'])
            self.assertEqual(session.inference_stride_s, .5)
            session.stop()
            self.assertTrue(session.snapshot()['stopped'])
            self.assertFalse(events)
            self.assertFalse(samples)

    def test_callback_failure_does_not_discard_valid_prediction(self):
        engine, captures, _ = self.engine(mode='cycle')
        def broken(_):
            raise OSError('disk full in optional logger')
        engine.on_prediction = broken
        feed(engine, frame(10, 0))
        feed(engine, frame(10.1, 1))
        self.assertEqual(len(captures), 1)
        self.assertIsNotNone(engine.latest)
        self.assertEqual(engine.counts['prediction_callback_errors'], 1)

    def test_stop_during_slow_prediction_suppresses_event(self):
        entered, release = threading.Event(), threading.Event()
        events = []
        worker = _InferenceWorker(bundle(mode='cycle'), True, on_prediction=events.append)
        def slow_prediction(model, windows):
            entered.set()
            if not release.wait(2):
                raise RuntimeError('test release timed out')
            return ['p05'] * len(windows)
        worker.engine.predictor = slow_prediction
        try:
            worker.submit('status', status())
            worker.submit('enabled', True)
            deadline = time.monotonic() + 2
            while not worker.snapshot()['status_ready'] and time.monotonic() < deadline:
                time.sleep(.005)
            self.assertTrue(worker.snapshot()['status_ready'])
            t = time.perf_counter()
            for row in frame(t, 0):
                worker.submit('sample', row)
            time.sleep(.11)
            for row in frame(time.perf_counter(), 1):
                worker.submit('sample', row)
            self.assertTrue(entered.wait(2))
            worker.submit('enabled', False)
            release.set()
            deadline = time.monotonic() + 2
            while worker.snapshot()['inference_running'] and time.monotonic() < deadline:
                time.sleep(.005)
            self.assertFalse(worker.snapshot()['inference_running'])
            self.assertFalse(events)
            self.assertIsNone(worker.snapshot()['prediction'])
        finally:
            release.set()
            worker.close()

    def test_connected_model_switch_replaces_worker_and_stopped_session_cannot_restart(self):
        class FakeSerial:
            def __init__(self, port, on_sample, on_event, **kw):
                self.connected = False
                self.on_event = on_event
            def start(self):
                self.connected = True
            def stop(self):
                self.connected = False
            def snapshot(self):
                return {'connected': self.connected}
            def send_command(self, text):
                if text == 'status':
                    self.on_event('status', status())
        with patch('location_live.load_model', return_value=bundle()), patch('serial_input.SerialInput', FakeSerial):
            session = LiveSession('old.joblib', 'COM_TEST', identity_confirmed=True).start()
            try:
                old = session.worker
                session.switch_model('new.joblib')
                self.assertIsNot(session.worker, old)
                self.assertFalse(old.thread.is_alive())
                self.assertFalse(session.worker.engine.enabled)
                self.assertFalse(session.identity_confirmed)
                self.assertIsNone(session.snapshot()['prediction'])
            finally:
                session.stop()
            with self.assertRaises(RuntimeError):
                session.switch_model('third.joblib')


if __name__ == '__main__':
    unittest.main()
