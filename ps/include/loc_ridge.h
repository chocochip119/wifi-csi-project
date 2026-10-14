#ifndef WISE_LOC_RIDGE_H
#define WISE_LOC_RIDGE_H

/*
 * PS-side location inference: the PC Portable Ridge live engine in C.
 *
 * Input is the checksum-valid TX USB payload (STATUS=1, CYCLE=2, ACK=3) with a
 * CLOCK_MONOTONIC timestamp.  Preprocessing (5-RX cycle check, I/Q decode,
 * amplitude, 10 Hz throttle, 2 s window, mean, StandardScaler) and the Ridge
 * argmax follow pc/backend/localization/location_live.py and location_core.py.
 * No POSIX or hardware access, so the same file builds on the host for tests.
 */

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define LOC_RX_COUNT 5u
#define LOC_CSI_BYTES 384u
#define LOC_DROP_PAIRS 2u
#define LOC_PAIRS_PER_RX (LOC_CSI_BYTES / 2u - LOC_DROP_PAIRS)
#define LOC_AMP_FEATURES (LOC_RX_COUNT * LOC_PAIRS_PER_RX)
#define LOC_FEATURES (LOC_AMP_FEATURES + LOC_RX_COUNT)
#define LOC_MAX_CLASSES 16u
#define LOC_NO_COORD INT16_MIN

/* Class codes on the wire: index in labels.CLASSES (p01..p10, empty). */
#define LOC_CODE_EMPTY 10u

typedef struct loc_engine loc_engine_t;

typedef struct {
    uint32_t window_id;
    uint32_t end_trigger_seq;
    uint32_t infer_us;
    uint8_t class_code;
    uint8_t occupied;
    uint8_t window_cycles;
    uint8_t n_scores;
    int16_t x_cm;               /* LOC_NO_COORD when the class has no point */
    int16_t y_cm;
    uint64_t window_start_us;   /* producer clock, same basis as the input */
    uint64_t window_end_us;
    float scores[LOC_MAX_CLASSES]; /* indexed by class_code */
} loc_result_t;

typedef struct {
    uint64_t status_frames, invalid_status, ack_resets;
    uint64_t cycle_frames, not_ready_frames, chronology_rejects;
    uint64_t invalid_cycles, valid_cycles, rate_limited_cycles;
    uint64_t gaps, stale_resets, buffer_overflows;
    uint64_t short_windows, predictions;
} loc_stats_t;

typedef void (*loc_result_callback_t)(const loc_result_t *result, void *user);

/* stride_s <= 0 keeps the PC live default of 0.5 s. err may be NULL. */
loc_engine_t *loc_engine_open(const char *model_path, double stride_s,
                              loc_result_callback_t callback, void *user,
                              char *err, size_t err_len);
void loc_engine_close(loc_engine_t *engine);

/* usb_type: 1=STATUS, 2=CYCLE, 3=ACK (TX USB frame types). Others are ignored. */
void loc_engine_usb(loc_engine_t *engine, uint8_t usb_type,
                    const uint8_t *payload, size_t length, uint64_t now_ns);

/* Expire stale STATUS / CSI while no frames arrive. */
void loc_engine_tick(loc_engine_t *engine, uint64_t now_ns);

void loc_engine_get_stats(const loc_engine_t *engine, loc_stats_t *stats);
const char *loc_engine_reason(const loc_engine_t *engine);
int loc_engine_ready(const loc_engine_t *engine);

/* Optional timing hook for infer_us; the default uses the input clock delta 0. */
typedef uint64_t (*loc_clock_ns_t)(void);
void loc_engine_set_clock(loc_engine_t *engine, loc_clock_ns_t clock_ns);

#ifdef __cplusplus
}
#endif

#endif
