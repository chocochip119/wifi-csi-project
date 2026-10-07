import importlib.util
from pathlib import Path

import numpy as np
import pytest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("wise_int8_reference", ROOT / "ml/pose/int8_reference.py")
reference = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reference)


def oracle(v, shift):
    v = int(v)
    if shift <= 0:
        return v << min(-shift, 64)
    if shift > abs(v).bit_length() + 1:
        return 0
    quotient, remainder = divmod(abs(v), 1 << shift)
    magnitude = quotient + (remainder >= (1 << (shift - 1)))
    return -magnitude if v < 0 else magnitude


@pytest.mark.parametrize("shift", [-64, -7, -6, -1, 0, 1, 2, 7, 31, 32, 62, 63, 64, 65, 66, 2147483647])
def test_rounding_matches_integer_oracle_at_signed_boundaries(shift):
    values = np.array([-(1 << 63), -(1 << 63) + 1, -129, -128, -127, -8, -6, -4,
                       -3, -2, -1, 0, 1, 2, 3, 4, 6, 8, 127, 128, 129, (1 << 63) - 1], dtype=np.int64)
    actual = reference._rounding_right_shift(values, shift)
    assert list(actual) == [oracle(v, shift) for v in values]


def test_wide_product_does_not_wrap_at_positive_2_to_63():
    acc = np.array([[-(1 << 32)]], dtype=np.int64)
    q = reference.requantize_acc(acc, [-(1 << 31)], [63])
    np.testing.assert_array_equal(q, [[1]])


def test_bias_addition_preserves_33_bits():
    acc, q = reference.linear_int8(np.array([[-1]], dtype=np.int8), np.array([[1]], dtype=np.int8),
                                  np.array([-(1 << 31)], dtype=np.int32),
                                  {"requant_multiplier": [1], "requant_shift": [31]})
    assert int(acc[0, 0]) == -(1 << 31) - 1
    assert int(q[0, 0]) == -1


@pytest.mark.parametrize("divisor", [1, 3, 48])
def test_signed_division_matches_independent_magnitude_oracle(divisor):
    values = np.arange(-8191, 8192, dtype=np.int64)
    expected = [(-1 if v < 0 else 1) * ((2 * abs(int(v)) + divisor) // (2 * divisor)) for v in values]
    np.testing.assert_array_equal(reference._rounding_divide(values, divisor), expected)


def test_constant_negative_pool_is_not_biased():
    x = np.full((1, 32, 128, 10), -1, dtype=np.int8)
    q = reference.adaptive_avg_pool2d_int8(x, {"output_size": [8, 4], "requant_multiplier": 1, "requant_shift": 0})
    np.testing.assert_array_equal(q, x[:, :, :8, :4])


@pytest.mark.parametrize("source", ["CNN_Encoder/requant_stage.v", "CNN_Encoder/Pool.v", "FC/Common/requant_core.v"])
def test_packaged_ip_uses_identical_rtl(source):
    assert (ROOT / "pl/cnn/rtl" / source).read_bytes() == (ROOT / "integration/pose_cnn_1.1/src" / Path(source).name).read_bytes()
