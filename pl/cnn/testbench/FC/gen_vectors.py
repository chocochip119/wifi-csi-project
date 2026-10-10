"""Deterministic FC fixtures; Python integers are the independent arithmetic oracle."""
import argparse
import random
from pathlib import Path


def requant(acc, bias, mult, shift):
    value = (acc + bias) * mult
    if shift > 0:
        if shift > abs(value).bit_length() + 1:
            value = 0
        else:
            magnitude, remainder = divmod(abs(value), 1 << shift)
            magnitude += remainder >= (1 << (shift - 1))
            value = -magnitude if value < 0 else magnitude
    else:
        # Once shifted by 7, every nonzero integer saturates to INT8.
        value <<= min(-shift, 7)
    return max(-127, min(127, value))


def write_hex(name, values, digits):
    mask = (1 << (4 * digits)) - 1
    Path(name).write_text("".join(f"{value & mask:0{digits}x}\n" for value in values))


def pack(values):
    return [sum((byte & 255) << (8 * lane) for lane, byte in enumerate(values[i:i+8]))
            for i in range(0, len(values), 8)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--rx", type=int, default=5, choices=(3, 5))
    args = parser.parse_args()
    rng = random.Random(20261010 + args.rx)
    shifts = [-(1 << 31), -40, -7, -6, -5, -4, -3, -2, -1, 0, 1, 2,
              31, 32, 62, 63, 64, 65, 66, 80, (1 << 31)-1]
    limits = [-(1 << 31), -129, -127, -64, -6, -2, -1, 0, 1, 2, 6, 63,
              127, 129, (1 << 31)-1]
    params = [(s, m, b) for s in shifts for m in [-(1 << 31), -1, 0, 1, (1 << 31)-1]
              for b in [-(1 << 31), 0, (1 << 31)-1]]
    vectors, expected = [], []
    for i in range(12000):
        tag = i % len(params)
        shift, mult, bias = params[tag]
        acc = limits[(i // len(params)) % len(limits)] if i < 6000 else rng.randint(-(1 << 31), (1 << 31)-1)
        vectors.append((tag << 32) | (acc & 0xffffffff))
        expected.append((tag << 8) | (requant(acc, bias, mult, shift) & 255))
    write_hex("rq_params.hex", [(s & 0xffffffff) << 64 | (m & 0xffffffff) << 32 | (b & 0xffffffff)
                                for s, m, b in params], 24)
    write_hex("rq_vectors.hex", vectors, 11)
    write_hex("rq_expected.hex", expected, 5)

    features = [rng.randint(-8, 8) for _ in range(args.rx * 1024)]
    # Arbitrary distinguishable tables test address/latency routing, not GELU accuracy.
    tables = [[((i * (2*t+1) + 19*t) & 255) for i in range(256)] for t in range(4)]
    write_hex("lut.hex", sum(tables, []), 2)
    write_hex("features.hex", pack(features), 16)
    all_weights, all_params, accumulators, outputs = [], [], [], []
    inputs = features
    for layer, out_size in enumerate((128, 128, 24)):
        weights = [[rng.randint(-2, 2) for _ in inputs] for _ in range(out_size)]
        layer_params = [(rng.randrange(-30, 31), rng.choice((-3, -1, 1, 2, 3)), rng.randrange(3, 9))
                        for _ in range(out_size)]
        accs = [sum(x*w for x, w in zip(inputs, row)) for row in weights]
        qs = [requant(a, b, m, s) for a, (b, m, s) in zip(accs, layer_params)]
        out = [tables[layer+2][q+128] for q in qs] if layer < 2 else [q & 255 for q in qs]
        all_weights.append(sum((pack(row) for row in weights), []))
        all_params.extend((s << 64) | ((m & 0xffffffff) << 32) | (b & 0xffffffff)
                          for b, m, s in layer_params)
        accumulators.extend(accs)
        outputs.extend(out)
        inputs = [q if q < 128 else q-256 for q in out]
    write_hex("fc1_weights.hex", all_weights[0], 16)
    write_hex("fc23_weights.hex", all_weights[1] + all_weights[2] + [0]*(4096-2048-384), 16)
    write_hex("top_params.hex", all_params, 24)
    write_hex("top_acc.hex", accumulators, 8)
    write_hex("top_outputs.hex", outputs, 2)
    print(f"Fixtures RX={args.rx}: requant=12000, FC outputs=280", flush=True)


if __name__ == "__main__":
    main()
