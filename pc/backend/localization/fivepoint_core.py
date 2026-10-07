"""Shared CSV/live CSI transform. No hardware access and no model fitting on import."""
from __future__ import annotations

from copy import deepcopy
import json
import math
import re

import numpy as np

from .phase_features import fit_phase_transform, transform_phase

from .labels import CLASSES, POINTS_CM
DEFAULT_CONFIG = {
    'layout_id': 'layout_02', 'mode': 'window', 'variant': 'amp_rssi',
    'rx_ids': [0, 1, 2, 3, 4], 'rx_mac_by_index': None,
    'csi_len': 384, 'drop_pairs': 2,
    'window_s': 2.0, 'stride_s': 2.0, 'min_interval_s': 0.1,
    'max_cycle_span_s': 0.1, 'min_window_cycles': 10, 'min_window_span_s': 1.0,
    'trim_start_s': 2.0, 'trim_end_s': 2.0,
}


def _require(test, message):
    if not test:
        raise ValueError(message)


def _integer(value, name):
    _require(not isinstance(value, (bool, np.bool_)), f'{name}: boolean is not an integer')
    try:
        f = float(value)
    except (TypeError, ValueError) as exc:
        raise ValueError(f'{name}: expected integer') from exc
    _require(math.isfinite(f) and f == math.floor(f), f'{name}: expected finite integer')
    return int(f)


def normalize_mac(value):
    compact = re.sub(r'[:-]', '', str(value)).lower()
    _require(bool(re.fullmatch(r'[0-9a-f]{12}', compact)), 'Invalid RX MAC address')
    return ':'.join(compact[i:i+2] for i in range(0, 12, 2))


def validate_config(config=None):
    cfg = deepcopy(DEFAULT_CONFIG)
    if config is not None:
        _require(isinstance(config, dict), 'config must be a dict')
        cfg.update(deepcopy(config))
    _require(bool(re.fullmatch(r'layout_\d{2,}', str(cfg['layout_id']))), 'layout_id must be layout_NN')
    _require(cfg['mode'] in ('window', 'cycle'), 'mode must be window or cycle')
    _require(cfg['variant'] in ('amp_rssi', 'amp_phase_rssi'), 'Unknown input variant')
    ids = [_integer(n, 'rx_ids') for n in cfg['rx_ids']]
    _require(len(ids) == len(set(ids)) == 5 and all(0 <= n <= 255 for n in ids), 'Exactly five unique RX IDs required')
    cfg['rx_ids'] = ids  # Explicit user order is part of the model contract.
    cfg['csi_len'] = _integer(cfg['csi_len'], 'csi_len')
    cfg['drop_pairs'] = _integer(cfg['drop_pairs'], 'drop_pairs')
    _require(cfg['csi_len'] == 384 and cfg['drop_pairs'] == 2,
             'This HT40 pipeline expects 384 CSI bytes and drops the first two pairs per RX')
    for key in ('window_s', 'stride_s', 'min_interval_s', 'max_cycle_span_s',
                'min_window_span_s', 'trim_start_s', 'trim_end_s'):
        cfg[key] = float(cfg[key])
        _require(math.isfinite(cfg[key]) and cfg[key] >= 0, f'{key} must be finite and nonnegative')
    _require(cfg['window_s'] > 0 and cfg['stride_s'] > 0 and cfg['min_interval_s'] > 0,
             'Window, stride and minimum cycle interval must be positive')
    cfg['min_window_cycles'] = _integer(cfg['min_window_cycles'], 'min_window_cycles')
    _require(cfg['min_window_cycles'] >= 1, 'min_window_cycles must be at least one')
    if cfg['mode'] == 'window':
        _require(cfg['min_window_span_s'] < cfg['window_s'],
                 'min_window_span_s must be less than window_s; adjust it for shorter windows')
        _require(cfg['min_window_cycles'] <= math.ceil(cfg['window_s'] / cfg['min_interval_s']),
                 'Minimum window cycles exceeds possible samples at configured interval')
    mapping = cfg.get('rx_mac_by_index')
    if mapping is not None:
        _require(isinstance(mapping, dict), 'rx_mac_by_index must be a dict or None')
        normalized = {str(_integer(k, 'RX mapping index')): normalize_mac(v) for k, v in mapping.items()}
        _require(set(normalized) == {str(n) for n in ids} and len(set(normalized.values())) == 5,
                 'RX MAC mapping must contain the five configured IDs and unique MACs')
        cfg['rx_mac_by_index'] = normalized
    return cfg


def inference_config(config, *, stride_s=None):
    """Copy the model contract, optionally changing only the output cadence."""
    cfg = validate_config(config)
    if stride_s is not None:
        _require(cfg['mode'] == 'window', 'Inference stride override requires window mode')
        _require(not isinstance(stride_s, (bool, np.bool_)), 'Stride must be a number, not boolean')
        cfg['stride_s'] = stride_s
        cfg = validate_config(cfg)
    return cfg


def _decode_iq(row, cfg):
    raw_hex = row.get('csi_raw_hex')
    if isinstance(raw_hex, str) and raw_hex.strip():
        try:
            raw = bytes.fromhex(raw_hex)
        except ValueError as exc:
            raise ValueError('Invalid raw CSI hex') from exc
        _require(len(raw) == cfg['csi_len'], 'Raw CSI length mismatch')
        iq = np.frombuffer(raw, dtype=np.int8).astype(np.float64).reshape(-1, 2)
    else:
        value = row.get('iq_pairs')
        if isinstance(value, str):
            try:
                value = json.loads(value)
            except (TypeError, ValueError) as exc:
                raise ValueError('Invalid iq_pairs JSON') from exc
        try:
            iq = np.asarray(value, dtype=np.float64)
        except (TypeError, ValueError) as exc:
            raise ValueError('Invalid IQ values') from exc
        _require(iq.shape == (cfg['csi_len'] // 2, 2), 'IQ pairs must have shape (192,2)')
    _require(np.isfinite(iq).all() and (iq >= -128).all() and (iq <= 127).all()
             and (iq == np.floor(iq)).all(), 'IQ values must be signed int8 values')
    return iq[cfg['drop_pairs']:]


def cycle_from_rows(rows, config=None):
    """Validate one complete trigger. Rows use normalized time_s in seconds.

    Firmware convention assumed [imaginary, real]. Physical LTF/bin mapping
    is not inferred. Exactly five RX rows are required; never fill missing RX.
    """
    cfg = validate_config(config)
    rows = list(rows)
    _require(len(rows) == 5, 'A complete cycle requires exactly five rows')
    ids = [_integer(r['rx_index'], 'rx_index') for r in rows]
    _require(len(set(ids)) == 5 and set(ids) == set(cfg['rx_ids']), 'Missing, duplicate or unexpected RX')
    seqs = [_integer(r['trigger_seq'], 'trigger_seq') for r in rows]
    _require(len(set(seqs)) == 1 and 0 <= seqs[0] <= 0xFFFFFFFF, 'Trigger sequence mismatch')
    times = np.asarray([float(r['time_s']) for r in rows])
    _require(np.isfinite(times).all(), 'Cycle timestamps must be finite')
    _require(float(np.ptp(times)) <= cfg['max_cycle_span_s'] + 1e-9, 'RX time span exceeds configured limit')
    by_id = dict(zip(ids, rows))
    imag, real, rss = [], [], []
    for rx in cfg['rx_ids']:
        row = by_id[rx]
        _require(_integer(row['csi_len'], 'csi_len') == cfg['csi_len'], 'CSI length does not match trained layout')
        for key in ('active_nodes', 'received_nodes'):
            if key in row:
                _require(_integer(row[key], key) == 5, 'Incomplete firmware cycle')
        rssi = float(row['rssi'])
        _require(math.isfinite(rssi) and -128 <= rssi <= 127, 'RSSI must be finite signed-byte dBm value')
        iq = _decode_iq(row, cfg)
        imag.extend(iq[:, 0])
        real.extend(iq[:, 1])
        rss.append(rssi)
    return {'time_s': float(times.min()), 'trigger_seq': seqs[0],
            'imag': np.asarray(imag, dtype=np.float64),
            'real': np.asarray(real, dtype=np.float64), 'rssi': np.asarray(rss, dtype=np.float64)}


def make_windows(cycles, config=None, *, start_s, end_s):
    """Complete half-open windows in supplied bounds; caller owns edge trimming.

    Throttle accepted cycles once across the interval before grouping, so each
    overlapping window uses the same retained cycles. Does not fit anything.
    """
    cfg = validate_config(config)
    start_s, end_s = float(start_s), float(end_s)
    _require(math.isfinite(start_s) and math.isfinite(end_s) and end_s >= start_s, 'Invalid time bounds')
    selected, previous, previous_seq, last_kept = [], None, None, -math.inf
    for cycle in cycles:
        t = float(cycle['time_s'])
        _require(math.isfinite(t), 'Non-finite cycle timestamp')
        if previous is not None:
            _require(t > previous, 'Cycle timestamps must increase strictly')
            _require(cycle['trigger_seq'] != previous_seq, 'Repeated trigger in consecutive cycles')
        previous, previous_seq = t, cycle['trigger_seq']
        if start_s <= t < end_s and t - last_kept + 1e-9 >= cfg['min_interval_s']:
            selected.append(cycle)
            last_kept = t
    if cfg['mode'] == 'cycle':
        return [[cycle] for cycle in selected]
    result, offset = [], 0
    while start_s + offset * cfg['stride_s'] + cfg['window_s'] <= end_s + 1e-9:
        begin = start_s + offset * cfg['stride_s']
        stop = begin + cfg['window_s']
        group = [c for c in selected if begin <= c['time_s'] < stop]
        if (len(group) >= cfg['min_window_cycles'] and
                group[-1]['time_s'] - group[0]['time_s'] + 1e-9 >= cfg['min_window_span_s']):
            result.append(group)
        offset += 1
    return result


def _arrays(group, cfg):
    width = 5 * (cfg['csi_len'] // 2 - cfg['drop_pairs'])
    _require(bool(group), 'Cannot transform an empty window')
    imag = np.stack([c['imag'] for c in group]).astype(np.float64)
    real = np.stack([c['real'] for c in group]).astype(np.float64)
    rssi = np.stack([c['rssi'] for c in group]).astype(np.float64)
    _require(imag.shape == real.shape == (len(group), width) and rssi.shape == (len(group), 5),
             'Feature cycle dimensions do not match model')
    _require(np.isfinite(imag).all() and np.isfinite(real).all() and np.isfinite(rssi).all(),
             'Non-finite cycle input')
    return imag, real, rssi


def fit_phase(windows, config=None):
    """Call with train windows only. Repeated overlapping references counted once."""
    cfg = validate_config(config)
    unique = {id(cycle): cycle for group in windows for cycle in group}
    imag, real, _ = _arrays(list(unique.values()), cfg)
    return fit_phase_transform(imag, real, [cfg['csi_len']] * 5, cfg['drop_pairs'] * 2)


def make_features(windows, config=None, phase_contract=None):
    cfg = validate_config(config)
    width = 5 * (cfg['csi_len'] // 2 - cfg['drop_pairs'])
    use_phase = cfg['variant'] == 'amp_phase_rssi'
    _require(not use_phase or phase_contract is not None, 'Saved train-only phase reference required')
    features = []
    for group in windows:
        imag, real, rssi = _arrays(group, cfg)
        blocks = [np.hypot(imag, real).mean(axis=0), rssi.mean(axis=0)]
        if use_phase:
            blocks.append(transform_phase(imag, real, phase_contract).mean(axis=0))
        features.append(np.concatenate(blocks))
    return (np.stack(features).astype(np.float64) if features
            else np.empty((0, width + 5 + (2 * width if use_phase else 0)), dtype=np.float64))
