"""tb_Conv_MAC 용 벡터 생성.

Conv MAC 출력(bias 전 dot-product)을 3 RX 전체 순서대로 계산한다.
순서: RX마다 Conv1(h → w → oc 0..15) → Conv2 pass0(oc 0..15) → pass1(oc 16..31)
출력: conv_in.hex (입력 11,520 B), conv_f1.hex (fmap1 20,480 B, Conv2 입력으로 사용),
      conv_wram.hex (333 x 128-bit), conv_exp.hex ({tag, acc})
"""
import random

random.seed(7)
H, W = 128, 10


def r8():
    return random.randint(-128, 127)


def u8(v):
    return v & 0xff


inp = [[[r8() for _ in range(W)] for _ in range(H)] for _ in range(9)]
f1 = [[[r8() for _ in range(W)] for _ in range(H)] for _ in range(16)]
w1 = [[[[r8() for _ in range(3)] for _ in range(5)] for _ in range(3)] for _ in range(16)]
w2 = [[[[r8() for _ in range(3)] for _ in range(3)] for _ in range(16)] for _ in range(32)]

with open("conv_in.hex", "w") as f:
    f.write("".join("%02x\n" % u8(inp[c][h][w]) for c in range(9) for h in range(H) for w in range(W)))
with open("conv_f1.hex", "w") as f:
    f.write("".join("%02x\n" % u8(f1[c][h][w]) for c in range(16) for h in range(H) for w in range(W)))

# weight word = tap, word[8*lane +: 8] = weight[16*pass + lane][tap]
words = []
for ic in range(3):
    for kh in range(5):
        for kw in range(3):
            words.append([w1[l][ic][kh][kw] for l in range(16)])
for p in range(2):
    for ic in range(16):
        for kh in range(3):
            for kw in range(3):
                words.append([w2[16 * p + l][ic][kh][kw] for l in range(16)])
assert len(words) == 333
with open("conv_wram.hex", "w") as f:
    f.write("".join("".join("%02x" % u8(v) for v in reversed(wd)) + "\n" for wd in words))

out = []
for rx in range(3):
    for h in range(H):
        for w in range(W):
            for oc in range(16):
                s = 0
                for ic in range(3):
                    for kh in range(5):
                        for kw in range(3):
                            ih, iw = h + kh - 2, w + kw - 1
                            if 0 <= ih < H and 0 <= iw < W:
                                s += inp[rx + 3 * ic][ih][iw] * w1[oc][ic][kh][kw]
                out.append(((rx << 17) | (0 << 16) | (oc << 11) | (h << 4) | w, s))
    for p in range(2):
        for h in range(H):
            for w in range(W):
                for l in range(16):
                    oc = 16 * p + l
                    s = 0
                    for ic in range(16):
                        for kh in range(3):
                            for kw in range(3):
                                ih, iw = h + kh - 1, w + kw - 1
                                if 0 <= ih < H and 0 <= iw < W:
                                    s += f1[ic][ih][iw] * w2[oc][ic][kh][kw]
                    out.append(((rx << 17) | (1 << 16) | (oc << 11) | (h << 4) | w, s))

with open("conv_exp.hex", "w") as f:
    f.write("".join("%05x%08x\n" % (t, s & 0xffffffff) for t, s in out))
print("outputs:", len(out))
