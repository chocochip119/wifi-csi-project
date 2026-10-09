/*
 * Software (ARM PS) RX5 pose CNN, bit-exact with the PL pose_cnn IP.
 *
 * Network (per RX r, input channels r, r+5, r+10):
 *   Conv1 3->16 k5x3 pad(2,1) -> requant -> GELU LUT e1
 *   Conv2 16->32 k3x3 pad(1,1) -> requant -> GELU LUT e2
 *   Pool  16x3 windows (cols 0-2,2-4,5-7,7-9) -> *pool_mult >>pool_shift -> /48
 *   flat[r*1024 + c*32 + oh*4 + ow]
 * FC1 5120->128 + LUT h1, FC2 128->128 + LUT h2, FC3 128->24.
 *
 * Rounding: nearest_half_away_from_zero_v1 (ml/pose/INT8.md).
 */
#define _POSIX_C_SOURCE 200809L

#include "pose_cnn_sw.h"

#include <math.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define RX       POSE_SW_RX
#define H        POSE_SW_H
#define W        POSE_SW_W
#define HW       (H * W)

#define C1_OUT   16u
#define C1_IN    3u
#define C1_KH    5u
#define C1_KW    3u
#define C2_OUT   32u
#define C2_IN    16u
#define C2_K     3u

/* padded tiles */
#define P1_H     (H + 4u)
#define P1_W     (W + 2u)
#define P2_H     (H + 2u)
#define P2_W     (W + 2u)

#define BLOB_MAGIC     0x36574C50u
#define BLOB_VERSION   2u
#define SHIFT_MIN      (-31)
#define SHIFT_MAX      63

/* word offsets inside the blob (pose_model.py layout(rx)) */
#define OFF_C1_W   8u
#define OFF_C1_B   188u
#define OFF_C1_M   204u
#define OFF_C1_S   220u
#define OFF_C2_W   236u
#define OFF_C2_B   1388u
#define OFF_C2_M   1420u
#define OFF_C2_S   1452u
#define OFF_FC1_W  1484u
#define OFF_FC1_B  (OFF_FC1_W + RX * 32768u)
#define OFF_FC1_M  (OFF_FC1_B + 128u)
#define OFF_FC1_S  (OFF_FC1_M + 128u)
#define OFF_FC2_W  (OFF_FC1_S + 128u)
#define OFF_FC2_B  (OFF_FC2_W + 4096u)
#define OFF_FC2_M  (OFF_FC2_B + 128u)
#define OFF_FC2_S  (OFF_FC2_M + 128u)
#define OFF_FC3_W  (OFF_FC2_S + 128u)
#define OFF_FC3_B  (OFF_FC3_W + 768u)
#define OFF_FC3_M  (OFF_FC3_B + 24u)
#define OFF_FC3_S  (OFF_FC3_M + 24u)
#define OFF_LUT_E1 (OFF_FC3_S + 24u)
#define OFF_LUT_E2 (OFF_LUT_E1 + 64u)
#define OFF_LUT_H1 (OFF_LUT_E2 + 64u)
#define OFF_LUT_H2 (OFF_LUT_H1 + 64u)
#define BLOB_WORDS (OFF_LUT_H2 + 64u)

_Static_assert(BLOB_WORDS * 4u == POSE_SW_BLOB_BYTES, "blob layout mismatch");

typedef struct {
    int16_t xp1[C1_IN][P1_H][P1_W];     /* padded Conv1 input     */
    int16_t xp2[C2_IN][P2_H][P2_W];     /* padded Conv1 output    */
    int32_t acc[HW];
    int16_t f2[HW];                     /* one Conv2 output plane */
} scratch_t;

struct pose_cnn_sw {
    unsigned threads;
    float output_scale;
    uint32_t scale_bits;
    int32_t pool_mult;
    int32_t pool_shift;

    int16_t w1[C1_OUT][C1_IN][C1_KH][C1_KW];
    int32_t b1[C1_OUT], m1[C1_OUT], s1[C1_OUT];
    int16_t w2[C2_OUT][C2_IN][C2_K][C2_K];
    int32_t b2[C2_OUT], m2[C2_OUT], s2[C2_OUT];

    int8_t fc1_w[POSE_SW_HIDDEN][POSE_SW_FLAT];
    int32_t fc1_b[POSE_SW_HIDDEN], fc1_m[POSE_SW_HIDDEN], fc1_s[POSE_SW_HIDDEN];
    int8_t fc2_w[POSE_SW_HIDDEN][POSE_SW_HIDDEN];
    int32_t fc2_b[POSE_SW_HIDDEN], fc2_m[POSE_SW_HIDDEN], fc2_s[POSE_SW_HIDDEN];
    int8_t fc3_w[POSE_SW_OUTPUT_BYTES][POSE_SW_HIDDEN];
    int32_t fc3_b[POSE_SW_OUTPUT_BYTES], fc3_m[POSE_SW_OUTPUT_BYTES],
            fc3_s[POSE_SW_OUTPUT_BYTES];

    int8_t lut_e1[256], lut_e2[256], lut_h1[256], lut_h2[256];

    scratch_t scratch[POSE_SW_MAX_THREADS];

    /* per-call state shared with worker threads */
    const int8_t *cur_input;
    int8_t flat[POSE_SW_FLAT];
};

typedef struct {
    pose_cnn_sw_t *sw;
    unsigned tid;
} worker_arg_t;

static void set_err(char *err, size_t err_len, const char *fmt, ...)
{
    va_list ap;
    if (err == NULL || err_len == 0u) return;
    va_start(ap, fmt);
    vsnprintf(err, err_len, fmt, ap);
    va_end(ap);
}

static uint64_t now_ns(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

static uint32_t rd32(const uint8_t *blob, uint32_t word)
{
    const uint8_t *p = blob + (size_t)word * 4u;
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static void rd_i32(const uint8_t *blob, uint32_t word, int32_t *dst, unsigned n)
{
    unsigned i;
    for (i = 0u; i < n; ++i) dst[i] = (int32_t)rd32(blob, word + i);
}

static int check_shifts(const int32_t *s, unsigned n)
{
    unsigned i;
    for (i = 0u; i < n; ++i) {
        if (s[i] < SHIFT_MIN || s[i] > SHIFT_MAX) return -1;
    }
    return 0;
}

/* Round-half-away-from-zero arithmetic shift; s <= 0 is a left shift.
 * Unsigned arithmetic reproduces the int64 wrap of the numpy reference. */
static inline int64_t round_shift(int64_t v, int32_t s)
{
    uint64_t off;
    if (s <= 0) return (int64_t)((uint64_t)v << (unsigned)(-s));
    off = (uint64_t)1 << (unsigned)(s - 1);
    if (v >= 0) return (int64_t)((uint64_t)v + off) >> s;
    return (int64_t)((uint64_t)v + off - 1u) >> s;
}

static inline int32_t sat8(int64_t v)
{
    return v > 127 ? 127 : (v < -127 ? -127 : (int32_t)v);
}

static inline int32_t requant(int64_t acc, int32_t m, int32_t s)
{
    return sat8(round_shift((int64_t)((uint64_t)acc * (uint64_t)(int64_t)m), s));
}

/* ---------------------------------------------------------------- encoder */

static void encode_rx(pose_cnn_sw_t *sw, scratch_t *t, const int8_t *input, unsigned r)
{
    unsigned oc, c, a, b, h, w;

    /* Conv1 input: channels r + RX*c, zero padding (2,1) */
    memset(t->xp1, 0, sizeof(t->xp1));
    for (c = 0u; c < C1_IN; ++c) {
        const int8_t *src = input + (size_t)(r + RX * c) * HW;
        for (h = 0u; h < H; ++h) {
            for (w = 0u; w < W; ++w) t->xp1[c][h + 2u][w + 1u] = src[h * W + w];
        }
    }

    /* Conv1 + requant + GELU, written straight into the padded Conv2 input */
    memset(t->xp2, 0, sizeof(t->xp2));
    for (oc = 0u; oc < C1_OUT; ++oc) {
        memset(t->acc, 0, sizeof(t->acc));
        for (c = 0u; c < C1_IN; ++c) {
            for (a = 0u; a < C1_KH; ++a) {
                for (b = 0u; b < C1_KW; ++b) {
                    const int32_t wv = sw->w1[oc][c][a][b];
                    for (h = 0u; h < H; ++h) {
                        const int16_t *row = &t->xp1[c][h + a][b];
                        int32_t *acc = &t->acc[h * W];
                        for (w = 0u; w < W; ++w) acc[w] += wv * row[w];
                    }
                }
            }
        }
        for (h = 0u; h < H; ++h) {
            for (w = 0u; w < W; ++w) {
                int32_t q = requant((int64_t)t->acc[h * W + w] + sw->b1[oc],
                                    sw->m1[oc], sw->s1[oc]);
                t->xp2[oc][h + 1u][w + 1u] = sw->lut_e1[q + 128];
            }
        }
    }

    /* Conv2 + requant + GELU + Pool, one output channel at a time */
    for (oc = 0u; oc < C2_OUT; ++oc) {
        unsigned oh, ow;
        static const unsigned win_start[4] = {0u, 2u, 5u, 7u};

        memset(t->acc, 0, sizeof(t->acc));
        for (c = 0u; c < C2_IN; ++c) {
            for (a = 0u; a < C2_K; ++a) {
                for (b = 0u; b < C2_K; ++b) {
                    const int32_t wv = sw->w2[oc][c][a][b];
                    for (h = 0u; h < H; ++h) {
                        const int16_t *row = &t->xp2[c][h + a][b];
                        int32_t *acc = &t->acc[h * W];
                        for (w = 0u; w < W; ++w) acc[w] += wv * row[w];
                    }
                }
            }
        }
        for (h = 0u; h < HW; ++h) {
            int32_t q = requant((int64_t)t->acc[h] + sw->b2[oc], sw->m2[oc], sw->s2[oc]);
            t->f2[h] = sw->lut_e2[q + 128];
        }
        for (oh = 0u; oh < 8u; ++oh) {
            for (ow = 0u; ow < 4u; ++ow) {
                int64_t sum = 0, p;
                for (h = oh * 16u; h < oh * 16u + 16u; ++h) {
                    for (w = win_start[ow]; w < win_start[ow] + 3u; ++w) {
                        sum += t->f2[h * W + w];
                    }
                }
                p = round_shift(sum * sw->pool_mult, sw->pool_shift);
                p = p >= 0 ? (p + 24) / 48 : -((-p + 24) / 48);   /* /48, ties away */
                sw->flat[r * 1024u + oc * 32u + oh * 4u + ow] = (int8_t)sat8(p);
            }
        }
    }
}

static void *encoder_worker(void *arg)
{
    worker_arg_t *wa = (worker_arg_t *)arg;
    pose_cnn_sw_t *sw = wa->sw;
    unsigned r;
    for (r = wa->tid; r < RX; r += sw->threads) {
        encode_rx(sw, &sw->scratch[wa->tid], sw->cur_input, r);
    }
    return NULL;
}

/* --------------------------------------------------------------------- FC */

static void fc_layer(const int8_t *x, unsigned n_in, const int8_t *wt, unsigned n_out,
                     const int32_t *bias, const int32_t *m, const int32_t *s,
                     const int8_t *lut, int8_t *out)
{
    unsigned o, i;
    for (o = 0u; o < n_out; ++o) {
        const int8_t *row = wt + (size_t)o * n_in;
        int32_t sum = 0;
        int32_t acc;
        int32_t q;
        for (i = 0u; i < n_in; ++i) sum += (int32_t)row[i] * (int32_t)x[i];
        /* reference keeps the biased accumulator in int32 (wraps) */
        acc = (int32_t)((uint32_t)sum + (uint32_t)bias[o]);
        q = requant(acc, m[o], s[o]);
        out[o] = lut != NULL ? lut[q + 128] : (int8_t)q;
    }
}

/* -------------------------------------------------------------------- API */

pose_cnn_sw_t *pose_cnn_sw_create(const uint8_t *blob, size_t blob_bytes,
                                  unsigned threads, char *err, size_t err_len)
{
    pose_cnn_sw_t *sw;
    unsigned i;

    if (blob == NULL || blob_bytes != POSE_SW_BLOB_BYTES) {
        set_err(err, err_len, "blob size %zu, expected %u", blob_bytes, POSE_SW_BLOB_BYTES);
        return NULL;
    }
    if (rd32(blob, 0u) != BLOB_MAGIC || rd32(blob, 1u) != BLOB_VERSION ||
        rd32(blob, 2u) != BLOB_WORDS) {
        set_err(err, err_len, "bad blob header: magic=0x%08x version=%u words=%u",
                rd32(blob, 0u), rd32(blob, 1u), rd32(blob, 2u));
        return NULL;
    }
    if (threads < 1u || threads > POSE_SW_MAX_THREADS) {
        set_err(err, err_len, "threads must be 1..%u", POSE_SW_MAX_THREADS);
        return NULL;
    }
    sw = (pose_cnn_sw_t *)calloc(1u, sizeof(*sw));
    if (sw == NULL) {
        set_err(err, err_len, "out of memory");
        return NULL;
    }
    sw->threads = threads;

    /* header: word4 output scale (float32), word5 pool_mult, word6 pool_shift */
    sw->scale_bits = rd32(blob, 4u);
    memcpy(&sw->output_scale, &sw->scale_bits, sizeof(sw->output_scale));
    sw->pool_mult = (int32_t)rd32(blob, 5u);
    sw->pool_shift = (int32_t)rd32(blob, 6u);

    for (i = 0u; i < C1_OUT * C1_IN * C1_KH * C1_KW; ++i) {
        (&sw->w1[0][0][0][0])[i] = (int8_t)blob[OFF_C1_W * 4u + i];
    }
    for (i = 0u; i < C2_OUT * C2_IN * C2_K * C2_K; ++i) {
        (&sw->w2[0][0][0][0])[i] = (int8_t)blob[OFF_C2_W * 4u + i];
    }
    rd_i32(blob, OFF_C1_B, sw->b1, C1_OUT);
    rd_i32(blob, OFF_C1_M, sw->m1, C1_OUT);
    rd_i32(blob, OFF_C1_S, sw->s1, C1_OUT);
    rd_i32(blob, OFF_C2_B, sw->b2, C2_OUT);
    rd_i32(blob, OFF_C2_M, sw->m2, C2_OUT);
    rd_i32(blob, OFF_C2_S, sw->s2, C2_OUT);

    memcpy(sw->fc1_w, blob + OFF_FC1_W * 4u, sizeof(sw->fc1_w));
    memcpy(sw->fc2_w, blob + OFF_FC2_W * 4u, sizeof(sw->fc2_w));
    memcpy(sw->fc3_w, blob + OFF_FC3_W * 4u, sizeof(sw->fc3_w));
    rd_i32(blob, OFF_FC1_B, sw->fc1_b, POSE_SW_HIDDEN);
    rd_i32(blob, OFF_FC1_M, sw->fc1_m, POSE_SW_HIDDEN);
    rd_i32(blob, OFF_FC1_S, sw->fc1_s, POSE_SW_HIDDEN);
    rd_i32(blob, OFF_FC2_B, sw->fc2_b, POSE_SW_HIDDEN);
    rd_i32(blob, OFF_FC2_M, sw->fc2_m, POSE_SW_HIDDEN);
    rd_i32(blob, OFF_FC2_S, sw->fc2_s, POSE_SW_HIDDEN);
    rd_i32(blob, OFF_FC3_B, sw->fc3_b, POSE_SW_OUTPUT_BYTES);
    rd_i32(blob, OFF_FC3_M, sw->fc3_m, POSE_SW_OUTPUT_BYTES);
    rd_i32(blob, OFF_FC3_S, sw->fc3_s, POSE_SW_OUTPUT_BYTES);

    memcpy(sw->lut_e1, blob + OFF_LUT_E1 * 4u, 256u);
    memcpy(sw->lut_e2, blob + OFF_LUT_E2 * 4u, 256u);
    memcpy(sw->lut_h1, blob + OFF_LUT_H1 * 4u, 256u);
    memcpy(sw->lut_h2, blob + OFF_LUT_H2 * 4u, 256u);

    /* same rejections as the PL loader (blob_decoder.v) */
    if (sw->pool_shift < SHIFT_MIN || sw->pool_shift > SHIFT_MAX ||
        check_shifts(sw->s1, C1_OUT) || check_shifts(sw->s2, C2_OUT) ||
        check_shifts(sw->fc1_s, POSE_SW_HIDDEN) || check_shifts(sw->fc2_s, POSE_SW_HIDDEN) ||
        check_shifts(sw->fc3_s, POSE_SW_OUTPUT_BYTES)) {
        set_err(err, err_len, "blob shift value outside %d..%d", SHIFT_MIN, SHIFT_MAX);
        free(sw);
        return NULL;
    }
    if (!isfinite(sw->output_scale) || sw->output_scale <= 0.0f) {
        set_err(err, err_len, "invalid output scale bits=0x%08x", sw->scale_bits);
        free(sw);
        return NULL;
    }
    return sw;
}

pose_cnn_sw_t *pose_cnn_sw_create_from_file(const char *path, unsigned threads,
                                            char *err, size_t err_len)
{
    FILE *f = fopen(path, "rb");
    uint8_t *blob;
    size_t got;
    int extra;
    pose_cnn_sw_t *sw;

    if (f == NULL) {
        set_err(err, err_len, "cannot open %s", path);
        return NULL;
    }
    blob = (uint8_t *)malloc(POSE_SW_BLOB_BYTES);
    if (blob == NULL) {
        fclose(f);
        set_err(err, err_len, "out of memory");
        return NULL;
    }
    got = fread(blob, 1u, POSE_SW_BLOB_BYTES, f);
    extra = fgetc(f);
    fclose(f);
    if (got != POSE_SW_BLOB_BYTES || extra != EOF) {
        set_err(err, err_len, "%s: size mismatch (expected %u bytes)", path, POSE_SW_BLOB_BYTES);
        free(blob);
        return NULL;
    }
    sw = pose_cnn_sw_create(blob, POSE_SW_BLOB_BYTES, threads, err, err_len);
    free(blob);
    return sw;
}

void pose_cnn_sw_destroy(pose_cnn_sw_t *sw)
{
    free(sw);
}

float pose_cnn_sw_output_scale(const pose_cnn_sw_t *sw) { return sw->output_scale; }
uint32_t pose_cnn_sw_scale_bits(const pose_cnn_sw_t *sw) { return sw->scale_bits; }
unsigned pose_cnn_sw_threads(const pose_cnn_sw_t *sw) { return sw->threads; }

int pose_cnn_sw_infer(pose_cnn_sw_t *sw, const int8_t *input, size_t input_bytes,
                      int8_t output[POSE_SW_OUTPUT_BYTES],
                      pose_cnn_sw_timing_t *timing, pose_cnn_sw_trace_t *trace)
{
    pthread_t tids[POSE_SW_MAX_THREADS];
    worker_arg_t args[POSE_SW_MAX_THREADS];
    unsigned started = 1u;
    unsigned i;
    int8_t fc1[POSE_SW_HIDDEN];
    int8_t fc2[POSE_SW_HIDDEN];
    uint64_t t0, t1, t2;

    if (sw == NULL || input == NULL || output == NULL || input_bytes != POSE_SW_INPUT_BYTES) {
        return -1;
    }
    t0 = now_ns();
    sw->cur_input = input;
    for (i = 0u; i < sw->threads; ++i) {
        args[i].sw = sw;
        args[i].tid = i;
    }
    for (i = 1u; i < sw->threads; ++i) {
        if (pthread_create(&tids[i], NULL, encoder_worker, &args[i]) != 0) break;
        started++;
    }
    if (started != sw->threads) {
        /* thread start failed: finish the missing slots on this thread */
        unsigned r;
        for (i = 1u; i < started; ++i) pthread_join(tids[i], NULL);
        for (r = 0u; r < RX; ++r) {
            if (r % sw->threads == 0u || r % sw->threads >= started) {
                encode_rx(sw, &sw->scratch[0], input, r);
            }
        }
        started = 1u;
    } else {
        encoder_worker(&args[0]);
    }
    for (i = 1u; i < started; ++i) pthread_join(tids[i], NULL);
    t1 = now_ns();

    fc_layer(sw->flat, POSE_SW_FLAT, &sw->fc1_w[0][0], POSE_SW_HIDDEN,
             sw->fc1_b, sw->fc1_m, sw->fc1_s, sw->lut_h1, fc1);
    fc_layer(fc1, POSE_SW_HIDDEN, &sw->fc2_w[0][0], POSE_SW_HIDDEN,
             sw->fc2_b, sw->fc2_m, sw->fc2_s, sw->lut_h2, fc2);
    fc_layer(fc2, POSE_SW_HIDDEN, &sw->fc3_w[0][0], POSE_SW_OUTPUT_BYTES,
             sw->fc3_b, sw->fc3_m, sw->fc3_s, NULL, output);
    t2 = now_ns();

    if (timing != NULL) {
        timing->encoder_ns = t1 - t0;
        timing->fc_ns = t2 - t1;
        timing->total_ns = t2 - t0;
    }
    if (trace != NULL) {
        memcpy(trace->flat, sw->flat, sizeof(trace->flat));
        memcpy(trace->fc1, fc1, sizeof(fc1));
        memcpy(trace->fc2, fc2, sizeof(fc2));
    }
    return 0;
}
