"""tb_requant_stage 용 벡터 생성.

rq = clamp(round_shift((acc + bias) * mult, shift), -127, 127)
round_shift 는 reference(round_shift_signed / _rounding_right_shift)와 같은 식.
출력: rq_param.hex (48 x {shift, mult, bias}), rq_vec.hex ({tag, acc}), rq_exp.hex ({tag, rq})
"""
import random

random.seed(1)
N = 5000


def round_shift(v, s):
    if s <= 0:
        return v << (-s)
    o = 1 << (s - 1)
    return (v + o) >> s if v >= 0 else (v - o) >> s


params = []
for _ in range(48):
    bias = random.randint(-2**20, 2**20)
    mult = random.randint(2**30, 2**31 - 1)
    sh = random.choice([0, -1, 1, 2] + list(range(25, 45)))
    params.append((sh, mult, bias))

with open("rq_param.hex", "w") as f:
    for sh, m, b in params:
        f.write("%08x%08x%08x\n" % (sh & 0xffffffff, m, b & 0xffffffff))

with open("rq_vec.hex", "w") as vec, open("rq_exp.hex", "w") as exp:
    for _ in range(N):
        layer = random.randint(0, 1)
        oc = random.randint(0, 15 if layer == 0 else 31)
        rx, h, w = random.randint(0, 2), random.randint(0, 127), random.randint(0, 9)
        tag = (rx << 17) | (layer << 16) | (oc << 11) | (h << 4) | w
        sh, m, b = params[oc if layer == 0 else 16 + oc]
        if random.random() < 0.1:
            acc = random.choice([0, 1, -1, 2**31 - 1 - 2**20, -2**31 + 2**20])
        else:
            acc = random.randint(-2**(8 + random.randint(0, 20)), 2**(8 + random.randint(0, 20)))
        q = max(-127, min(127, round_shift((acc + b) * m, sh)))
        vec.write("%05x%08x\n" % (tag, acc & 0xffffffff))
        exp.write("%05x%02x\n" % (tag, q & 0xff))

print("vectors:", N)
