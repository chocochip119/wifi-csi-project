#ifndef WIMOTION_CSI_PIPELINE_H
#define WIMOTION_CSI_PIPELINE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define CSI_RX_COUNT 5u
#define CSI_FEATURE_PLANES 3u
#define CSI_INPUT_CHANNELS (CSI_RX_COUNT * CSI_FEATURE_PLANES)
#define CSI_SUBCARRIERS 128u
#define CSI_WINDOW_SIZE 10u
#define CSI_WINDOW_STRIDE 10u
#define CSI_INPUT_BYTES (CSI_INPUT_CHANNELS * CSI_SUBCARRIERS * CSI_WINDOW_SIZE)
#define CSI_MAX_FILL_GAP 3u

typedef struct csi_pipeline csi_pipeline_t;

typedef struct {
    uint64_t bytes_received;
    uint64_t valid_frames;
    uint64_t status_frames;
    uint64_t ack_frames;
    uint64_t checksum_errors;
    uint64_t malformed_frames;
    uint64_t cycles_emitted;
    uint64_t windows_emitted;
    uint8_t last_active_nodes;
    uint8_t last_received_nodes;
    uint8_t last_status_mode;
    uint8_t last_status_wifi_channel;
    uint8_t last_status_connected_nodes;
    uint8_t last_status_active_nodes;
    uint8_t last_status_saved_nodes;
    uint32_t last_status_generation;
    uint32_t last_status_next_trigger;
    uint32_t last_status_uart_seq;
    uint32_t last_status_trigger_sent;
    uint32_t last_status_cycle_timeouts;
    uint8_t last_ack_ok;
    uint8_t last_ack_mode;
    char last_ack_message[65];
    uint64_t rx_present[CSI_RX_COUNT];
    uint64_t rx_missing[CSI_RX_COUNT];
} csi_pipeline_stats_t;

typedef int (*csi_window_callback_t)(
    const int8_t *input,
    size_t input_bytes,
    uint32_t trigger_seq,
    void *user);

/*
 * input_scale is the INT8 input tensor scale exported with the 5-RX model.
 * The parser/preprocessor can be verified with a temporary positive scale,
 * but deployment must use the scale stored in the final model/weight blob.
 */
csi_pipeline_t *csi_pipeline_create(float input_scale);
void csi_pipeline_destroy(csi_pipeline_t *pipeline);

/*
 * Drop an incomplete serial frame/window after a live-stream stall while
 * retaining cumulative statistics.  The next complete cycle starts a fresh
 * temporal window, so stale samples are never mixed with a restarted stream.
 */
void csi_pipeline_resync(csi_pipeline_t *pipeline);

/* Feed any fragment size. Multiple serial frames in one call are supported. */
int csi_pipeline_feed(
    csi_pipeline_t *pipeline,
    const uint8_t *data,
    size_t length,
    csi_window_callback_t callback,
    void *user);

void csi_pipeline_get_stats(
    const csi_pipeline_t *pipeline,
    csi_pipeline_stats_t *stats);

#ifdef __cplusplus
}
#endif

#endif
