"""Independent integer oracle for both pipelined requantizers, including BRAM timing."""
import random
from pathlib import Path

rng = random.Random(29)
N = 8000
shifts = [-2147483648, -64, -7, -6, -1, 0, 1, 2, 31, 32, 62, 63, 64, 65, 66, 2147483647]
params = []
for i in range(48):
    params.append((shifts[i % len(shifts)], [-2147483648, -1, 1][i // 16],
                   [-2147483648, 0, 2147483647][i // 16]))
Path("params.hex").write_text("".join(f"{s & 0xffffffff:08x}{m & 0xffffffff:08x}{b & 0xffffffff:08x}\n" for s, m, b in params))
vectors, expected = [], []
for i in range(N):
    index = i % 48
    layer, oc = (0, index) if index < 16 else (1, index - 16)
    tag = (rng.randrange(3) << 17) | (layer << 16) | (oc << 11) | (rng.randrange(128) << 4) | rng.randrange(10)
    acc = [-2147483648, -129, -8, -6, -4, -3, -2, -1, 0, 1, 2, 3, 4, 6, 8, 129, 2147483647][(i // 48) % 17] if i < 48 * 17 else rng.randint(-2147483648, 2147483647)
    shift, multiplier, bias = params[index]
    v = (acc + bias) * multiplier
    if shift <= 0:
        v <<= min(-shift, 64)
    elif shift > abs(v).bit_length() + 1:
        v = 0
    else:
        magnitude, remainder = divmod(abs(v), 1 << shift)
        magnitude += remainder >= (1 << (shift - 1))
        v = -magnitude if v < 0 else magnitude
    v = max(-127, min(127, v))
    vectors.append(f"{tag:05x}{acc & 0xffffffff:08x}\n")
    expected.append(f"{tag:05x}{v & 0xff:02x}\n")
Path("vectors.hex").write_text("".join(vectors))
Path("expected.hex").write_text("".join(expected))
print(f"Independent vectors: {N}")
