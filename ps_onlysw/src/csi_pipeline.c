#include "csi_pipeline.h"

#include <math.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#define SERIAL_MAGIC 0x35534943u
#define SERIAL_VERSION 1u
#define FRAME_STATUS 1u
#define FRAME_CYCLE 2u
#define FRAME_ACK 3u
#define SERIAL_HEADER_BYTES 16u
#define STATUS_HEADER_BYTES 44u
#define STATUS_NODE_BYTES 22u
#define ACK_PAYLOAD_BYTES 76u
#define CYCLE_HEADER_BYTES 32u
#define CYCLE_SLOT_BYTES 6u
#define MAX_FRAME_PAYLOAD 12288u
#define RX_BUFFER_SIZE (256u * 1024u)
#define MAX_CSI_PAIRS 512u
#define MAX_CSI_BYTES (MAX_CSI_PAIRS * 2u)

typedef struct {
    uint8_t rx_index;
    bool present;
    int8_t rssi;
    uint16_t csi_len;
    int8_t csi[MAX_CSI_BYTES];
} cycle_record_t;

typedef struct {
    uint32_t trigger_seq;
    uint8_t active_nodes;
    uint8_t received_nodes;
    cycle_record_t records[CSI_RX_COUNT];
} cycle_t;

struct csi_pipeline {
    float input_scale;
    uint8_t rx_buffer[RX_BUFFER_SIZE];
    size_t rx_length;

    float raw_base[CSI_WINDOW_SIZE][CSI_RX_COUNT][CSI_SUBCARRIERS];
    float raw_mask[CSI_WINDOW_SIZE][CSI_RX_COUNT];
    unsigned raw_count;

    float stream_last_valid[CSI_RX_COUNT][CSI_SUBCARRIERS];
    unsigned stream_gap[CSI_RX_COUNT];
    bool stream_has_last_valid[CSI_RX_COUNT];

    float seed_last_valid[CSI_RX_COUNT][CSI_SUBCARRIERS];
    unsigned seed_gap[CSI_RX_COUNT];
    bool seed_has_last_valid[CSI_RX_COUNT];

    int8_t output[CSI_INPUT_BYTES];

    uint64_t current_window_seq;
    uint64_t next_window_seq;

    csi_pipeline_stats_t stats;
    csi_frame_callback_t frame_callback;
    void *frame_user;
};

static uint16_t rd16(const uint8_t *p)
{
    return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

static uint32_t rd32(const uint8_t *p)
{
    return (uint32_t)p[0] |
           ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) |
           ((uint32_t)p[3] << 24);
}

static uint32_t checksum32(
    const uint8_t *first,
    size_t first_length,
    const uint8_t *second,
    size_t second_length)
{
    uint32_t value = 0u;
    size_t i;
    for (i = 0; i < first_length; ++i) {
        value = ((value << 5) - value + first[i]) & 0xffffffffu;
    }
    for (i = 0; i < second_length; ++i) {
        value = ((value << 5) - value + second[i]) & 0xffffffffu;
    }
    return value;
}

static size_t find_magic(const uint8_t *buffer, size_t length)
{
    size_t i;
    for (i = 0; i + 4u <= length; ++i) {
        if (rd32(buffer + i) == SERIAL_MAGIC) {
            return i;
        }
    }
    return SIZE_MAX;
}

static void discard_prefix(csi_pipeline_t *pipeline, size_t length)
{
    if (length >= pipeline->rx_length) {
        pipeline->rx_length = 0u;
        return;
    }
    memmove(
        pipeline->rx_buffer,
        pipeline->rx_buffer + length,
        pipeline->rx_length - length);
    pipeline->rx_length -= length;
}

static int append_rx(csi_pipeline_t *pipeline, const uint8_t *data, size_t length)
{
    if (length > RX_BUFFER_SIZE || pipeline->rx_length + length > RX_BUFFER_SIZE) {
        return -1;
    }
    memcpy(pipeline->rx_buffer + pipeline->rx_length, data, length);
    pipeline->rx_length += length;
    pipeline->stats.bytes_received += length;
    return 0;
}

static int parse_cycle_payload(
    csi_pipeline_t *pipeline,
    const uint8_t *payload,
    size_t length,
    cycle_t *cycle)
{
    size_t cursor = CYCLE_HEADER_BYTES;
    unsigned slot;
    unsigned stored = 0u;

    if (length < CYCLE_HEADER_BYTES) {
        pipeline->stats.malformed_frames++;
        return -1;
    }

    memset(cycle, 0, sizeof(*cycle));
    cycle->trigger_seq = rd32(payload + 4u);
    cycle->active_nodes = payload[28u];
    cycle->received_nodes = payload[29u];

    if (cycle->active_nodes > 32u) {
        pipeline->stats.malformed_frames++;
        return -1;
    }

    for (slot = 0u; slot < cycle->active_nodes; ++slot) {
        uint8_t rx_index;
        uint8_t present;
        int8_t rssi;
        uint16_t csi_len;
        cycle_record_t *record;

        if (cursor + CYCLE_SLOT_BYTES > length) {
            pipeline->stats.malformed_frames++;
            return -1;
        }

        rx_index = payload[cursor + 0u];
        present = payload[cursor + 1u];
        rssi = (int8_t)payload[cursor + 2u];
        csi_len = rd16(payload + cursor + 4u);
        cursor += CYCLE_SLOT_BYTES;

        if (cursor + csi_len > length || csi_len > MAX_CSI_BYTES || (csi_len & 1u) != 0u) {
            pipeline->stats.malformed_frames++;
            return -1;
        }

        if (present != 0u && rx_index < CSI_RX_COUNT) {
            record = &cycle->records[rx_index];
            record->rx_index = rx_index;
            record->present = true;
            record->rssi = rssi;
            record->csi_len = csi_len;
            memcpy(record->csi, payload + cursor, csi_len);
            stored++;
        }
        cursor += csi_len;
    }

    if (cursor != length) {
        pipeline->stats.malformed_frames++;
        return -1;
    }
    return (int)stored;
}

static void parse_status_payload(
    csi_pipeline_t *pipeline,
    const uint8_t *payload,
    size_t length)
{
    uint8_t node_entries;

    if (length < STATUS_HEADER_BYTES) {
        pipeline->stats.malformed_frames++;
        return;
    }
    node_entries = payload[7u];
    if (length < STATUS_HEADER_BYTES + (size_t)node_entries * STATUS_NODE_BYTES) {
        pipeline->stats.malformed_frames++;
        return;
    }
    pipeline->stats.status_frames++;
    pipeline->stats.last_status_mode = payload[0u];
    pipeline->stats.last_status_wifi_channel = payload[1u];
    pipeline->stats.last_status_connected_nodes = payload[4u];
    pipeline->stats.last_status_active_nodes = payload[5u];
    pipeline->stats.last_status_saved_nodes = payload[6u];
    pipeline->stats.last_status_generation = rd32(payload + 16u);
    pipeline->stats.last_status_next_trigger = rd32(payload + 20u);
    pipeline->stats.last_status_uart_seq = rd32(payload + 24u);
    pipeline->stats.last_status_trigger_sent = rd32(payload + 28u);
    pipeline->stats.last_status_cycle_timeouts = rd32(payload + 32u);
}

static void parse_ack_payload(
    csi_pipeline_t *pipeline,
    const uint8_t *payload,
    size_t length)
{
    size_t message_length;

    if (length < ACK_PAYLOAD_BYTES) {
        pipeline->stats.malformed_frames++;
        return;
    }
    pipeline->stats.ack_frames++;
    pipeline->stats.last_ack_ok = payload[0u];
    pipeline->stats.last_ack_mode = payload[1u];
    memcpy(pipeline->stats.last_ack_message, payload + 12u, 64u);
    pipeline->stats.last_ack_message[64] = '\0';
    for (message_length = 0u;
         message_length < 64u && pipeline->stats.last_ack_message[message_length] != '\0';
         ++message_length) {
    }
    pipeline->stats.last_ack_message[message_length] = '\0';
}

/* Returns 1 for a cycle, 0 when more bytes are needed, and -1 on fatal input. */
static int pop_cycle(csi_pipeline_t *pipeline, cycle_t *cycle)
{
    while (pipeline->rx_length >= SERIAL_HEADER_BYTES) {
        size_t magic_position = find_magic(pipeline->rx_buffer, pipeline->rx_length);
        uint8_t version;
        uint8_t frame_type;
        uint16_t payload_length;
        uint32_t expected_checksum;
        uint32_t actual_checksum;
        size_t total_length;

        if (magic_position == SIZE_MAX) {
            if (pipeline->rx_length > 3u) {
                memmove(
                    pipeline->rx_buffer,
                    pipeline->rx_buffer + pipeline->rx_length - 3u,
                    3u);
                pipeline->rx_length = 3u;
            }
            return 0;
        }
        if (magic_position != 0u) {
            discard_prefix(pipeline, magic_position);
        }
        if (pipeline->rx_length < SERIAL_HEADER_BYTES) {
            return 0;
        }

        version = pipeline->rx_buffer[4u];
        frame_type = pipeline->rx_buffer[5u];
        payload_length = rd16(pipeline->rx_buffer + 6u);
        expected_checksum = rd32(pipeline->rx_buffer + 12u);

        if (version != SERIAL_VERSION || payload_length > MAX_FRAME_PAYLOAD) {
            pipeline->stats.malformed_frames++;
            discard_prefix(pipeline, 1u);
            continue;
        }

        total_length = SERIAL_HEADER_BYTES + payload_length;
        if (pipeline->rx_length < total_length) {
            return 0;
        }

        actual_checksum = checksum32(
            pipeline->rx_buffer,
            12u,
            pipeline->rx_buffer + SERIAL_HEADER_BYTES,
            payload_length);
        if (actual_checksum != expected_checksum) {
            pipeline->stats.checksum_errors++;
            discard_prefix(pipeline, 1u);
            continue;
        }

        pipeline->stats.valid_frames++;
        if (pipeline->frame_callback) {
            pipeline->frame_callback(frame_type, rd32(pipeline->rx_buffer + 8u),
                pipeline->rx_buffer + SERIAL_HEADER_BYTES, payload_length,
                pipeline->frame_user);
        }
        if (frame_type == FRAME_CYCLE) {
            int record_count = parse_cycle_payload(
                pipeline,
                pipeline->rx_buffer + SERIAL_HEADER_BYTES,
                payload_length,
                cycle);
            discard_prefix(pipeline, total_length);
            if (record_count > 0) {
                pipeline->stats.cycles_emitted++;
                return 1;
            }
        } else if (frame_type == FRAME_STATUS) {
            parse_status_payload(
                pipeline,
                pipeline->rx_buffer + SERIAL_HEADER_BYTES,
                payload_length);
            discard_prefix(pipeline, total_length);
        } else if (frame_type == FRAME_ACK) {
            parse_ack_payload(
                pipeline,
                pipeline->rx_buffer + SERIAL_HEADER_BYTES,
                payload_length);
            discard_prefix(pipeline, total_length);
        } else {
            discard_prefix(pipeline, total_length);
        }
    }
    return 0;
}

static void normalize(float *values, size_t length)
{
    double sum = 0.0;
    double variance = 0.0;
    double mean;
    double standard_deviation;
    double denominator;
    size_t i;

    for (i = 0u; i < length; ++i) {
        sum += values[i];
    }
    mean = sum / (double)length;
    for (i = 0u; i < length; ++i) {
        double difference = (double)values[i] - mean;
        variance += difference * difference;
    }
    standard_deviation = sqrt(variance / (double)length);
    denominator = standard_deviation >= 1e-3 ? standard_deviation : 1.0;

    for (i = 0u; i < length; ++i) {
        double value = ((double)values[i] - mean) / denominator;
        if (value > 4.0) value = 4.0;
        if (value < -4.0) value = -4.0;
        values[i] = (float)value;
    }
}

static int parse_csi_feature(
    const int8_t *csi,
    uint16_t csi_length,
    float output[CSI_SUBCARRIERS])
{
    size_t pair_count = csi_length / 2u;
    float values[MAX_CSI_PAIRS];
    const float *raw_chunk;
    size_t i;

    if (pair_count < CSI_SUBCARRIERS || pair_count > MAX_CSI_PAIRS) {
        return -1;
    }

    for (i = 0u; i < pair_count; ++i) {
        int i_value = csi[i * 2u + 0u];
        int q_value = csi[i * 2u + 1u];
        values[i] = log1pf((float)(i_value * i_value + q_value * q_value));
    }
    normalize(values, pair_count);

    /* Keep the final 128 HT-LTF pairs, then map [0..63,-64..-1] to [-64..63]. */
    raw_chunk = values + pair_count - CSI_SUBCARRIERS;
    for (i = 0u; i < 64u; ++i) {
        output[64u + i] = raw_chunk[i];
        output[i] = raw_chunk[64u + i];
    }
    normalize(output, CSI_SUBCARRIERS);
    return 0;
}

static int8_t quantize_int8(float value, float scale)
{
    float scaled = value / scale;
    if (scaled >= 127.0f) return 127;
    if (scaled <= -127.0f) return -127;
    int quantized = (int)lrintf(scaled);
    if (quantized > 127) quantized = 127;
    if (quantized < -127) quantized = -127;
    return (int8_t)quantized;
}

static void capture_seed(csi_pipeline_t *pipeline)
{
    memcpy(pipeline->seed_last_valid, pipeline->stream_last_valid, sizeof(pipeline->seed_last_valid));
    memcpy(pipeline->seed_gap, pipeline->stream_gap, sizeof(pipeline->seed_gap));
    memcpy(pipeline->seed_has_last_valid, pipeline->stream_has_last_valid, sizeof(pipeline->seed_has_last_valid));
}

static void encode_window(csi_pipeline_t *pipeline)
{
    float filled[CSI_WINDOW_SIZE][CSI_RX_COUNT][CSI_SUBCARRIERS] = {{{0}}};
    float last_valid[CSI_RX_COUNT][CSI_SUBCARRIERS];
    unsigned gap[CSI_RX_COUNT];
    bool has_last_valid[CSI_RX_COUNT];
    unsigned frame;
    unsigned node;
    unsigned subcarrier;

    memcpy(last_valid, pipeline->seed_last_valid, sizeof(last_valid));
    memcpy(gap, pipeline->seed_gap, sizeof(gap));
    memcpy(has_last_valid, pipeline->seed_has_last_valid, sizeof(has_last_valid));

    for (frame = 0u; frame < CSI_WINDOW_SIZE; ++frame) {
        for (node = 0u; node < CSI_RX_COUNT; ++node) {
            if (pipeline->raw_mask[frame][node] > 0.5f) {
                memcpy(filled[frame][node], pipeline->raw_base[frame][node], sizeof(filled[frame][node]));
                memcpy(last_valid[node], pipeline->raw_base[frame][node], sizeof(last_valid[node]));
                has_last_valid[node] = true;
                gap[node] = 0u;
            } else {
                if (has_last_valid[node] && gap[node] < CSI_MAX_FILL_GAP) {
                    memcpy(filled[frame][node], last_valid[node], sizeof(filled[frame][node]));
                }
                gap[node]++;
            }
        }
    }

    for (node = 0u; node < CSI_RX_COUNT; ++node) {
        unsigned channel_base = node;
        unsigned channel_delta = CSI_RX_COUNT + node;
        unsigned channel_mask = CSI_RX_COUNT * 2u + node;
        for (subcarrier = 0u; subcarrier < CSI_SUBCARRIERS; ++subcarrier) {
            for (frame = 0u; frame < CSI_WINDOW_SIZE; ++frame) {
                float base_value = filled[frame][node][subcarrier];
                float delta_value = frame == 0u
                    ? 0.0f
                    : filled[frame][node][subcarrier] - filled[frame - 1u][node][subcarrier];
                size_t base_index =
                    (channel_base * CSI_SUBCARRIERS + subcarrier) * CSI_WINDOW_SIZE + frame;
                size_t delta_index =
                    (channel_delta * CSI_SUBCARRIERS + subcarrier) * CSI_WINDOW_SIZE + frame;
                size_t mask_index =
                    (channel_mask * CSI_SUBCARRIERS + subcarrier) * CSI_WINDOW_SIZE + frame;

                pipeline->output[base_index] = quantize_int8(base_value, pipeline->input_scale);
                pipeline->output[delta_index] = quantize_int8(delta_value, pipeline->input_scale);
                pipeline->output[mask_index] = quantize_int8(
                    pipeline->raw_mask[frame][node],
                    pipeline->input_scale);
            }
        }
    }
}

static int push_cycle(
    csi_pipeline_t *pipeline,
    const cycle_t *cycle,
    csi_window_callback_t callback,
    void *user)
{
    uint64_t window_seq = pipeline->current_window_seq;
    float base[CSI_RX_COUNT][CSI_SUBCARRIERS] = {{0}};
    float mask[CSI_RX_COUNT] = {0};
    unsigned node;

    pipeline->stats.last_active_nodes = cycle->active_nodes;
    pipeline->stats.last_received_nodes = cycle->received_nodes;
    for (node = 0u; node < CSI_RX_COUNT; ++node) {
        if (cycle->records[node].present) {
            pipeline->stats.rx_present[node]++;
        } else {
            pipeline->stats.rx_missing[node]++;
        }
    }

    if (pipeline->raw_count == 0u) {
        capture_seed(pipeline);
    }

    for (node = 0u; node < CSI_RX_COUNT; ++node) {
        const cycle_record_t *record = &cycle->records[node];
        if (record->present &&
            parse_csi_feature(record->csi, record->csi_len, base[node]) == 0) {
            mask[node] = 1.0f;
        }
    }

    memcpy(pipeline->raw_base[pipeline->raw_count], base, sizeof(base));
    for (node = 0u; node < CSI_RX_COUNT; ++node) {
        pipeline->raw_mask[pipeline->raw_count][node] = mask[node];
        if (mask[node] > 0.5f) {
            memcpy(pipeline->stream_last_valid[node], base[node], sizeof(base[node]));
            pipeline->stream_has_last_valid[node] = true;
            pipeline->stream_gap[node] = 0u;
        } else {
            pipeline->stream_gap[node]++;
        }
    }

    pipeline->raw_count++;
    if (pipeline->raw_count < CSI_WINDOW_SIZE) {
        return 0;
    }

    encode_window(pipeline);
    pipeline->raw_count = 0u;
    pipeline->current_window_seq = 0u;
    pipeline->stats.windows_emitted++;
    if (callback != NULL) {
        return callback(
            pipeline->output,
            CSI_INPUT_BYTES,
            window_seq,
            cycle->trigger_seq,
            user);
    }
    return 0;
}

csi_pipeline_t *csi_pipeline_create(float input_scale)
{
    csi_pipeline_t *pipeline;
    unsigned node;

    if (!isfinite(input_scale) || input_scale <= 0.0f) {
        return NULL;
    }
    pipeline = (csi_pipeline_t *)calloc(1u, sizeof(*pipeline));
    if (pipeline == NULL) {
        return NULL;
    }
    pipeline->input_scale = input_scale;
    pipeline->current_window_seq = 0u;
    pipeline->next_window_seq = 1u;
    for (node = 0u; node < CSI_RX_COUNT; ++node) {
        pipeline->stream_gap[node] = CSI_MAX_FILL_GAP;
        pipeline->seed_gap[node] = CSI_MAX_FILL_GAP;
    }
    return pipeline;
}

void csi_pipeline_destroy(csi_pipeline_t *pipeline)
{
    free(pipeline);
}

void csi_pipeline_resync(csi_pipeline_t *pipeline)
{
    unsigned node;

    if (pipeline == NULL) {
        return;
    }
    pipeline->rx_length = 0u;
    pipeline->raw_count = 0u;
    pipeline->current_window_seq = 0u;
    memset(pipeline->raw_base, 0, sizeof(pipeline->raw_base));
    memset(pipeline->raw_mask, 0, sizeof(pipeline->raw_mask));
    memset(pipeline->stream_last_valid, 0, sizeof(pipeline->stream_last_valid));
    memset(pipeline->stream_has_last_valid, 0, sizeof(pipeline->stream_has_last_valid));
    memset(pipeline->seed_last_valid, 0, sizeof(pipeline->seed_last_valid));
    memset(pipeline->seed_has_last_valid, 0, sizeof(pipeline->seed_has_last_valid));
    for (node = 0u; node < CSI_RX_COUNT; ++node) {
        pipeline->stream_gap[node] = CSI_MAX_FILL_GAP;
        pipeline->seed_gap[node] = CSI_MAX_FILL_GAP;
    }
}

int csi_pipeline_feed(
    csi_pipeline_t *pipeline,
    const uint8_t *data,
    size_t length,
    csi_window_callback_t window_callback,
    csi_record_callback_t record_callback,
    void *user)
{
    cycle_t cycle;
    int result;

    if (pipeline == NULL || (length != 0u && data == NULL)) {
        return -1;
    }
    if (append_rx(pipeline, data, length) != 0) {
        return -1;
    }

    for (;;) {
        int callback_result;
        uint64_t window_seq;
        uint8_t window_pos;
        uint8_t present_mask = 0u;
        unsigned node;

        result = pop_cycle(pipeline, &cycle);
        if (result <= 0) {
            return result;
        }

        if (pipeline->raw_count == 0u) {
            pipeline->current_window_seq = pipeline->next_window_seq++;
        }
        window_seq = pipeline->current_window_seq;
        window_pos = (uint8_t)pipeline->raw_count;

        for (node = 0u; node < CSI_RX_COUNT; ++node) {
            if (cycle.records[node].present) {
                present_mask |= (uint8_t)(1u << node);
            }
        }

        if (record_callback != NULL) {
            for (node = 0u; node < CSI_RX_COUNT; ++node) {
                const cycle_record_t *record = &cycle.records[node];
                if (!record->present) {
                    continue;
                }
                record_callback(
                    window_seq,
                    window_pos,
                    cycle.trigger_seq,
                    cycle.active_nodes,
                    cycle.received_nodes,
                    present_mask,
                    record->rx_index,
                    record->rssi,
                    record->csi,
                    record->csi_len,
                    user);
            }
        }

        callback_result = push_cycle(pipeline, &cycle, window_callback, user);
        if (callback_result != 0) {
            return callback_result;
        }
    }
}

void csi_pipeline_get_stats(
    const csi_pipeline_t *pipeline,
    csi_pipeline_stats_t *stats)
{
    if (pipeline != NULL && stats != NULL) {
        *stats = pipeline->stats;
    }
}

void csi_pipeline_set_frame_callback(csi_pipeline_t *pipeline,
    csi_frame_callback_t callback, void *user)
{
    if (pipeline) { pipeline->frame_callback = callback; pipeline->frame_user = user; }
}
