#include "loc_ridge.h"

#include <math.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Same constants as location_live.py / location_core.py. */
#define STALE_NS        2000000000ull
#define STATUS_TTL_NS  10000000000ull
#define GAP_NS          1000000000ull   /* config max_cycle_gap_s default 1.0 */
#define DEFAULT_STRIDE_S 0.5
#define LOC_MAX_CYCLES  64u

#define MODEL_MAGIC "WLOC"
#define MODEL_VERSION 1u
#define MODEL_HEADER_BYTES 128u
#define MODEL_CLASS_BYTES 8u
#define MODEL_MAX_BYTES (4u * 1024u * 1024u)

#define STATUS_HEADER_BYTES 44u
#define STATUS_NODE_BYTES 22u
#define ACK_BYTES 76u
#define CYCLE_HEADER_BYTES 32u
#define CYCLE_SLOT_BYTES 6u
#define SIG_BYTES (LOC_RX_COUNT * 6u + 6u + 4u + 4u * 3u)

typedef struct {
    double time_s;
    uint64_t time_ns;
    uint32_t trigger_seq;
    double amp[LOC_AMP_FEATURES];
    double rssi[LOC_RX_COUNT];
} loc_cycle_t;

struct loc_engine {
    unsigned n_classes;
    uint8_t code[LOC_MAX_CLASSES];
    uint8_t has_xy[LOC_MAX_CLASSES];
    int16_t x_cm[LOC_MAX_CLASSES], y_cm[LOC_MAX_CLASSES];
    double *mean, *scale, *coef, *intercept;
    double window_s, stride_s, min_interval_s, min_span_s;
    unsigned min_cycles;
    bool has_mapping;
    uint8_t expected_mac[LOC_RX_COUNT][6];

    loc_result_callback_t callback;
    void *user;
    loc_clock_ns_t clock_ns;

    /* STATUS identity (location_live.set_status). */
    bool ready, have_sig;
    uint64_t status_ns, input_floor_ns;
    uint8_t sig[SIG_BYTES];
    uint8_t radio_channel, radio_second;
    uint32_t radio_timeout_us, radio_gap_us;

    /* Frame chronology (feed / _finish_pending). */
    bool have_last_input, have_pending, have_last_valid, have_last_kept;
    uint64_t last_input_ns, last_valid_ns, last_kept_ns;
    uint32_t pending_trigger;

    /* Window grid (_emit_windows). */
    bool have_window;
    double window_start_s;
    unsigned n_cycles;
    loc_cycle_t cycles[LOC_MAX_CYCLES];
    uint32_t next_window_id;

    const char *reason;
    loc_stats_t stats;
};

static uint16_t rd16(const uint8_t *p) { return (uint16_t)(p[0] | (uint16_t)p[1] << 8); }
static uint32_t rd32(const uint8_t *p)
{ return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24; }
static double rdf64(const uint8_t *p) { double v; memcpy(&v, p, 8); return v; }

static uint32_t crc32_ieee(const uint8_t *data, size_t length)
{
    uint32_t crc = 0xFFFFFFFFu;
    for (size_t i = 0; i < length; ++i) {
        crc ^= data[i];
        for (unsigned bit = 0; bit < 8u; ++bit)
            crc = (crc >> 1) ^ (0xEDB88320u & (0u - (crc & 1u)));
    }
    return ~crc;
}

static void set_err(char *err, size_t len, const char *fmt, ...)
{
    va_list args;
    if (!err || !len) return;
    va_start(args, fmt);
    vsnprintf(err, len, fmt, args);
    va_end(args);
}

/* ---- model file (written by ps/tools/export_loc_model.py) ---------------- */

static int load_model(loc_engine_t *e, const char *path, char *err, size_t err_len)
{
    FILE *file = fopen(path, "rb");
    uint8_t *data = NULL;
    long size;
    int result = -1;

    if (!file) { set_err(err, err_len, "cannot open %s", path); return -1; }
    if (fseek(file, 0, SEEK_END) != 0 || (size = ftell(file)) < 0 || fseek(file, 0, SEEK_SET) != 0) {
        set_err(err, err_len, "cannot size %s", path); goto done;
    }
    if ((unsigned long)size < MODEL_HEADER_BYTES + 4u || (unsigned long)size > MODEL_MAX_BYTES) {
        set_err(err, err_len, "model size %ld out of range", size); goto done;
    }
    data = malloc((size_t)size);
    if (!data || fread(data, 1, (size_t)size, file) != (size_t)size) {
        set_err(err, err_len, "cannot read %s", path); goto done;
    }
    if (crc32_ieee(data, (size_t)size - 4u) != rd32(data + size - 4)) {
        set_err(err, err_len, "model CRC32 mismatch"); goto done;
    }
    if (memcmp(data, MODEL_MAGIC, 4) != 0 || rd32(data + 4) != MODEL_VERSION) {
        set_err(err, err_len, "not a WLOC v%u model", MODEL_VERSION); goto done;
    }
    e->n_classes = rd32(data + 8);
    if (e->n_classes < 2u || e->n_classes > LOC_MAX_CLASSES || rd32(data + 12) != LOC_FEATURES ||
        rd32(data + 16) != LOC_RX_COUNT || rd32(data + 20) != LOC_CSI_BYTES ||
        rd32(data + 24) != LOC_DROP_PAIRS) {
        set_err(err, err_len, "model contract is not 5 RX x 384 bytes, drop 2, amp_rssi"); goto done;
    }
    {
        size_t nf = LOC_FEATURES, nc = e->n_classes;
        size_t expected = MODEL_HEADER_BYTES + nc * MODEL_CLASS_BYTES + 8u * (2u * nf + nc * nf + nc) + 4u;
        const uint8_t *cursor;
        if ((size_t)size != expected) {
            set_err(err, err_len, "model size %ld != expected %zu", size, expected); goto done;
        }
        e->min_cycles = rd32(data + 28);
        e->window_s = rdf64(data + 32);
        e->min_interval_s = rdf64(data + 40);
        e->min_span_s = rdf64(data + 48);
        e->has_mapping = rd32(data + 64) != 0u;
        memcpy(e->expected_mac, data + 68, sizeof(e->expected_mac));
        cursor = data + MODEL_HEADER_BYTES;
        for (unsigned i = 0; i < nc; ++i, cursor += MODEL_CLASS_BYTES) {
            e->code[i] = cursor[0];
            e->has_xy[i] = cursor[1];
            e->x_cm[i] = (int16_t)rd16(cursor + 2);
            e->y_cm[i] = (int16_t)rd16(cursor + 4);
            if (e->code[i] > LOC_CODE_EMPTY || (e->code[i] == LOC_CODE_EMPTY) == (e->has_xy[i] != 0)) {
                set_err(err, err_len, "bad class table entry %u", i); goto done;
            }
            for (unsigned j = 0; j < i; ++j)
                if (e->code[j] == e->code[i]) { set_err(err, err_len, "duplicate class code"); goto done; }
        }
        e->mean = malloc(nf * sizeof(double));
        e->scale = malloc(nf * sizeof(double));
        e->coef = malloc(nc * nf * sizeof(double));
        e->intercept = malloc(nc * sizeof(double));
        if (!e->mean || !e->scale || !e->coef || !e->intercept) {
            set_err(err, err_len, "out of memory"); goto done;
        }
        for (size_t k = 0; k < nf; ++k, cursor += 8) e->mean[k] = rdf64(cursor);
        for (size_t k = 0; k < nf; ++k, cursor += 8) e->scale[k] = rdf64(cursor);
        for (size_t k = 0; k < nc * nf; ++k, cursor += 8) e->coef[k] = rdf64(cursor);
        for (size_t k = 0; k < nc; ++k, cursor += 8) e->intercept[k] = rdf64(cursor);
        for (size_t k = 0; k < nf; ++k)
            if (!isfinite(e->mean[k]) || !isfinite(e->scale[k]) || e->scale[k] == 0.0) {
                set_err(err, err_len, "non-finite scaler"); goto done;
            }
        for (size_t k = 0; k < nc * nf; ++k)
            if (!isfinite(e->coef[k])) { set_err(err, err_len, "non-finite coef"); goto done; }
    }
    /* inference_config / validate_config checks. */
    if (!(e->window_s > 0.0) || !(e->min_interval_s > 0.0) || !(e->min_span_s >= 0.0) ||
        !(e->min_span_s < e->window_s) || e->min_cycles < 1u ||
        e->min_cycles > (unsigned)ceil(e->window_s / e->min_interval_s)) {
        set_err(err, err_len, "invalid window configuration"); goto done;
    }
    if (ceil(e->window_s / e->min_interval_s) + 2.0 > LOC_MAX_CYCLES) {
        set_err(err, err_len, "window needs more than %u cycles", LOC_MAX_CYCLES); goto done;
    }
    result = 0;
done:
    free(data);
    fclose(file);
    return result;
}

/* ---- state resets (_drop_window / clear) -------------------------------- */

static void drop_window(loc_engine_t *e, const char *reason)
{
    e->n_cycles = 0;
    e->have_window = false;
    e->have_last_kept = false;
    e->reason = reason;
}

static void clear_state(loc_engine_t *e, const char *reason, bool forget_status, bool forget_sequence)
{
    drop_window(e, reason);
    e->have_pending = false;
    e->have_last_valid = false;
    if (forget_status) { e->ready = false; e->have_sig = false; }
    if (forget_sequence) e->have_last_input = false;
}

/* ---- inference ----------------------------------------------------------- */

static void predict(loc_engine_t *e, const loc_cycle_t *const *group, unsigned n,
                    double start_s, double end_s)
{
    double x[LOC_FEATURES], best = -INFINITY;
    double scores[LOC_MAX_CLASSES];
    unsigned best_i = 0;
    uint64_t t0 = e->clock_ns ? e->clock_ns() : 0;
    loc_result_t r;

    /* make_features: amplitude mean (950) then RSSI mean (5). */
    for (unsigned k = 0; k < LOC_AMP_FEATURES; ++k) {
        double sum = 0.0;
        for (unsigned i = 0; i < n; ++i) sum += group[i]->amp[k];
        x[k] = sum / (double)n;
    }
    for (unsigned k = 0; k < LOC_RX_COUNT; ++k) {
        double sum = 0.0;
        for (unsigned i = 0; i < n; ++i) sum += group[i]->rssi[k];
        x[LOC_AMP_FEATURES + k] = sum / (double)n;
    }
    /* StandardScaler -> RidgeClassifier; argmax keeps the first maximum. */
    for (unsigned k = 0; k < LOC_FEATURES; ++k) x[k] = (x[k] - e->mean[k]) / e->scale[k];
    for (unsigned c = 0; c < e->n_classes; ++c) {
        const double *row = e->coef + (size_t)c * LOC_FEATURES;
        double s = e->intercept[c];
        for (unsigned k = 0; k < LOC_FEATURES; ++k) s += x[k] * row[k];
        scores[c] = s;
        if (s > best) { best = s; best_i = c; }
    }

    memset(&r, 0, sizeof(r));
    r.window_id = e->next_window_id++;
    r.end_trigger_seq = group[n - 1]->trigger_seq;
    r.class_code = e->code[best_i];
    r.occupied = r.class_code != LOC_CODE_EMPTY;
    r.window_cycles = (uint8_t)n;
    r.x_cm = e->has_xy[best_i] ? e->x_cm[best_i] : LOC_NO_COORD;
    r.y_cm = e->has_xy[best_i] ? e->y_cm[best_i] : LOC_NO_COORD;
    r.window_start_us = (uint64_t)llround(start_s * 1e6);
    r.window_end_us = (uint64_t)llround(end_s * 1e6);
    r.n_scores = (uint8_t)(LOC_CODE_EMPTY + 1u);
    for (unsigned c = 0; c < e->n_classes; ++c) r.scores[e->code[c]] = (float)scores[c];
    if (e->clock_ns) r.infer_us = (uint32_t)((e->clock_ns() - t0) / 1000u);
    e->stats.predictions++;
    e->reason = r.occupied ? "person present" : "empty";
    if (e->callback) e->callback(&r, e->user);
}

/* make_windows for one [start, end) window, then the length/span gate. */
static void emit_windows(loc_engine_t *e, uint64_t watermark_ns)
{
    while (e->have_window && (double)watermark_ns / 1e9 + 1e-9 >= e->window_start_s + e->window_s) {
        const loc_cycle_t *group[LOC_MAX_CYCLES];
        unsigned n = 0, kept = 0;
        double start = e->window_start_s, end = start + e->window_s, last = -INFINITY;

        for (unsigned i = 0; i < e->n_cycles; ++i) {
            double t = e->cycles[i].time_s;
            if (start <= t && t < end && t - last + 1e-9 >= e->min_interval_s) {
                group[n++] = &e->cycles[i];
                last = t;
            }
        }
        if (n >= e->min_cycles && group[n - 1]->time_s - group[0]->time_s + 1e-9 >= e->min_span_s) {
            predict(e, group, n, start, end);
        } else {
            e->stats.short_windows++;
            e->reason = "window has too few cycles or too short a span";
        }
        e->window_start_s += e->stride_s;
        for (unsigned i = 0; i < e->n_cycles; ++i)
            if (e->cycles[i].time_s >= e->window_start_s - 1e-9) e->cycles[kept++] = e->cycles[i];
        e->n_cycles = kept;
    }
}

/* ---- STATUS / ACK -------------------------------------------------------- */

static const char *check_status(loc_engine_t *e, const uint8_t *p, size_t len, uint8_t sig[SIG_BYTES])
{
    uint8_t mac[LOC_RX_COUNT][6];
    unsigned slots = 0, indexes = 0;

    if (len < STATUS_HEADER_BYTES || p[7] > 8u || len != STATUS_HEADER_BYTES + STATUS_NODE_BYTES * (size_t)p[7])
        return "STATUS size mismatch";
    if (p[0] == 0u || p[5] != LOC_RX_COUNT) return "TX not running with 5 active RX";
    if (p[7] != LOC_RX_COUNT) return "STATUS needs exactly 5 RX nodes";
    if (p[2] != 1u && p[2] != 2u) return "HT40 (above/below) required";
    if (p[1] < 1u || p[1] > 14u) return "bad Wi-Fi channel";
    for (unsigned i = 0; i < LOC_RX_COUNT; ++i) {
        const uint8_t *node = p + STATUS_HEADER_BYTES + STATUS_NODE_BYTES * i;
        uint8_t slot = node[0], flags = node[3];
        uint8_t index = (flags & 0x02u) ? node[1] : slot;
        if ((flags & 0x05u) != 0x05u) return "RX not connected/live";
        if (slot >= LOC_RX_COUNT || (slots & (1u << slot))) return "RX slot index not 0..4";
        if (index >= LOC_RX_COUNT || (indexes & (1u << index))) return "RX index duplicated or invalid";
        slots |= 1u << slot;
        indexes |= 1u << index;
        memcpy(mac[index], node + 4, 6);
    }
    for (unsigned i = 0; i < LOC_RX_COUNT; ++i)
        for (unsigned j = 0; j < i; ++j)
            if (memcmp(mac[i], mac[j], 6) == 0) return "duplicate RX MAC";
    if (e->has_mapping && memcmp(mac, e->expected_mac, sizeof(mac)) != 0)
        return "RX index/MAC differs from the trained model";

    /* (mapping, radio, generation) as in status_identity + set_status. */
    memcpy(sig, mac, sizeof(mac));
    memcpy(sig + sizeof(mac), p + 36, 6);            /* tx_mac */
    memcpy(sig + sizeof(mac) + 6, p, 4);             /* channel, second, protocol (+ mode) */
    memcpy(sig + sizeof(mac) + 10, p + 8, 8);        /* timeout_us, udp_slot_gap_us */
    memcpy(sig + sizeof(mac) + 18, p + 16, 4);       /* generation */
    return NULL;
}

static void on_status(loc_engine_t *e, const uint8_t *p, size_t len, uint64_t now_ns)
{
    uint8_t sig[SIG_BYTES];
    const char *problem = check_status(e, p, len, sig);

    e->stats.status_frames++;
    if (problem) {
        clear_state(e, problem, true, true);
        e->stats.invalid_status++;
        return;
    }
    if (!e->have_sig || memcmp(sig, e->sig, SIG_BYTES) != 0) {
        clear_state(e, "STATUS accepted; waiting for complete cycles", true, true);
        e->input_floor_ns = now_ns;
    }
    memcpy(e->sig, sig, SIG_BYTES);
    e->have_sig = true;
    e->ready = true;
    e->status_ns = now_ns;
    e->radio_channel = p[1];
    e->radio_second = p[2];
    e->radio_timeout_us = rd32(p + 8);
    e->radio_gap_us = rd32(p + 12);
}

static void on_ack(loc_engine_t *e, const uint8_t *p, size_t len)
{
    bool unchanged = e->ready && len == ACK_BYTES && p[0] != 0u && p[1] != 0u &&
                     p[2] == e->radio_channel && p[3] == e->radio_second &&
                     rd32(p + 4) == e->radio_timeout_us && rd32(p + 8) == e->radio_gap_us;
    if (!unchanged) {
        clear_state(e, "TX ACK changed state; waiting for STATUS", true, true);
        e->stats.ack_resets++;
    }
}

/* ---- CSI cycle ----------------------------------------------------------- */

/* cycle_from_rows: exactly RX 0..4, 384 bytes each, active/received 5. */
static const char *decode_cycle(const uint8_t *p, size_t len, loc_cycle_t *cycle)
{
    size_t cursor = CYCLE_HEADER_BYTES;
    unsigned seen = 0, rows = 0;
    bool bad_len = false;

    if (p[28] > 32u) return "malformed cycle";
    for (unsigned slot = 0; slot < p[28]; ++slot) {
        uint8_t rx, present;
        uint16_t n;
        if (cursor + CYCLE_SLOT_BYTES > len) return "malformed cycle";
        rx = p[cursor];
        present = p[cursor + 1];
        n = rd16(p + cursor + 4);
        if (cursor + CYCLE_SLOT_BYTES + n > len || (n & 1u)) return "malformed cycle";
        if (present) {
            const int8_t *iq = (const int8_t *)(p + cursor + CYCLE_SLOT_BYTES);
            if (rx >= LOC_RX_COUNT || (seen & (1u << rx))) return "duplicate or unexpected RX";
            seen |= 1u << rx;
            ++rows;
            if (n != LOC_CSI_BYTES) {
                bad_len = true;
            } else {
                double *amp = cycle->amp + (size_t)rx * LOC_PAIRS_PER_RX;
                /* Pairs are (imaginary, real); drop the first two pairs. */
                for (unsigned k = 0; k < LOC_PAIRS_PER_RX; ++k) {
                    unsigned pair = k + LOC_DROP_PAIRS;
                    amp[k] = hypot((double)iq[2u * pair], (double)iq[2u * pair + 1u]);
                }
                cycle->rssi[rx] = (double)(int8_t)p[cursor + 2];
            }
        }
        cursor += CYCLE_SLOT_BYTES + n;
    }
    if (cursor != len) return "malformed cycle";
    if (p[28] != LOC_RX_COUNT || p[29] != LOC_RX_COUNT) return "5 RX cycle incomplete or timed out";
    if (rows != LOC_RX_COUNT) return "missing RX in cycle";
    if (bad_len) return "CSI length differs from the model";
    return NULL;
}

static void tick(loc_engine_t *e, uint64_t now_ns)
{
    if (!e->ready) return;
    if (now_ns < e->status_ns || now_ns - e->status_ns > STATUS_TTL_NS) {
        clear_state(e, "STATUS is stale", true, false);
        e->stats.stale_resets++;
        return;
    }
    if (e->have_last_valid && (now_ns < e->last_valid_ns || now_ns - e->last_valid_ns > STALE_NS)) {
        clear_state(e, "no valid 5-RX CSI for 2 s", false, false);
        e->stats.stale_resets++;
    }
}

static void on_cycle(loc_engine_t *e, const uint8_t *p, size_t len, uint64_t now_ns)
{
    loc_cycle_t *cycle;
    const char *problem;
    uint32_t trigger;

    e->stats.cycle_frames++;
    if (!e->ready) { e->stats.not_ready_frames++; return; }
    if (now_ns < e->status_ns || now_ns - e->status_ns > STATUS_TTL_NS) {
        clear_state(e, "STATUS is stale", true, false);
        e->stats.stale_resets++;
        return;
    }
    if (len < CYCLE_HEADER_BYTES) { e->stats.invalid_cycles++; return; }
    trigger = rd32(p + 4);

    /* Chronology first: a broken order cannot be compared with buffered cycles. */
    if (now_ns < e->input_floor_ns ||
        (e->have_last_input && now_ns <= e->last_input_ns) ||
        (e->have_pending && (((trigger - e->pending_trigger) & 0xFFFFFFFFu) == 0u ||
                             ((trigger - e->pending_trigger) & 0xFFFFFFFFu) >= 0x80000000u))) {
        clear_state(e, "CSI time/trigger order rejected", false, true);
        e->stats.chronology_rejects++;
        return;
    }
    if (e->have_last_input && now_ns - e->last_input_ns > GAP_NS) {
        clear_state(e, "CSI gap; collecting a new window", false, false);
        e->stats.gaps++;
    }
    /* The PC closes windows when the next frame arrives; this frame is not yet in them. */
    emit_windows(e, now_ns);
    e->have_pending = true;
    e->pending_trigger = trigger;
    e->have_last_input = true;
    e->last_input_ns = now_ns;

    if (e->n_cycles == LOC_MAX_CYCLES) {
        drop_window(e, "cycle buffer overflow");
        e->stats.buffer_overflows++;
    }
    cycle = &e->cycles[e->n_cycles];
    problem = decode_cycle(p, len, cycle);
    if (problem) {
        e->reason = problem;
        e->stats.invalid_cycles++;
        tick(e, now_ns);
        return;
    }
    if (e->have_last_valid && now_ns - e->last_valid_ns > GAP_NS) {
        drop_window(e, "CSI gap; collecting a new window");
        e->stats.gaps++;
        cycle = &e->cycles[0];
        (void)decode_cycle(p, len, cycle);
    }
    e->have_last_valid = true;
    e->last_valid_ns = now_ns;
    e->stats.valid_cycles++;
    {
        uint64_t interval_ns = (uint64_t)llround(e->min_interval_s * 1e9);
        if (e->have_last_kept && now_ns - e->last_kept_ns + 1u < interval_ns) {
            e->stats.rate_limited_cycles++;
            tick(e, now_ns);
            return;
        }
    }
    e->have_last_kept = true;
    e->last_kept_ns = now_ns;
    cycle->time_ns = now_ns;
    cycle->time_s = (double)now_ns / 1e9;
    cycle->trigger_seq = trigger;
    if (!e->have_window) {
        e->have_window = true;
        e->window_start_s = cycle->time_s;
    }
    e->n_cycles++;
    tick(e, now_ns);
}

/* ---- public API ---------------------------------------------------------- */

loc_engine_t *loc_engine_open(const char *model_path, double stride_s,
                              loc_result_callback_t callback, void *user,
                              char *err, size_t err_len)
{
    loc_engine_t *e;
    if (!model_path) { set_err(err, err_len, "no model path"); return NULL; }
    e = calloc(1, sizeof(*e));
    if (!e) { set_err(err, err_len, "out of memory"); return NULL; }
    if (load_model(e, model_path, err, err_len) != 0) { loc_engine_close(e); return NULL; }
    e->stride_s = stride_s > 0.0 ? stride_s : DEFAULT_STRIDE_S;
    if (!isfinite(e->stride_s)) { set_err(err, err_len, "bad stride"); loc_engine_close(e); return NULL; }
    e->callback = callback;
    e->user = user;
    e->reason = "waiting for TX STATUS";
    return e;
}

void loc_engine_close(loc_engine_t *e)
{
    if (!e) return;
    free(e->mean); free(e->scale); free(e->coef); free(e->intercept);
    free(e);
}

void loc_engine_usb(loc_engine_t *e, uint8_t usb_type, const uint8_t *payload, size_t length,
                    uint64_t now_ns)
{
    if (!e || !payload) return;
    if (usb_type == 1u) on_status(e, payload, length, now_ns);
    else if (usb_type == 2u) on_cycle(e, payload, length, now_ns);
    else if (usb_type == 3u) on_ack(e, payload, length);
}

void loc_engine_tick(loc_engine_t *e, uint64_t now_ns) { if (e) tick(e, now_ns); }

void loc_engine_get_stats(const loc_engine_t *e, loc_stats_t *stats)
{ if (e && stats) *stats = e->stats; }

const char *loc_engine_reason(const loc_engine_t *e) { return e ? e->reason : "no engine"; }

int loc_engine_ready(const loc_engine_t *e) { return e && e->ready; }

void loc_engine_set_clock(loc_engine_t *e, loc_clock_ns_t clock_ns) { if (e) e->clock_ns = clock_ns; }
