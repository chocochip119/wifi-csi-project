"""Presence and nine-point + p05-seated inference from the existing TX USB aggregate stream.

No serial port is opened and no TX command is sent at import/model loading.
Training and inference share location_core transforms. Coordinates denote
the nine collection points; p10 is p05 seated. The trained empty class has no coordinate. Missing
or invalid CSI is an unavailable prediction, never an empty-room prediction.
"""
from __future__ import annotations

from collections import Counter
import copy
import html
import json
import math
from pathlib import Path
import queue
import re
import threading
import time

from .location_core import cycle_from_rows, make_windows, inference_config
from .location_model import load_model, predict_windows
from .labels import CLASSES, EMPTY_LABEL, LOCATION_CLASSES


STALE_NS = 2_000_000_000
STATUS_TTL_NS = 10_000_000_000
RADIO_KEYS = ('tx_mac', 'wifi_channel', 'second_channel', 'protocol_bitmap',
              'timeout_us', 'udp_slot_gap_us')
POINT_IDS = set(LOCATION_CLASSES)
CLASS_IDS = set(CLASSES)


def _mac(value):
    value = str(value).upper()
    if not re.fullmatch(r'(?:[0-9A-F]{2}:){5}[0-9A-F]{2}', value):
        raise ValueError('올바르지 않은 MAC 주소')
    return value


def status_identity(status):
    """Return firmware RX-index mapping without silently reordering features."""
    if status.get('mode') != 'running' or status.get('active_count') != 5:
        raise ValueError('TX Run 상태와 활성 RX 5개가 필요합니다')
    nodes = status.get('nodes', [])
    if len(nodes) != 5 or not all(n.get('connected') and n.get('live') for n in nodes):
        raise ValueError('RX 5개의 connected/live Status가 필요합니다')
    if {n.get('slot_index') for n in nodes} != set(range(5)):
        raise ValueError('RX slot index가 0..4가 아닙니다')
    mapping = {}
    for node in nodes:
        index = node.get('saved_order') if node.get('saved') else node.get('slot_index')
        if index not in range(5) or index in mapping:
            raise ValueError('RX index 순서가 중복되거나 잘못되었습니다')
        mapping[int(index)] = _mac(node.get('mac'))
    if len(set(mapping.values())) != 5:
        raise ValueError('RX MAC 주소가 중복되었습니다')
    radio = {k: status[k] for k in RADIO_KEYS}
    radio['tx_mac'] = _mac(radio['tx_mac'])
    if radio['second_channel'] not in ('above', 'below'):
        raise ValueError('현재 CSI 계약에는 HT40(above/below)이 필요합니다')
    if not isinstance(radio['wifi_channel'], int) or not 1 <= radio['wifi_channel'] <= 14:
        raise ValueError('Wi-Fi 채널이 잘못되었습니다')
    if not isinstance(radio['protocol_bitmap'], int):
        raise ValueError('Wi-Fi protocol_bitmap이 필요합니다')
    if any(not isinstance(radio[k], int) or radio[k] < 0 for k in ('timeout_us', 'udp_slot_gap_us')):
        raise ValueError('TX timeout/slot timing이 잘못되었습니다')
    return mapping, radio


class LiveInferenceEngine:
    """Deterministic single-thread engine, also used by software replay tests.

    Finalize a cycle only at the next frame boundary: a repeated RX invalidates
    that complete frame. Windows begin at the first valid complete cycle after
    reset. No prediction is made until its full wall-clock duration elapses.
    """

    def __init__(self, bundle, *, identity_confirmed=False, predictor=None,
                 status_ttl_ns=STATUS_TTL_NS, enabled=True, inference_stride_s=0.5,
                 on_prediction=None):
        self.bundle = bundle
        self.config = inference_config(bundle['config'], stride_s=(inference_stride_s
                                       if bundle['config'].get('mode', 'window') == 'window' else None))
        if set(bundle['classes']) != CLASS_IDS or set(bundle['points_cm']) != POINT_IDS:
            raise ValueError('사람 없음(empty) + p01~p09 + p10(p05 앉기)의 11클래스 모델이 필요합니다. 기존 5/6클래스 모델은 새 데이터로 재학습하세요.')
        if list(self.config['rx_ids']) != list(range(5)):
            raise ValueError('실시간 입력은 RX index 0..4 순서를 사용합니다')
        self.predictor = predictor or predict_windows
        self.on_prediction = on_prediction
        self.status_ttl_ns = status_ttl_ns
        self.identity_confirmed = bool(identity_confirmed)
        self.expected_mapping = self.config.get('rx_mac_by_index')
        if self.expected_mapping:
            self.expected_mapping = {int(k): _mac(v) for k, v in self.expected_mapping.items()}
            if set(self.expected_mapping) != set(range(5)):
                raise ValueError('모델의 rx_mac_by_index는 0..4 전체를 포함해야 합니다')
        self.enabled = enabled
        self.mapping = self.radio = self.status_ns = self.status_signature = None
        self.input_floor_ns = 0
        self.pinned_mapping = self.pinned_radio = None
        self.counts = Counter()
        self.reject_reasons = Counter()
        self.pending = {}
        self.pending_key = None
        self.pending_bad = False
        self.last_input_ns = self.last_cycle_seq = None
        self.last_valid_ns = self.last_kept_ns = None
        self.cycles = []
        self.window_start_s = None
        self.latest = None
        self.reason = 'TX Status 확인 대기'
        self.identity_blocked = False

    def _drop_window(self, reason):
        self.cycles.clear()
        self.window_start_s = None
        self.last_kept_ns = None
        self.latest = None
        self.reason = str(reason)

    def clear(self, reason, *, forget_status=False, forget_sequence=False):
        self._drop_window(reason)
        self.pending.clear()
        self.pending_key = None
        self.pending_bad = False
        self.last_valid_ns = None
        if forget_status:
            self.mapping = self.radio = self.status_ns = self.status_signature = None
        if forget_sequence:
            self.last_input_ns = self.last_cycle_seq = None

    def confirm_identity(self):
        """Explicitly reconfirm the physical layout/index order after inspection."""
        self.identity_confirmed = True
        self.identity_blocked = False
        self.pinned_mapping = self.pinned_radio = None
        self.clear('배치/RX 순서 확인됨; 새 Status 대기', forget_status=True, forget_sequence=True)

    def set_enabled(self, value):
        self.enabled = bool(value)
        self.clear('새 2초 입력 수집 대기' if value else '추론 정지 (USB 연결 유지)')

    def set_status(self, status, now_ns):
        try:
            mapping, radio = status_identity(status)
            if self.config.get('layout_id') != 'layout_02':
                raise ValueError('layout_02 모델이 필요합니다')
            if self.expected_mapping:
                if mapping != self.expected_mapping:
                    raise ValueError('학습 모델에 저장된 RX index↔MAC과 다릅니다')
            elif not self.identity_confirmed:
                raise ValueError('학습 당시와 현재 layout_02 배치/RX index 순서를 직접 확인하세요')
            expected_radio = self.config.get('radio')
            if expected_radio:
                expected_radio = dict(expected_radio)
                if 'tx_mac' in expected_radio:
                    expected_radio['tx_mac'] = _mac(expected_radio['tx_mac'])
            if expected_radio and any(radio.get(k) != v for k, v in expected_radio.items()):
                raise ValueError('학습 모델의 TX/무선 설정과 다릅니다')
            if self.identity_blocked:
                raise ValueError('RX/무선 설정 변경 후 배치와 순서를 다시 확인해야 합니다')
            if self.pinned_mapping is not None and (mapping != self.pinned_mapping or radio != self.pinned_radio):
                self.identity_blocked = True
                self.identity_confirmed = False
                raise ValueError('현재 연결 중 RX MAC 순서 또는 TX/무선 설정이 변경되었습니다')
            signature = (tuple(sorted(mapping.items())), json.dumps(radio, sort_keys=True), status.get('generation'))
            if signature != self.status_signature:
                self.clear('Status 확인됨; 새로운 완전한 입력 수집 대기', forget_status=True, forget_sequence=True)
                self.input_floor_ns = int(now_ns)
            self.mapping, self.radio = mapping, radio
            self.pinned_mapping, self.pinned_radio = dict(mapping), dict(radio)
            self.status_signature, self.status_ns = signature, int(now_ns)
            return True
        except (KeyError, TypeError, ValueError) as exc:
            self.clear(f'Status 확인 필요: {exc}', forget_status=True, forget_sequence=True)
            self.counts['invalid_status'] += 1
            self.reject_reasons['status: ' + str(exc)] += 1
            return False

    def handle_ack(self, payload):
        unchanged = (self.radio is not None and payload.get('ok')
                     and payload.get('mode') == 'running'
                     and all(payload.get(k) == self.radio[k] for k in
                             ('wifi_channel', 'second_channel', 'timeout_us', 'udp_slot_gap_us')))
        if not unchanged:
            self.clear('TX 상태/설정 ACK 변경; 새 Status 대기', forget_status=True, forget_sequence=True)

    def tick(self, now_ns):
        if self.mapping is None:
            return
        if self.status_ttl_ns is not None and not 0 <= now_ns - self.status_ns <= self.status_ttl_ns:
            self.reject_reasons['status_stale_or_future'] += 1
            self.clear('Status가 오래되었습니다; 다시 조회하세요', forget_status=True)
            return
        if self.last_valid_ns is not None and not 0 <= now_ns - self.last_valid_ns <= STALE_NS:
            self.reject_reasons['valid_csi_stale_or_future'] += 1
            self.clear('최근 2초 동안 유효한 5 RX CSI가 없습니다')
            return
        if self.pending_key is not None and not 0 <= now_ns - self.pending_key[0] <= STALE_NS:
            self.reject_reasons['pending_frame_stale_or_future'] += 1
            self.clear('수신 CSI 프레임이 오래되었습니다')
            return
        # A completed frame remains pending until the next frame boundary so
        # duplicate rows can poison it. Emit from _finish_pending only; a wall
        # clock tick must not omit that last pending frame from an offline-
        # equivalent window just because a USB callback is still arriving.

    def feed(self, row, now_ns):
        # Arrival diagnosis precedes readiness, timing and quality rejection.
        self.counts['received_rows'] += 1
        try:
            received_rx = int(row['rx_index'])
            if received_rx in range(5):
                self.counts[f'received_rx_{received_rx}'] += 1
        except (KeyError, TypeError, ValueError):
            pass
        # The worker calls tick after draining each row; do not emit a window
        # before this row can invalidate a duplicate/partial boundary frame.
        if self.mapping is None or not self.enabled:
            self.counts['not_ready_rows'] += 1
            return None
        if self.status_ttl_ns is not None and not 0 <= now_ns - self.status_ns <= self.status_ttl_ns:
            self.reject_reasons['status_stale_or_future'] += 1
            self.clear('Status가 오래되었습니다; 다시 조회하세요', forget_status=True)
            return None
        before = self.counts['predictions']
        try:
            key = tuple(int(row[k]) for k in ('monotonic_ns', 'uart_seq', 'trigger_seq'))
            rx = int(row['rx_index'])
            if not 0 <= now_ns - key[0] <= STALE_NS:
                raise ValueError('오래되었거나 미래 시각인 CSI')
            if key[0] < self.input_floor_ns:
                raise ValueError('현재 Status 확인 이전의 CSI')
            if any(not 0 <= k <= 0xFFFFFFFF for k in key[1:]):
                raise ValueError('잘못된 CSI sequence')
            if key != self.pending_key:
                if self.last_input_ns is not None and key[0] <= self.last_input_ns:
                    raise ValueError('CSI 주기 시각 중복/역전')
                if self.pending_key is not None:
                    delta = (key[2] - self.pending_key[2]) & 0xFFFFFFFF
                    if delta == 0 or delta >= 0x80000000:
                        raise ValueError('CSI trigger_seq 중복/역전')
                gap_ns = int(float(self.config.get('max_cycle_gap_s', 1.0)) * 1e9)
                if self.last_input_ns is not None and key[0] - self.last_input_ns > gap_ns:
                    self.clear('CSI 수신 간격이 길어 새 입력을 모읍니다', forget_sequence=True)
                    self.counts['gaps'] += 1
                    self.reject_reasons['input_gap_over_limit'] += 1
                if self.pending_key is not None:
                    self._finish_pending(now_ns, watermark_ns=key[0])
                self.pending_key = key
                self.last_input_ns = key[0]
                self.pending_bad = False
        except (KeyError, TypeError, ValueError) as exc:
            # Broken chronology cannot be compared to old buffered samples.
            self.clear(f'CSI 시각/순서 거부: {exc}', forget_sequence=True)
            self.counts['invalid_rows'] += 1
            self.counts['discontinuities'] += 1
            self.reject_reasons['chronology: ' + str(exc)] += 1
            return None
        try:
            if rx not in self.mapping or rx in self.pending:
                raise ValueError('동일 CSI 주기의 RX index 중복/불일치')
            self.counts[f'rx_{rx}'] += 1
            self.pending[rx] = dict(row)
            if int(row['active_nodes']) != 5 or int(row['received_nodes']) != 5:
                raise ValueError('5 RX CSI 미완성 또는 timeout')
            # Validate wire length immediately even if this cycle is later
            # skipped by the 10 Hz throttle.
            if int(row['csi_len']) != int(self.config['csi_len']):
                raise ValueError('모델과 CSI 길이가 다릅니다')
            if len(bytes.fromhex(row['csi_raw_hex'])) != int(row['csi_len']):
                raise ValueError('CSI hex 길이가 맞지 않습니다')
        except (KeyError, TypeError, ValueError) as exc:
            self.pending_bad = True
            self.reason = f'해당 CSI 주기만 제외: {exc}'
            self.counts['invalid_rows'] += 1
            self.reject_reasons['row: ' + str(exc)] += 1
        if self.counts['predictions'] > before:
            return copy.deepcopy(self.latest)
        return None

    def _finish_pending(self, now_ns, *, watermark_ns):
        rows, key, bad = list(self.pending.values()), self.pending_key, self.pending_bad
        self.pending, self.pending_key, self.pending_bad = {}, None, False
        try:
            if bad or len(rows) != 5:
                raise ValueError('불완전하거나 중복된 CSI 주기')
            if not 0 <= now_ns - key[0] <= STALE_NS:
                self._drop_window('오래된 CSI 주기')
                raise ValueError('오래된 CSI 주기')
            self.last_cycle_seq = key[2]
            canonical = [{**r, 'time_s': int(r['monotonic_ns']) / 1e9} for r in rows]
            cycle = cycle_from_rows(canonical, self.config)
            gap_ns = int(float(self.config.get('max_cycle_gap_s', 1.0)) * 1e9)
            if self.last_valid_ns is not None and key[0] - self.last_valid_ns > gap_ns:
                self._drop_window('CSI 수신 간격이 길어 새 입력을 모읍니다')
                self.counts['gaps'] += 1
            self.last_valid_ns = key[0]
            self.counts['valid_cycles'] += 1
            interval_ns = int(round(float(self.config['min_interval_s']) * 1e9))
            if self.last_kept_ns is not None and key[0] - self.last_kept_ns + 1 < interval_ns:
                self.counts['rate_limited_cycles'] += 1
                if self.config.get('mode', 'window') == 'window':
                    self._emit_windows(now_ns, watermark_ns=watermark_ns)
                return
            self.last_kept_ns = key[0]
            if self.config.get('mode', 'window') == 'cycle':
                self._predict([[cycle]], now_ns)
                return
            if self.window_start_s is None:
                self.window_start_s = cycle['time_s']
            self.cycles.append(cycle)
            self._emit_windows(now_ns, watermark_ns=watermark_ns)
        except Exception as exc:
            # Offline rejects just this cycle. Keep the same global 10 Hz
            # throttle and half-open window grid across ordinary RX loss.
            self.reason = f'해당 CSI 주기만 제외: {exc}'
            self.counts['rejected_cycles'] += 1
            self.reject_reasons['cycle: ' + str(exc)] += 1
            if self.config.get('mode', 'window') == 'window':
                self._emit_windows(now_ns, watermark_ns=watermark_ns)

    def _emit_windows(self, now_ns, *, watermark_ns):
        if self.window_start_s is None:
            return
        width = float(self.config['window_s'])
        stride = float(self.config['stride_s'])
        if width <= 0 or stride <= 0:
            self.clear('잘못된 모델 window/stride 설정', forget_status=True)
            return
        # Close only after input timestamps cross the window boundary. A slow
        # worker's wall clock must not close a window before queued frames arrive.
        while self.window_start_s is not None and watermark_ns / 1e9 + 1e-9 >= self.window_start_s + width:
            end_s = self.window_start_s + width
            try:
                windows = make_windows(self.cycles, self.config,
                                       start_s=self.window_start_s, end_s=end_s)
                if windows:
                    self._predict(windows, now_ns, window_start_s=self.window_start_s,
                                  window_end_s=end_s)
                else:
                    self.latest = None
                    self.reason = '2초 창의 유효 주기 수/시간 범위가 부족합니다'
                    self.counts['short_windows'] += 1
                    self.reject_reasons['window_insufficient_cycles_or_span'] += 1
            except Exception as exc:
                self.latest = None
                self.reason = f'추론 오류: {exc}'
                self.counts['inference_errors'] += 1
                self.reject_reasons['inference: ' + str(exc)] += 1
            if self.window_start_s is None:
                return
            self.window_start_s += stride
            self.cycles = [c for c in self.cycles if c['time_s'] >= self.window_start_s - 1e-9]

    def _predict(self, windows, now_ns, *, window_start_s=None, window_end_s=None):
        labels = self.predictor(self.bundle, windows)
        if len(labels) != len(windows):
            raise ValueError('모델 예측 개수가 창 개수와 다릅니다')
        point = str(labels[-1])
        if point not in CLASS_IDS:
            raise ValueError('모델이 알 수 없는 분류값을 반환했습니다')
        stamp_ns = int(round(max(c['time_s'] for c in windows[-1]) * 1e9))
        if not 0 <= now_ns - stamp_ns <= STALE_NS:
            self._drop_window('모델 결과의 CSI가 오래되어 폐기했습니다')
            return
        xy = self.bundle['points_cm'].get(point)
        self.latest = dict(point_id=point, occupied=point != EMPTY_LABEL,
                           representative_x_cm=None if xy is None else xy[0],
                           representative_y_cm=None if xy is None else xy[1],
                           monotonic_ns=stamp_ns, window_cycles=len(windows[-1]),
                           latest_sample_ns=stamp_ns, valid_cycles=len(windows[-1]),
                           window_start_s=window_start_s, window_end_s=window_end_s,
                           window_start_ns=(None if window_start_s is None else int(round(window_start_s * 1e9))),
                           window_end_ns=(None if window_end_s is None else int(round(window_end_s * 1e9))),
                           variant=self.bundle['variant'], family=self.bundle['family'])
        self.counts['predictions'] += len(windows)
        self.reason = ('사람 없음(empty) 분류 결과 · 좌표 없음' if point == EMPTY_LABEL else
                       '사람 있음 · 9개 수집 지점 및 중앙 앉기 중 분류 결과 (좌표는 해당 지점의 대표값)')
        if self.on_prediction is not None:
            try:
                self.on_prediction(copy.deepcopy(self.latest))
            except Exception:
                self.counts['prediction_callback_errors'] += 1

    def snapshot(self):
        return {'prediction': copy.deepcopy(self.latest), 'reason': self.reason,
                'counts': dict(self.counts), 'status_ready': self.mapping is not None,
                'reject_reasons': dict(self.reject_reasons),
                'status_monotonic_ns': self.status_ns, 'inference_running': self.enabled,
                'identity_confirmed': self.identity_confirmed,
                'identity_blocked': self.identity_blocked,
                'rx_mac_by_index': copy.deepcopy(self.mapping), 'radio': copy.deepcopy(self.radio),
                'buffered_cycles': len(self.cycles), 'model_family': self.bundle['family'],
                'model_variant': self.bundle['variant'], 'window_s': self.config['window_s'],
                'model_training_stride_s': self.bundle['config']['stride_s'],
                'inference_stride_s': self.config['stride_s']}


class _InferenceWorker:
    """Bounded mailbox keeps serial callbacks free of expensive model work."""

    def __init__(self, bundle, identity_confirmed=False, *, inference_stride_s=0.5,
                 on_prediction=None):
        self.on_prediction = on_prediction
        self.engine = LiveInferenceEngine(bundle, identity_confirmed=identity_confirmed, enabled=False,
                                          inference_stride_s=inference_stride_s,
                                          on_prediction=self._prediction_event)
        self.mailbox = queue.Queue(maxsize=250)
        self.controls = queue.Queue()
        self.stop_event = threading.Event()
        self.overflow = threading.Event()
        self.state_lock = threading.Lock()
        self.state = self.engine.snapshot()
        self.block_reason = None
        self.thread = threading.Thread(target=self._run, name='location-model', daemon=True)
        self.thread.start()

    def _prediction_event(self, prediction):
        # Never publish an old model result after a stop/reset was queued while
        # its predict() call was running. Events are independent of UI polling.
        with self.state_lock:
            blocked = self.block_reason is not None
        if not blocked and not self.stop_event.is_set() and self.on_prediction is not None:
            self.on_prediction(prediction)

    def submit(self, kind, payload=None):
        if kind in ('reset', 'error', 'closed', 'confirm') or (kind == 'enabled' and not payload):
            with self.state_lock:
                self.block_reason = f'{kind}: {payload or "새 입력 확인 대기"}'
                self.state.update(prediction=None, reason=self.block_reason)
        try:
            target = self.mailbox if kind == 'sample' else self.controls
            # Match SerialInput and TrialRecorder, including the clock epoch.
            target.put_nowait((kind, payload, time.perf_counter_ns()))
        except queue.Full:
            with self.state_lock:
                self.block_reason = '수신 처리량 초과: 이전 입력 폐기'
                self.state.update(prediction=None, reason=self.block_reason)
            self.overflow.set()

    def _run(self):
        while not self.stop_event.is_set():
            try:
                if self.overflow.is_set():
                    while True:
                        try:
                            self.mailbox.get_nowait()
                        except queue.Empty:
                            break
                    self.engine.clear('수신 처리량 초과: 새 Status와 입력 대기', forget_status=True)
                    self.engine.counts['queue_overflows'] += 1
                    self.overflow.clear()
                try:
                    kind, payload, stamp = self.controls.get_nowait()
                except queue.Empty:
                    kind, payload, stamp = self.mailbox.get(timeout=0.05)
                if kind in ('enabled', 'confirm', 'reset', 'error', 'closed'):
                    while True:
                        try:
                            self.mailbox.get_nowait()
                        except queue.Empty:
                            break
                if kind == 'sample':
                    self.engine.feed(payload, time.perf_counter_ns())
                elif kind == 'status':
                    self.engine.set_status(payload, stamp)
                elif kind == 'ack':
                    self.engine.handle_ack(payload)
                elif kind == 'enabled':
                    self.engine.set_enabled(payload)
                elif kind == 'confirm':
                    self.engine.confirm_identity()
                elif kind in ('reset', 'error', 'closed'):
                    self.engine.clear(f'{kind}: {payload or "새 Status 필요"}', forget_status=True, forget_sequence=True)
            except queue.Empty:
                pass
            except Exception as exc:
                self.engine.clear(f'추론 작업 오류: {exc}', forget_status=True)
            self.engine.tick(time.perf_counter_ns())
            with self.state_lock:
                self.state = self.engine.snapshot()
                # A control event posted during a long model call must block
                # that call's older result until all queued control is handled.
                if self.controls.empty() and not self.overflow.is_set():
                    self.block_reason = None

    def snapshot(self):
        now_ns = time.perf_counter_ns()
        with self.state_lock:
            state = copy.deepcopy(self.state)
            blocked = self.block_reason
        pred, stamp = state['prediction'], state['status_monotonic_ns']
        if blocked:
            state.update(prediction=None, reason=blocked)
        elif pred and not 0 <= now_ns - pred['monotonic_ns'] <= STALE_NS:
            state.update(prediction=None, reason='최근 2초의 유효한 CSI 추론 결과가 없습니다')
        elif stamp is not None and not 0 <= now_ns - stamp <= STATUS_TTL_NS:
            state.update(prediction=None, status_ready=False, reason='Status 수신이 오래되었습니다')
        return state

    def close(self):
        self.stop_event.set()
        self.thread.join(timeout=2)


class LiveSession:
    """Notebook controller. start connects; start_inference enables predictions.

    ``send_command('mode run')`` is always explicit. Only read-only ``status``
    commands are polled automatically. stop_inference keeps the port open;
    stop closes the port. Construct a new session after stop.

    Optional callbacks receive independent dict copies. on_sample runs on the
    serial reader thread; on_prediction runs on the model worker. Keep both
    short (queue disk work if needed). Callback failures increment the public
    snapshot callback_errors counters; they do not kill reception/inference.
    """

    def __init__(self, model_path, port, baudrate=115200, identity_confirmed=False, *,
                 inference_stride_s=0.5, on_prediction=None, on_sample=None):
        self.model_path = Path(model_path)
        self.bundle = load_model(self.model_path)
        # Fail early for incompatible models before opening the device.
        LiveInferenceEngine(self.bundle, identity_confirmed=identity_confirmed, enabled=False,
                            inference_stride_s=inference_stride_s)
        self.inference_stride_s = inference_stride_s
        self.port, self.baudrate = str(port), int(baudrate)
        self.identity_confirmed = bool(identity_confirmed)
        self.on_prediction, self.on_sample = on_prediction, on_sample
        self._callback_errors = Counter()
        self._callback_lock = threading.Lock()
        self._model_generation = 0
        self.worker = None
        self.serial = None
        self._stop = threading.Event()
        self._poll_thread = None
        self._started = False

    def start(self):
        if self._started:
            raise RuntimeError('LiveSession은 단일 연결용입니다; 새 객체를 만드세요')
        from serial_input import SerialInput
        self._started = True
        self.worker = self._new_worker(self.bundle, self.identity_confirmed)
        self.serial = SerialInput(self.port, self._on_sample, self._on_event, baudrate=self.baudrate)
        try:
            self.serial.start()
            self._poll_thread = threading.Thread(target=self._poll, name='location-status', daemon=True)
            self._poll_thread.start()
        except Exception:
            self.stop()
            raise
        return self

    def _on_sample(self, row):
        if self.worker is not None and not self._stop.is_set():
            if self.on_sample is not None:
                try:
                    self.on_sample(copy.deepcopy(row))
                except Exception:
                    with self._callback_lock:
                        self._callback_errors['sample'] += 1
            self.worker.submit('sample', row)

    def _new_worker(self, bundle, confirmed):
        generation = self._model_generation
        def prediction_event(prediction):
            if (self._stop.is_set() or generation != self._model_generation
                    or self.on_prediction is None):
                return
            try:
                self.on_prediction(copy.deepcopy(prediction))
            except Exception:
                with self._callback_lock:
                    self._callback_errors['prediction'] += 1
        return _InferenceWorker(bundle, confirmed, inference_stride_s=self.inference_stride_s,
                                on_prediction=prediction_event)

    def _on_event(self, kind, payload):
        if self.worker is not None and not self._stop.is_set():
            self.worker.submit(kind, payload)

    def _poll(self):
        last_poll = -math.inf
        while not self._stop.wait(0.2):
            try:
                if self.serial and self.serial.snapshot()['connected'] and time.perf_counter() - last_poll >= 3:
                    self.serial.send_command('status')
                    last_poll = time.perf_counter()
            except Exception as exc:
                self._on_event('error', str(exc))

    def _require_worker(self):
        if self.worker is None or self._stop.is_set():
            raise RuntimeError('먼저 start()로 USB를 연결하세요')

    def confirm_identity(self):
        self._require_worker()
        self.identity_confirmed = True
        self.worker.submit('confirm')
        self.send_command('status')

    def start_inference(self, identity_confirmed=None):
        self._require_worker()
        if identity_confirmed is not None:
            self.identity_confirmed = bool(identity_confirmed)
        if not self.bundle['config'].get('rx_mac_by_index') and not self.identity_confirmed:
            raise ValueError('현재 배치와 학습 RX index 순서가 같은지 확인 후 identity_confirmed=True로 시작하세요')
        if self.identity_confirmed:
            self.worker.submit('confirm')
        self.worker.submit('enabled', True)
        self.send_command('status')
        return self

    def stop_inference(self):
        self._require_worker()
        self.worker.submit('enabled', False)

    def send_command(self, command):
        self._require_worker()
        if not isinstance(command, str) or not command.strip() or '\n' in command or '\r' in command:
            raise ValueError('줄바꿈 없는 펌웨어 명령 한 개를 입력하세요')
        command = command.strip()
        if command != 'status':
            self.worker.submit('reset', f'명시적 TX 명령: {command}')
        self.serial.send_command(command)

    def switch_model(self, model_path):
        """Load and validate first, then stop inference and discard old buffers."""
        if self._stop.is_set():
            raise RuntimeError('종료된 LiveSession입니다; 다시 연결하려면 새 객체를 만드세요')
        path = Path(model_path)
        bundle = load_model(path)
        LiveInferenceEngine(bundle, identity_confirmed=False, enabled=False,
                            inference_stride_s=self.inference_stride_s)
        old = self.worker
        self._model_generation += 1
        if old is not None:
            old.submit('reset', '모델 교체')
            self.worker = self._new_worker(bundle, False)
            old.close()
        self.model_path, self.bundle = path, bundle
        self.identity_confirmed = False
        if self.serial is not None and self.serial.snapshot()['connected']:
            self.send_command('status')
        return self

    def snapshot(self):
        state = (self.worker.snapshot() if self.worker else
                 {'prediction': None, 'reason': 'USB 연결 전', 'inference_running': False})
        serial = self.serial.snapshot() if self.serial else {'connected': False, 'port': self.port}
        state.update(serial=serial, model_path=str(self.model_path), stopped=self._stop.is_set())
        with self._callback_lock:
            state['callback_errors'] = dict(self._callback_errors)
        if self._stop.is_set() or not serial.get('connected') or serial.get('last_error'):
            state.update(prediction=None, reason=('연결 종료' if self._stop.is_set() else
                                                serial.get('last_error') or 'USB 연결 대기'))
        return state

    def stop(self):
        self._stop.set()
        if self.serial is not None:
            self.serial.stop()
        if self.worker is not None:
            self.worker.close()
        if self._poll_thread and self._poll_thread is not threading.current_thread():
            self._poll_thread.join(timeout=1)
