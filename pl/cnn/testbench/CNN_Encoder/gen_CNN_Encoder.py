"""tb_CNN_Encoder 용 벡터 생성 (numpy 필요).

사용: python gen_CNN_Encoder.py [RX]   (기본 3, tb_CNN_Encoder 의 RX 와 같게)

RX마다 Conv1 → requant → GELU1 → Conv2 → requant → GELU2 → AdaptiveAvgPool(8,4)
수치 규칙은 ML/src/int8_reference.py 와 같다.
출력: enc_in64.hex (입력 RX*480 x 64-bit), enc_wram.hex (333 x 128-bit),
      enc_param.hex (48 x {shift, mult, bias}), enc_lut.hex (GELU LUT 1024 B),
      enc_pool.hex (pool_mult, pool_shift), enc_feat.hex (기대 Pool 결과 RX*128 x 64-bit)
"""
import sys
import numpy as np

RX = int(sys.argv[1]) if len(sys.argv) > 1 else 3

rng = np.random.default_rng(11)
H, W = 128, 10


def i8(*shape):
    return rng.integers(-127, 128, size=shape, dtype=np.int64)


def u8(v):
    return int(v) & 0xff


inp = i8(3 * RX, H, W)
w1, w2 = i8(16, 3, 5, 3), i8(32, 16, 3, 3)
b1, b2 = rng.integers(-2**14, 2**14, 16), rng.integers(-2**14, 2**14, 32)
m1, m2 = rng.integers(2**30, 2**31, 16), rng.integers(2**30, 2**31, 32)
s1, s2 = rng.integers(39, 42, 16), rng.integers(40, 43, 32)  # 출력이 대부분 포화되지 않게
lut = rng.integers(-127, 128, size=(2, 256))
pmult, pshift = int(rng.integers(2**30, 2**31)), 31


def round_shift(v, s):
    o = np.int64(1) << np.int64(s - 1)
    return np.where(v >= 0, (v + o) >> s, (v - o) >> s)


def conv(x, w, ph, pw):
    oc, ic, kh, kw = w.shape
    xp = np.pad(x, ((0, 0), (ph, ph), (pw, pw)))
    out = np.zeros((oc, H, W), np.int64)
    for c in range(ic):
        for a in range(kh):
            for b in range(kw):
                out += w[:, c, a, b][:, None, None] * xp[c, a:a + H, b:b + W][None]
    return out


def requant(acc, b, m, s):
    out = np.empty_like(acc)
    for o in range(acc.shape[0]):
        out[o] = np.clip(round_shift((acc[o] + b[o]) * m[o], int(s[o])), -127, 127)
    return out


def gelu(q, bank):
    return lut[bank][q + 128]


feat = np.zeros(RX * 1024, np.int64)
for rx in range(RX):
    x = inp[[rx + RX * c for c in range(3)]]
    f1 = gelu(requant(conv(x, w1, 2, 1), b1, m1, s1), 0)
    f2 = gelu(requant(conv(f1, w2, 1, 1), b2, m2, s2), 1)
    for oh in range(8):
        for ow, (ws, we) in enumerate([(0, 3), (2, 5), (5, 8), (7, 10)]):
            s = f2[:, oh * 16:oh * 16 + 16, ws:we].sum(axis=(1, 2))
            p = round_shift(s * pmult, pshift)
            p = np.clip(np.where(p >= 0, (p + 24) // 48, (p - 24) // 48), -127, 127)
            for oc in range(32):
                feat[rx * 1024 + oc * 32 + oh * 4 + ow] = p[oc]

fb = inp.reshape(-1)
with open("enc_in64.hex", "w") as f:
    f.write("".join("".join("%02x" % u8(fb[8 * k + i]) for i in reversed(range(8))) + "\n" for k in range(RX * 480)))

words = []
for c in range(3):
    for a in range(5):
        for b in range(3):
            words.append([w1[l, c, a, b] for l in range(16)])
for p in range(2):
    for c in range(16):
        for a in range(3):
            for b in range(3):
                words.append([w2[16 * p + l, c, a, b] for l in range(16)])
with open("enc_wram.hex", "w") as f:
    f.write("".join("".join("%02x" % u8(v) for v in reversed(wd)) + "\n" for wd in words))

# Param RAM 0..15 Conv1, 16..47 Conv2
prm = [(s1[i], m1[i], b1[i]) for i in range(16)] + [(s2[i], m2[i], b2[i]) for i in range(32)]
with open("enc_param.hex", "w") as f:
    f.write("".join("%08x%08x%08x\n" % (int(s) & 0xffffffff, int(m), int(b) & 0xffffffff) for s, m, b in prm))

# GELU LUT bank 0 Conv1, bank 1 Conv2 (bank 2,3 FC 는 0)
with open("enc_lut.hex", "w") as f:
    f.write("".join("%02x\n" % u8(v) for v in list(lut[0]) + list(lut[1]) + [0] * 512))

with open("enc_pool.hex", "w") as f:
    f.write("%08x\n%08x\n" % (pmult, pshift))

with open("enc_feat.hex", "w") as f:
    f.write("".join("".join("%02x" % u8(feat[8 * k + i]) for i in reversed(range(8))) + "\n" for k in range(RX * 128)))

print("feat bytes:", feat.size, " non-saturated:", float(np.mean(np.abs(feat) < 127)))
