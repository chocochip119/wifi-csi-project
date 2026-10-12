"""Train-fitted, relative CSI phase features for an unverified S3 LTF layout.

Each RX has one fixed reference bin chosen using training data only. Features
are cos/sin of each bin's phase minus that reference's phase. They remove one
common phase rotation per packet/RX, without requiring a frequency ordering.
They do NOT remove a frequency-dependent SFO/timing slope and are not the
reference repository's unwrapped, linearly detrended phase representation.
"""
from __future__ import annotations

import numpy as np


SCHEMA = 's3_relative_phase_v1'
METHOD = 'relative_phase_sincos'
BYTE_ORDER = 'imaginary_then_real'


def _require(condition, message):
    if not condition:
        raise ValueError(message)


def _integer(value):
    return isinstance(value, (int, np.integer)) and not isinstance(value, (bool, np.bool_))


def _arrays(imag, real, width=None):
    _require(not np.iscomplexobj(imag) and not np.iscomplexobj(real),
             'CSI imaginary and real inputs must be separate real-valued arrays')
    imag, real = np.asarray(imag, dtype=np.float64), np.asarray(real, dtype=np.float64)
    _require(imag.ndim == real.ndim == 2 and imag.shape == real.shape,
             'CSI imaginary/real inputs must have equal 2D [samples, bins] shapes')
    _require(imag.shape[0] > 0 and imag.shape[1] > 0, 'CSI arrays must not be empty')
    if width is not None:
        _require(imag.shape[1] == width, 'CSI bin count differs from phase feature contract')
    _require(np.isfinite(imag).all() and np.isfinite(real).all(),
             'CSI imaginary/real inputs must be finite')
    with np.errstate(over='ignore', invalid='ignore'):
        amplitude = np.hypot(imag, real)
    _require(np.isfinite(amplitude).all(), 'CSI amplitude overflowed; expected signed-byte values')
    return imag, real, amplitude


def _lengths(csi_bytes_per_rx, drop_prefix_bytes):
    _require(_integer(drop_prefix_bytes) and drop_prefix_bytes in (0, 4),
             'drop_prefix_bytes must be 0 or 4')
    _require(isinstance(csi_bytes_per_rx, (list, tuple)) and len(csi_bytes_per_rx) > 0,
             'csi_bytes_per_rx must be a nonempty list of byte lengths')
    _require(all(_integer(n) and drop_prefix_bytes < n <= 512 and n % 2 == 0
                 for n in csi_bytes_per_rx),
             'CSI lengths must be even, greater than the prefix, and at most 512 bytes')
    return [(int(n) - int(drop_prefix_bytes)) // 2 for n in csi_bytes_per_rx]


def fit_phase_transform(train_imag, train_real, csi_bytes_per_rx, drop_prefix_bytes=4):
    """Choose masks/references on train only; return a JSON-serializable contract.

    Inputs contain kept bins, after the configured leading bytes are removed,
    concatenated in fixed RX MAC order. First prefer nonzero coverage, then
    median positive amplitude, then the lowest raw pair index. A bin observed
    as nonzero at least once on train is retained; this is NOT a PHY null mask.
    """
    lengths = _lengths(csi_bytes_per_rx, drop_prefix_bytes)
    _, _, amplitude = _arrays(train_imag, train_real, sum(lengths))
    receivers, warnings, start = [], [], 0
    for rx, length in enumerate(lengths):
        block = amplitude[:, start:start + length]
        nonzero = block > 0
        counts = nonzero.sum(axis=0)
        _require(counts.max() > 0,
                 f'RX {rx}: all training CSI bins are zero; no usable phase reference. '
                 'Inspect capture data before comparing phase features.')
        candidates = np.flatnonzero(counts == counts.max())
        medians = [float(np.median(block[nonzero[:, k], k])) for k in candidates]
        # candidates is sorted, and argmax returns the first exact tie.
        reference = int(candidates[int(np.argmax(medians))])
        coverage = float(nonzero[:, reference].mean())
        mask = counts > 0
        receiver_warnings = []
        if coverage < 0.95:
            receiver_warnings.append('Reference bin is zero in more than 5% of training packets.')
        if int(mask.sum()) < 2:
            receiver_warnings.append('Fewer than two training-observed bins: phase has no varying bin relation.')
        if receiver_warnings:
            warnings.extend(f'RX {rx}: {message}' for message in receiver_warnings)
        receivers.append({
            'rx_order_index': rx, 'start': start, 'stop': start + length,
            'reference_kept_index': reference,
            'reference_raw_pair_index': reference + int(drop_prefix_bytes) // 2,
            'train_observed_nonzero_mask': mask.tolist(),
            'train_reference_nonzero_fraction': coverage,
            'train_observed_bin_count': int(mask.sum()),
            'warnings': receiver_warnings,
        })
        start += length
    return {
        'schema': SCHEMA, 'method': METHOD, 'byte_order': BYTE_ORDER,
        'fit_split': 'train', 'train_sample_count': int(amplitude.shape[0]),
        'drop_prefix_bytes': int(drop_prefix_bytes),
        'csi_bytes_per_rx': [int(n) for n in csi_bytes_per_rx],
        'input_bin_count': start, 'output_feature_count': 2 * start,
        'feature_order': 'cos of all kept bins in RX order, then sin of the same bins',
        'receivers': receivers, 'warnings': warnings,
        'limitations': [
            'Removes one common phase rotation per packet/RX only; no SFO or timing-slope correction.',
            'Does not infer physical subcarrier order or LTF field boundaries.',
            'Different from the original repository\'s unwrapped linear-detrended phase.',
            'Training-observed nonzero mask is empirical, not a standardized PHY null mask.',
            'Missing reference or zero/unobserved bin produces cos=sin=0; rows are preserved.',
            'CSI firmware may truncate at 512 bytes and does not export per-packet PHY layout.',
        ],
    }


def _validate_contract(contract):
    _require(isinstance(contract, dict), 'Phase contract must be an object')
    _require(contract.get('schema') == SCHEMA and contract.get('method') == METHOD
             and contract.get('byte_order') == BYTE_ORDER and contract.get('fit_split') == 'train',
             'Unsupported phase contract schema/method/byte order/fit split')
    lengths = _lengths(contract.get('csi_bytes_per_rx'), contract.get('drop_prefix_bytes'))
    width = sum(lengths)
    _require(_integer(contract.get('input_bin_count')) and contract['input_bin_count'] == width
             and _integer(contract.get('output_feature_count'))
             and contract['output_feature_count'] == 2 * width,
             'Phase contract feature dimensions are inconsistent')
    receivers = contract.get('receivers')
    _require(isinstance(receivers, list) and len(receivers) == len(lengths),
             'Phase contract RX count is inconsistent')
    start = 0
    for rx, (receiver, length) in enumerate(zip(receivers, lengths)):
        _require(isinstance(receiver, dict), 'Invalid phase RX contract')
        expected = {'rx_order_index': rx, 'start': start, 'stop': start + length}
        _require(all(_integer(receiver.get(k)) and receiver[k] == v for k, v in expected.items()),
                 'Phase RX slices must match the stored contiguous RX order')
        reference = receiver.get('reference_kept_index')
        _require(_integer(reference) and 0 <= reference < length,
                 'Phase reference index is outside its RX slice')
        _require(_integer(receiver.get('reference_raw_pair_index'))
                 and receiver['reference_raw_pair_index'] == reference + contract['drop_prefix_bytes'] // 2,
                 'Phase raw reference index does not match prefix removal')
        mask = receiver.get('train_observed_nonzero_mask')
        _require(isinstance(mask, list) and len(mask) == length
                 and all(type(value) is bool for value in mask) and mask[reference],
                 'Phase observed-bin mask is invalid or excludes the reference')
        start += length
    return width


def _valid_bins(amplitude, receiver):
    block = amplitude[:, receiver['start']:receiver['stop']]
    reference = receiver['reference_kept_index']
    valid_reference = block[:, reference] > 0
    valid = ((block > 0) & np.asarray(receiver['train_observed_nonzero_mask'], dtype=bool)
             & valid_reference[:, None])
    return valid, valid_reference


def transform_phase(imag, real, contract):
    """Return float32 [cos(all RX bins), sin(all RX bins)] without refitting.

    Each pair is exp(j*(phase_bin - phase_reference)). Zero or train-unobserved
    bins and whole RX blocks with a missing reference are zero-filled, without
    dropping rows or switching references. No frequency-axis unwrap is used.
    """
    width = _validate_contract(contract)
    imag, real, amplitude = _arrays(imag, real, width)
    unit_imag = np.divide(imag, amplitude, out=np.zeros_like(imag), where=amplitude > 0)
    unit_real = np.divide(real, amplitude, out=np.zeros_like(real), where=amplitude > 0)
    cosine, sine = np.zeros_like(amplitude), np.zeros_like(amplitude)
    for receiver in contract['receivers']:
        start, stop = receiver['start'], receiver['stop']
        reference = start + receiver['reference_kept_index']
        ref_imag, ref_real = unit_imag[:, reference, None], unit_real[:, reference, None]
        valid, _ = _valid_bins(amplitude, receiver)
        cosine[:, start:stop] = np.where(
            valid, unit_real[:, start:stop] * ref_real + unit_imag[:, start:stop] * ref_imag, 0)
        sine[:, start:stop] = np.where(
            valid, unit_imag[:, start:stop] * ref_real - unit_real[:, start:stop] * ref_imag, 0)
    return np.concatenate((cosine, sine), axis=1).astype(np.float32)


def phase_quality(imag, real, contract):
    """Report phase availability on any split without updating train decisions."""
    width = _validate_contract(contract)
    _, _, amplitude = _arrays(imag, real, width)
    receivers = []
    for receiver in contract['receivers']:
        valid, valid_reference = _valid_bins(amplitude, receiver)
        block = amplitude[:, receiver['start']:receiver['stop']]
        mask = np.asarray(receiver['train_observed_nonzero_mask'], dtype=bool)
        receivers.append({
            'rx_order_index': receiver['rx_order_index'],
            'missing_reference_fraction': float((~valid_reference).mean()),
            # A sin value of zero alone is not missing. This measures pairs with both channels zero.
            'zero_phase_fraction': float((~valid).mean()),
            'train_unobserved_nonzero_fraction': float(((block > 0) & ~mask).mean()),
        })
    return {'sample_count': int(amplitude.shape[0]), 'receivers': receivers}
