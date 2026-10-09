/*
 * Software (ARM PS) implementation of the RX5 pose CNN.
 *
 * Bit-exact with the PL pose_cnn IP and ml/pose/int8_reference.py
 * (rounding contract nearest_half_away_from_zero_v1). It consumes the same
 * weight blob (685,136 bytes) and the same INT8 input window [15][128][10],
 * and produces the same 24 INT8 outputs, so PL and PS results can be compared
 * byte for byte.
 */
#ifndef POSE_CNN_SW_H
#define POSE_CNN_SW_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define POSE_SW_RX            5u
#define POSE_SW_H             128u
#define POSE_SW_W             10u
#define POSE_SW_INPUT_BYTES   (POSE_SW_RX * 3u * POSE_SW_H * POSE_SW_W)   /* 19200 */
#define POSE_SW_FLAT          (POSE_SW_RX * 1024u)                        /* 5120 */
#define POSE_SW_HIDDEN        128u
#define POSE_SW_OUTPUT_BYTES  24u
#define POSE_SW_BLOB_BYTES    685136u
#define POSE_SW_MAX_THREADS   POSE_SW_RX

typedef struct pose_cnn_sw pose_cnn_sw_t;

/* Per-call wall-clock breakdown in nanoseconds (CLOCK_MONOTONIC). */
typedef struct {
    uint64_t encoder_ns;   /* Conv1+GELU, Conv2+GELU, Pool for all RX */
    uint64_t fc_ns;        /* FC1+GELU, FC2+GELU, FC3                 */
    uint64_t total_ns;
} pose_cnn_sw_timing_t;

/* Optional intermediate tensors (same values as the RTL flat/fc1/fc2 dumps). */
typedef struct {
    int8_t flat[POSE_SW_FLAT];
    int8_t fc1[POSE_SW_HIDDEN];
    int8_t fc2[POSE_SW_HIDDEN];
} pose_cnn_sw_trace_t;

/*
 * Validate and unpack a blob (same checks as the PL loader: magic, version,
 * word count, shift range -31..63, positive output scale).
 * threads: 1..POSE_SW_MAX_THREADS; the encoder runs one RX per thread slot.
 * On failure returns NULL and writes a reason into err.
 */
pose_cnn_sw_t *pose_cnn_sw_create(const uint8_t *blob, size_t blob_bytes,
                                  unsigned threads, char *err, size_t err_len);
pose_cnn_sw_t *pose_cnn_sw_create_from_file(const char *path, unsigned threads,
                                            char *err, size_t err_len);
void pose_cnn_sw_destroy(pose_cnn_sw_t *sw);

float pose_cnn_sw_output_scale(const pose_cnn_sw_t *sw);
uint32_t pose_cnn_sw_scale_bits(const pose_cnn_sw_t *sw);
unsigned pose_cnn_sw_threads(const pose_cnn_sw_t *sw);

/* timing and trace may be NULL. Returns 0 on success. */
int pose_cnn_sw_infer(pose_cnn_sw_t *sw, const int8_t *input, size_t input_bytes,
                      int8_t output[POSE_SW_OUTPUT_BYTES],
                      pose_cnn_sw_timing_t *timing, pose_cnn_sw_trace_t *trace);

#ifdef __cplusplus
}
#endif

#endif
