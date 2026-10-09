/*
 * PS-only variant of pose_cnn_rx5_live: identical USB/CSI/TCP path, but the
 * pose CNN runs on the ARM cores (pose_cnn_sw.c) instead of the PL IP.
 * No /dev/mem, no FPGA lock, no bitstream needed. Used to compare PS vs PL
 * inference speed on the same live stream.
 *
 * SW threads: POSE_SW_THREADS=1..5 (default 1; Zynq-7020 has 2 cores).
 */
#define _DEFAULT_SOURCE
#define _POSIX_C_SOURCE 200809L

#include "csi_pipeline.h"
#include "wise_server.h"
#include "pose_cnn_regs.h"
#include "pose_cnn_sw.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <pthread.h>
#include <inttypes.h>
#include <math.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

#define DEFAULT_BLOB_PATH          "/usr/share/pose-cnn-rx5/blob_rx5_test.bin"
#define READ_CHUNK                 16384u
#define POLL_INTERVAL_MS           250
#define STREAM_STALL_MS            5000u
#define SERIAL_WRITE_TIMEOUT_MS    1000u

#define UDP_QUEUE_DEPTH            1024u
#define UDP_PACKET_MAX_BYTES       1200u
#define UDP_MAGIC_0                'W'
#define UDP_MAGIC_1                'C'
#define UDP_MAGIC_2                'S'
#define UDP_MAGIC_3                'I'
#define UDP_VERSION                1u
#define UDP_TYPE_CSI               1u
#define UDP_TYPE_POSE              2u
#define UDP_POSE_RX_ID             0xffu
#define UDP_POSE_WINDOW_POS        0xffu

typedef struct {
    pose_cnn_sw_t *sw;
    float output_scale;
    uint32_t scale_bits;
} cnn_engine_t;


typedef struct __attribute__((packed)) {
    uint8_t magic[4];
    uint8_t version;
    uint8_t type;
    uint8_t rx_id;
    uint8_t window_pos;
    uint32_t packet_seq;
    uint64_t window_seq;
    uint32_t trigger_seq;
    uint8_t present_mask;
    uint8_t active_nodes;
    uint8_t received_nodes;
    int8_t rssi;
    uint16_t payload_len;
    uint64_t timestamp_ns;
} udp_wire_header_t;

typedef struct {
    uint16_t length;
    uint8_t data[UDP_PACKET_MAX_BYTES];
} udp_slot_t;

typedef struct {
    int fd;
    bool enabled;
    bool thread_started;
    bool running;
    pthread_t thread;
    struct sockaddr_in target;
    udp_slot_t *slots;
    uint32_t head;
    uint32_t tail;
    uint32_t packet_seq;

    uint64_t enqueued;
    uint64_t queue_dropped;
    uint64_t sent;
    uint64_t send_errors;
    uint64_t eagain;
    uint64_t enobufs;
    uint64_t bytes_sent;
} udp_sender_t;

_Static_assert(sizeof(udp_wire_header_t) == 38u, "unexpected UDP header size");

typedef struct {
    FILE *dump;
    uint64_t windows;
    uint64_t max_windows;
    csi_pipeline_t *pipeline;
    cnn_engine_t *engine;
    udp_sender_t udp;
    wise_server_t *tcp;
    uint64_t infer_total_us;
    uint64_t infer_min_us;
    uint64_t infer_max_us;
} live_context_t;

static void on_usb_frame(uint8_t type, uint32_t seq,
    const uint8_t *payload, size_t length, void *user)
{
    live_context_t *context = user;
    if (wise_server_usb(context->tcp, type, seq, payload, length) < 0)
        fprintf(stderr, "TCP rejected malformed USB payload type=%u length=%zu\n", type, length);
}

static volatile sig_atomic_t stop_requested = 0;

static uint64_t monotonic_ms(void)
{
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) {
        return 0u;
    }
    return (uint64_t)now.tv_sec * 1000u + (uint64_t)now.tv_nsec / 1000000u;
}

static uint64_t monotonic_ns(void)
{
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) {
        return 0u;
    }
    return (uint64_t)now.tv_sec * 1000000000ull + (uint64_t)now.tv_nsec;
}

static void on_signal(int signal_number)
{
    (void)signal_number;
    stop_requested = 1;
}

static int udp_enqueue(
    udp_sender_t *sender,
    const uint8_t *data,
    size_t length)
{
    uint32_t head;
    uint32_t next;
    uint32_t tail;
    udp_slot_t *slot;

    if (sender == NULL || !sender->enabled) {
        return 0;
    }
    if (data == NULL || length == 0u || length > UDP_PACKET_MAX_BYTES) {
        sender->queue_dropped++;
        return -1;
    }

    head = __atomic_load_n(&sender->head, __ATOMIC_RELAXED);
    tail = __atomic_load_n(&sender->tail, __ATOMIC_ACQUIRE);
    next = (head + 1u) % UDP_QUEUE_DEPTH;
    if (next == tail) {
        sender->queue_dropped++;
        return -1;
    }

    slot = &sender->slots[head];
    memcpy(slot->data, data, length);
    slot->length = (uint16_t)length;
    __atomic_store_n(&sender->head, next, __ATOMIC_RELEASE);
    sender->enqueued++;
    return 0;
}

static void *udp_sender_thread(void *arg)
{
    udp_sender_t *sender = (udp_sender_t *)arg;
    const struct timespec idle_sleep = {0, 1000000L};

    for (;;) {
        uint32_t tail = __atomic_load_n(&sender->tail, __ATOMIC_RELAXED);
        uint32_t head = __atomic_load_n(&sender->head, __ATOMIC_ACQUIRE);

        if (tail == head) {
            if (!__atomic_load_n(&sender->running, __ATOMIC_ACQUIRE)) {
                break;
            }
            nanosleep(&idle_sleep, NULL);
            continue;
        }

        {
            udp_slot_t *slot = &sender->slots[tail];
            ssize_t sent = sendto(
                sender->fd,
                slot->data,
                slot->length,
                MSG_DONTWAIT,
                (const struct sockaddr *)&sender->target,
                sizeof(sender->target));

            if (sent == (ssize_t)slot->length) {
                sender->sent++;
                sender->bytes_sent += (uint64_t)sent;
            } else {
                int saved_errno = errno;
                sender->send_errors++;
                if (sent < 0 &&
                    (saved_errno == EAGAIN || saved_errno == EWOULDBLOCK)) {
                    sender->eagain++;
                } else if (sent < 0 && saved_errno == ENOBUFS) {
                    sender->enobufs++;
                }
            }
        }

        __atomic_store_n(
            &sender->tail,
            (tail + 1u) % UDP_QUEUE_DEPTH,
            __ATOMIC_RELEASE);
    }

    return NULL;
}

static int udp_sender_start(udp_sender_t *sender, const char *target)
{
    char address[64];
    const char *colon;
    char *end;
    unsigned long port;
    size_t address_length;
    int flags;

    memset(sender, 0, sizeof(*sender));
    sender->fd = -1;

    if (target == NULL || *target == '\0') {
        return 0;
    }

    colon = strrchr(target, ':');
    if (colon == NULL || colon == target || colon[1] == '\0') {
        fprintf(stderr, "CSI_UDP_TARGET must be IPv4:PORT, got: %s\n", target);
        return -1;
    }

    address_length = (size_t)(colon - target);
    if (address_length >= sizeof(address)) {
        fprintf(stderr, "UDP IPv4 address is too long: %s\n", target);
        return -1;
    }
    memcpy(address, target, address_length);
    address[address_length] = '\0';

    errno = 0;
    port = strtoul(colon + 1, &end, 10);
    if (errno != 0 || *end != '\0' || port == 0ul || port > 65535ul) {
        fprintf(stderr, "invalid UDP port in CSI_UDP_TARGET: %s\n", target);
        return -1;
    }

    sender->fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (sender->fd < 0) {
        fprintf(stderr, "UDP socket failed: %s\n", strerror(errno));
        return -1;
    }

    flags = fcntl(sender->fd, F_GETFL, 0);
    if (flags < 0 ||
        fcntl(sender->fd, F_SETFL, flags | O_NONBLOCK) != 0) {
        fprintf(stderr, "UDP nonblocking setup failed: %s\n", strerror(errno));
        close(sender->fd);
        sender->fd = -1;
        return -1;
    }

    memset(&sender->target, 0, sizeof(sender->target));
    sender->target.sin_family = AF_INET;
    sender->target.sin_port = htons((uint16_t)port);
    if (inet_pton(AF_INET, address, &sender->target.sin_addr) != 1) {
        fprintf(stderr, "invalid UDP IPv4 address: %s\n", address);
        close(sender->fd);
        sender->fd = -1;
        return -1;
    }

    sender->slots = (udp_slot_t *)calloc(UDP_QUEUE_DEPTH, sizeof(*sender->slots));
    if (sender->slots == NULL) {
        fprintf(stderr, "UDP queue allocation failed\n");
        close(sender->fd);
        sender->fd = -1;
        return -1;
    }

    sender->enabled = true;
    __atomic_store_n(&sender->running, true, __ATOMIC_RELEASE);
    if (pthread_create(&sender->thread, NULL, udp_sender_thread, sender) != 0) {
        fprintf(stderr, "UDP sender thread creation failed\n");
        __atomic_store_n(&sender->running, false, __ATOMIC_RELEASE);
        sender->enabled = false;
        free(sender->slots);
        sender->slots = NULL;
        close(sender->fd);
        sender->fd = -1;
        return -1;
    }

    sender->thread_started = true;
    printf(
        "UDP bypass ON -> %s:%lu queue_depth=%u packet_max=%u\n",
        address,
        port,
        (unsigned)UDP_QUEUE_DEPTH,
        (unsigned)UDP_PACKET_MAX_BYTES);
    return 0;
}

static void udp_sender_stop(udp_sender_t *sender)
{
    if (sender == NULL) {
        return;
    }

    if (sender->thread_started) {
        __atomic_store_n(&sender->running, false, __ATOMIC_RELEASE);
        (void)pthread_join(sender->thread, NULL);
        sender->thread_started = false;
    }

    if (sender->fd >= 0) {
        close(sender->fd);
        sender->fd = -1;
    }
    free(sender->slots);
    sender->slots = NULL;
    sender->enabled = false;
}

static void udp_fill_header(
    live_context_t *context,
    udp_wire_header_t *header,
    uint8_t type,
    uint8_t rx_id,
    uint8_t window_pos,
    uint64_t window_seq,
    uint32_t trigger_seq,
    uint8_t present_mask,
    uint8_t active_nodes,
    uint8_t received_nodes,
    int8_t rssi,
    uint16_t payload_len)
{
    memset(header, 0, sizeof(*header));
    header->magic[0] = UDP_MAGIC_0;
    header->magic[1] = UDP_MAGIC_1;
    header->magic[2] = UDP_MAGIC_2;
    header->magic[3] = UDP_MAGIC_3;
    header->version = UDP_VERSION;
    header->type = type;
    header->rx_id = rx_id;
    header->window_pos = window_pos;
    header->packet_seq = context->udp.packet_seq++;
    header->window_seq = window_seq;
    header->trigger_seq = trigger_seq;
    header->present_mask = present_mask;
    header->active_nodes = active_nodes;
    header->received_nodes = received_nodes;
    header->rssi = rssi;
    header->payload_len = payload_len;
    header->timestamp_ns = monotonic_ns();
}

static void on_csi_record_udp(
    uint64_t window_seq,
    uint8_t window_pos,
    uint32_t trigger_seq,
    uint8_t active_nodes,
    uint8_t received_nodes,
    uint8_t present_mask,
    uint8_t rx_index,
    int8_t rssi,
    const int8_t *csi,
    uint16_t csi_len,
    void *user)
{
    live_context_t *context = (live_context_t *)user;
    uint8_t packet[UDP_PACKET_MAX_BYTES];
    udp_wire_header_t header;
    size_t packet_bytes;

    if (context == NULL || !context->udp.enabled) {
        return;
    }

    packet_bytes = sizeof(header) + (size_t)csi_len;
    if (packet_bytes > sizeof(packet)) {
        context->udp.queue_dropped++;
        return;
    }

    udp_fill_header(
        context,
        &header,
        UDP_TYPE_CSI,
        rx_index,
        window_pos,
        window_seq,
        trigger_seq,
        present_mask,
        active_nodes,
        received_nodes,
        rssi,
        csi_len);

    memcpy(packet, &header, sizeof(header));
    memcpy(packet + sizeof(header), csi, csi_len);
    (void)udp_enqueue(&context->udp, packet, packet_bytes);
}

static void enqueue_pose_udp(
    live_context_t *context,
    uint64_t window_seq,
    uint32_t trigger_seq,
    uint8_t active_nodes,
    uint8_t received_nodes,
    const int8_t pose[POSE_CNN_OUTPUT_BYTES])
{
    uint8_t packet[sizeof(udp_wire_header_t) + POSE_CNN_OUTPUT_BYTES];
    udp_wire_header_t header;

    if (context == NULL || !context->udp.enabled) {
        return;
    }

    udp_fill_header(
        context,
        &header,
        UDP_TYPE_POSE,
        UDP_POSE_RX_ID,
        UDP_POSE_WINDOW_POS,
        window_seq,
        trigger_seq,
        0u,
        active_nodes,
        received_nodes,
        0,
        (uint16_t)POSE_CNN_OUTPUT_BYTES);

    memcpy(packet, &header, sizeof(header));
    memcpy(packet + sizeof(header), pose, POSE_CNN_OUTPUT_BYTES);
    (void)udp_enqueue(&context->udp, packet, sizeof(packet));
}

/* PS-only engine: the CNN runs on the ARM cores (pose_cnn_sw.c), no FPGA access. */
static int cnn_engine_open(cnn_engine_t *engine, const char *blob_path, unsigned threads)
{
    char err[160];

    memset(engine, 0, sizeof(*engine));
    engine->sw = pose_cnn_sw_create_from_file(blob_path, threads, err, sizeof(err));
    if (engine->sw == NULL) {
        fprintf(stderr, "SW CNN load failed: %s\n", err);
        return -1;
    }
    engine->output_scale = pose_cnn_sw_output_scale(engine->sw);
    engine->scale_bits = pose_cnn_sw_scale_bits(engine->sw);
    printf(
        "SW CNN LOAD PASS threads=%u output_scale=%.9g bits=0x%08" PRIx32 "\n",
        pose_cnn_sw_threads(engine->sw),
        (double)engine->output_scale,
        engine->scale_bits);
    return 0;
}

static void cnn_engine_close(cnn_engine_t *engine)
{
    pose_cnn_sw_destroy(engine->sw);
    memset(engine, 0, sizeof(*engine));
}

static int cnn_engine_infer(
    cnn_engine_t *engine,
    const int8_t *input,
    size_t input_bytes,
    int8_t output[POSE_CNN_OUTPUT_BYTES],
    pose_cnn_sw_timing_t *timing)
{
    if (input_bytes != POSE_CNN_INPUT_BYTES) {
        fprintf(stderr,
                "wrong live input size: got %zu expected %u\n",
                input_bytes,
                POSE_CNN_INPUT_BYTES);
        return -1;
    }
    if (pose_cnn_sw_infer(engine->sw, input, input_bytes, output, timing, NULL) != 0) {
        fprintf(stderr, "SW INFER failed\n");
        return -1;
    }
    return 0;
}

static int setup_tty(int descriptor)
{
    struct termios settings;
    if (tcgetattr(descriptor, &settings) != 0) {
        return -1;
    }
    cfmakeraw(&settings);
    cfsetispeed(&settings, B115200);
    cfsetospeed(&settings, B115200);
    settings.c_cflag |= CLOCAL | CREAD;
    settings.c_cflag &= ~CRTSCTS;
    settings.c_cc[VMIN] = 0;
    settings.c_cc[VTIME] = 0;
    return tcsetattr(descriptor, TCSANOW, &settings);
}

static int write_all(int descriptor, const char *text)
{
    size_t offset = 0u;
    size_t length = strlen(text);
    uint64_t deadline_ms = monotonic_ms() + SERIAL_WRITE_TIMEOUT_MS;

    while (offset < length) {
        ssize_t count = write(descriptor, text + offset, length - offset);
        if (count > 0) {
            offset += (size_t)count;
            continue;
        }
        if (count < 0 && errno != EAGAIN && errno != EWOULDBLOCK) {
            if (errno == EINTR) {
                continue;
            }
            return -1;
        }
        if (monotonic_ms() >= deadline_ms) {
            errno = ETIMEDOUT;
            return -1;
        }
        {
            struct pollfd write_poll = {descriptor, POLLOUT, 0};
            int poll_result = poll(&write_poll, 1u, POLL_INTERVAL_MS);
            if (poll_result < 0 && errno != EINTR) {
                return -1;
            }
            if (poll_result > 0 &&
                (write_poll.revents & (POLLERR | POLLHUP | POLLNVAL)) != 0) {
                errno = EIO;
                return -1;
            }
        }
    }
    return 0;
}

static int send_command(int descriptor, const char *command)
{
    char line[128];
    int length = snprintf(line, sizeof(line), "CMD %s\n", command);
    if (length <= 0 || (size_t)length >= sizeof(line)) {
        return -1;
    }
    printf("TX coordinator: %s\n", command);
    return write_all(descriptor, line);
}

static int start_coordinator(int descriptor)
{
    tcflush(descriptor, TCIOFLUSH);
    if (send_command(descriptor, "mode wait") != 0) {
        return -1;
    }
    usleep(200000);
    if (send_command(descriptor, "status") != 0) {
        return -1;
    }
    usleep(100000);
    return send_command(descriptor, "mode run");
}

static void print_control_updates(
    const csi_pipeline_stats_t *stats,
    uint64_t *last_status_frames,
    uint64_t *last_ack_frames)
{
    if (stats->status_frames != *last_status_frames) {
        printf(
            "STATUS mode=%s connected=%u active=%u saved=%u channel=%u "
            "generation=%u next_trigger=%u trigger_sent=%u "
            "cycle_timeouts=%u\n",
            stats->last_status_mode != 0u ? "run" : "wait",
            (unsigned)stats->last_status_connected_nodes,
            (unsigned)stats->last_status_active_nodes,
            (unsigned)stats->last_status_saved_nodes,
            (unsigned)stats->last_status_wifi_channel,
            stats->last_status_generation,
            stats->last_status_next_trigger,
            stats->last_status_trigger_sent,
            stats->last_status_cycle_timeouts);
        *last_status_frames = stats->status_frames;
    }
    if (stats->ack_frames != *last_ack_frames) {
        printf(
            "ACK ok=%u mode=%s message=%s\n",
            (unsigned)stats->last_ack_ok,
            stats->last_ack_mode != 0u ? "run" : "wait",
            stats->last_ack_message[0] != '\0' ?
                stats->last_ack_message : "(empty)");
        *last_ack_frames = stats->ack_frames;
    }
    fflush(stdout);
}

static void print_pose(
    uint64_t window,
    const int8_t pose[POSE_CNN_OUTPUT_BYTES],
    float output_scale)
{
    unsigned i;
    printf("POSE_INT8 window=%llu:", (unsigned long long)window);
    for (i = 0u; i < POSE_CNN_OUTPUT_BYTES; ++i) {
        printf(" %d", (int)pose[i]);
    }
    putchar('\n');
    printf("POSE_FLOAT window=%llu:", (unsigned long long)window);
    for (i = 0u; i < POSE_CNN_OUTPUT_BYTES; ++i) {
        printf(" %.6f", (double)((float)pose[i] * output_scale));
    }
    putchar('\n');
}

static int on_window(
    const int8_t *input,
    size_t input_bytes,
    uint64_t window_seq,
    uint32_t trigger_seq,
    void *user)
{
    live_context_t *context = (live_context_t *)user;
    csi_pipeline_stats_t stats = {0};
    int8_t pose[POSE_CNN_OUTPUT_BYTES];
    pose_cnn_sw_timing_t timing;
    uint64_t infer_us;
    uint64_t window = context->windows + 1u;

    csi_pipeline_get_stats(context->pipeline, &stats);
    if (context->dump != NULL &&
        fwrite(input, 1u, input_bytes, context->dump) != input_bytes) {
        fprintf(stderr, "window dump write failed\n");
        return -1;
    }
    if (cnn_engine_infer(
            context->engine,
            input,
            input_bytes,
            pose,
            &timing) != 0) {
        return -1;
    }
    infer_us = timing.total_ns / 1000u;
    context->infer_total_us += infer_us;
    if (context->windows == 0u || infer_us < context->infer_min_us) {
        context->infer_min_us = infer_us;
    }
    if (infer_us > context->infer_max_us) {
        context->infer_max_us = infer_us;
    }

    enqueue_pose_udp(
        context,
        window_seq,
        trigger_seq,
        stats.last_active_nodes,
        stats.last_received_nodes,
        pose);

    (void)wise_server_pose(context->tcp, (uint32_t)window_seq, trigger_seq,
        (uint32_t)infer_us, context->engine->output_scale, pose);
    context->windows = window;
    printf(
        "LIVE window=%llu trigger=%u shape=[%u,%u,%u] bytes=%zu "
        "active=%u received=%u infer_ms=%.3f encoder_ms=%.3f fc_ms=%.3f engine=PS\n",
        (unsigned long long)window,
        trigger_seq,
        (unsigned)CSI_INPUT_CHANNELS,
        (unsigned)CSI_SUBCARRIERS,
        (unsigned)CSI_WINDOW_SIZE,
        input_bytes,
        (unsigned)stats.last_active_nodes,
        (unsigned)stats.last_received_nodes,
        timing.total_ns / 1e6,
        timing.encoder_ns / 1e6,
        timing.fc_ns / 1e6);
    print_pose(window, pose, context->engine->output_scale);
    fflush(stdout);
    if (context->max_windows != 0u && window >= context->max_windows) {
        return 1;
    }
    return 0;
}

/** Parse a finite positive scale, rejecting trailing text and range errors. */
static int parse_input_scale(const char *text, float *value)
{
    char *end;
    errno = 0;
    *value = strtof(text, &end);
    return text != end && *end == '\0' && errno == 0 &&
           isfinite(*value) && *value > 0.0f ? 0 : -1;
}

/** Parse an unsigned decimal count; only explicit zero selects continuous mode. */
static int parse_window_count(const char *text, uint64_t *value)
{
    const char *p = text;
    char *end;
    unsigned long long parsed;
    if (*p == '\0') return -1;
    for (; *p != '\0'; ++p) {
        if (*p < '0' || *p > '9') return -1;
    }
    errno = 0;
    parsed = strtoull(text, &end, 10);
    if (errno != 0 || *end != '\0' || parsed > UINT64_MAX) return -1;
    *value = (uint64_t)parsed;
    return 0;
}

static void usage(const char *program)
{
    fprintf(stderr,
        "usage: %s TTY INPUT_SCALE [MAX_WINDOWS] [BLOB] [DUMP_BIN]\n"
        "example: %s /dev/ttyACM0 0.02 10\n"
        "UDP: CSI_UDP_TARGET=10.10.20.2:5000 %s /dev/ttyACM0 0.02 0\n"
        "SW threads: POSE_SW_THREADS=2 %s /dev/ttyACM0 0.02 0\n",
        program,
        program,
        program,
        program);
}

int main(int argc, char **argv)
{
    const char *tty_path;
    const char *blob_path = DEFAULT_BLOB_PATH;
    const char *dump_path = NULL;
    float input_scale;
    int descriptor = -1;
    unsigned sw_threads = 1u;
    const char *threads_env = getenv("POSE_SW_THREADS");
    uint8_t buffer[READ_CHUNK];
    live_context_t context = {0};
    csi_pipeline_t *pipeline = NULL;
    csi_pipeline_stats_t stats = {0};
    cnn_engine_t engine;
    uint64_t last_progress_ms;
    uint64_t last_cycles = 0u;
    uint64_t last_status_frames = 0u;
    uint64_t last_ack_frames = 0u;
    unsigned watchdog_restarts = 0u;
    int exit_code = EXIT_FAILURE;
    const char *udp_target = getenv("CSI_UDP_TARGET");

    memset(&engine, 0, sizeof(engine));
    context.udp.fd = -1;
    if (argc < 3 || argc > 6) {
        usage(argv[0]);
        return 2;
    }
    tty_path = argv[1];
    if (parse_input_scale(argv[2], &input_scale) != 0) {
        fprintf(stderr, "invalid INPUT_SCALE: %s\n", argv[2]);
        usage(argv[0]);
        return 2;
    }
    if (argc >= 4) {
        if (parse_window_count(argv[3], &context.max_windows) != 0) {
            fprintf(stderr, "invalid MAX_WINDOWS: %s (use 0 for continuous mode)\n", argv[3]);
            usage(argv[0]);
            return 2;
        }
    }
    if (argc >= 5) {
        blob_path = argv[4];
    }
    if (argc == 6) {
        dump_path = argv[5];
    }
    if (threads_env != NULL && *threads_env != '\0') {
        uint64_t parsed;
        if (parse_window_count(threads_env, &parsed) != 0 ||
            parsed < 1u || parsed > POSE_SW_MAX_THREADS) {
            fprintf(stderr, "invalid POSE_SW_THREADS: %s (1..%u)\n",
                    threads_env, POSE_SW_MAX_THREADS);
            return 2;
        }
        sw_threads = (unsigned)parsed;
    }

    printf("WiSensing RX5 live CSI to PS software CNN (no FPGA)\n");
    printf("blob=%s input_scale=%.9g\n", blob_path, (double)input_scale);
    if (strcmp(blob_path, DEFAULT_BLOB_PATH) == 0) {
        printf("NOTE: default blob is for integration testing; binary assets are supplied separately.\n");
    }
    if (cnn_engine_open(&engine, blob_path, sw_threads) != 0) {
        goto cleanup;
    }

    if (udp_sender_start(&context.udp, udp_target) != 0) {
        fprintf(stderr, "UDP bypass disabled after setup failure; CNN path continues\n");
    }
    if (!context.udp.enabled) {
        printf("UDP bypass OFF\n");
    }

    descriptor = open(tty_path, O_RDWR | O_NOCTTY | O_NONBLOCK);
    if (descriptor < 0) {
        fprintf(stderr, "cannot open %s: %s\n", tty_path, strerror(errno));
        goto cleanup;
    }
    if (setup_tty(descriptor) != 0) {
        fprintf(stderr, "cannot configure %s: %s\n", tty_path, strerror(errno));
        goto cleanup;
    }
    if (dump_path != NULL) {
        context.dump = fopen(dump_path, "wb");
        if (context.dump == NULL) {
            fprintf(stderr, "cannot open %s: %s\n", dump_path, strerror(errno));
            goto cleanup;
        }
    }
    pipeline = csi_pipeline_create(input_scale);
    if (pipeline == NULL) {
        fprintf(stderr, "cannot create CSI pipeline\n");
        goto cleanup;
    }
    context.pipeline = pipeline;
    context.engine = &engine;
    const char *bind_ip = getenv("WISE_TCP_BIND");
    context.tcp = wise_server_start(bind_ip ? bind_ip : "0.0.0.0", 5000, 5001);
    if (!context.tcp) { fprintf(stderr, "Cannot start TCP ports 5000/5001\n"); goto cleanup; }
    csi_pipeline_set_frame_callback(pipeline, on_usb_frame, &context);
    printf("WISE TCP listening CSI/STATUS :5000 and Pose :5001\n");
    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);
    printf(
        "Listening on %s: rx=%u channels=%u input_bytes=%u\n",
        tty_path,
        (unsigned)CSI_RX_COUNT,
        (unsigned)CSI_INPUT_CHANNELS,
        (unsigned)CSI_INPUT_BYTES);
    if (start_coordinator(descriptor) != 0) {
        fprintf(stderr,
                "cannot start coordinator stream: %s\n",
                strerror(errno));
        goto cleanup;
    }
    last_progress_ms = monotonic_ms();
    uint64_t last_status_request_ms = last_progress_ms;

    while (!stop_requested) {
        struct pollfd serial_poll = {descriptor, POLLIN, 0};
        int poll_result = poll(&serial_poll, 1u, POLL_INTERVAL_MS);
        ssize_t count;
        int result;
        uint64_t now_ms;

        if (poll_result < 0) {
            if (errno == EINTR) {
                continue;
            }
            fprintf(stderr, "serial poll failed: %s\n", strerror(errno));
            goto cleanup;
        }
        if (stop_requested) {
            break;
        }
        if (monotonic_ms() - last_status_request_ms >= 3000u) {
            if (send_command(descriptor, "status") != 0) goto cleanup;
            last_status_request_ms = monotonic_ms();
        }
        if (poll_result == 0) {
            csi_pipeline_get_stats(pipeline, &stats);
            now_ms = monotonic_ms();
            if (stats.cycles_emitted != last_cycles) {
                last_cycles = stats.cycles_emitted;
                last_progress_ms = now_ms;
            } else if (now_ms - last_progress_ms >= STREAM_STALL_MS) {
                watchdog_restarts++;
                fprintf(stderr,
                    "WATCHDOG no complete cycle for %u ms; resync #%u "
                    "bytes=%llu valid=%llu connected=%u active=%u\n",
                    (unsigned)STREAM_STALL_MS,
                    watchdog_restarts,
                    (unsigned long long)stats.bytes_received,
                    (unsigned long long)stats.valid_frames,
                    (unsigned)stats.last_status_connected_nodes,
                    (unsigned)stats.last_status_active_nodes);
                csi_pipeline_resync(pipeline);
                if (start_coordinator(descriptor) != 0) {
                    fprintf(stderr,
                            "watchdog restart failed: %s\n",
                            strerror(errno));
                    goto cleanup;
                }
                last_progress_ms = monotonic_ms();
            }
            continue;
        }
        if ((serial_poll.revents & (POLLERR | POLLHUP | POLLNVAL)) != 0) {
            fprintf(stderr,
                    "serial device disconnected (revents=0x%x)\n",
                    serial_poll.revents);
            goto cleanup;
        }
        if ((serial_poll.revents & POLLIN) == 0) {
            continue;
        }
        count = read(descriptor, buffer, sizeof(buffer));
        if (count < 0) {
            if (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK) {
                continue;
            }
            fprintf(stderr, "serial read failed: %s\n", strerror(errno));
            goto cleanup;
        }
        if (count == 0) {
            continue;
        }
        result = csi_pipeline_feed(
            pipeline,
            buffer,
            (size_t)count,
            on_window,
            on_csi_record_udp,
            &context);
        if (result < 0) {
            fprintf(stderr, "CSI pipeline or CNN inference failed\n");
            goto cleanup;
        }
        if (result > 0) {
            break;
        }
        csi_pipeline_get_stats(pipeline, &stats);
        print_control_updates(
            &stats,
            &last_status_frames,
            &last_ack_frames);
        if (stats.cycles_emitted != last_cycles) {
            last_cycles = stats.cycles_emitted;
            last_progress_ms = monotonic_ms();
        } else {
            now_ms = monotonic_ms();
            if (now_ms - last_progress_ms >= STREAM_STALL_MS) {
                watchdog_restarts++;
                fprintf(stderr,
                    "WATCHDOG data received but no complete cycle for %u ms; "
                    "resync #%u bytes=%llu valid=%llu connected=%u active=%u\n",
                    (unsigned)STREAM_STALL_MS,
                    watchdog_restarts,
                    (unsigned long long)stats.bytes_received,
                    (unsigned long long)stats.valid_frames,
                    (unsigned)stats.last_status_connected_nodes,
                    (unsigned)stats.last_status_active_nodes);
                csi_pipeline_resync(pipeline);
                if (start_coordinator(descriptor) != 0) {
                    fprintf(stderr,
                            "watchdog restart failed: %s\n",
                            strerror(errno));
                    goto cleanup;
                }
                last_progress_ms = monotonic_ms();
            }
        }
    }
    exit_code = EXIT_SUCCESS;

cleanup:
    if (descriptor >= 0) {
        (void)send_command(descriptor, "mode wait");
    }
    csi_pipeline_get_stats(pipeline, &stats);
    fprintf(stderr,
        "LIVE STATS bytes=%llu valid_frames=%llu cycles=%llu windows=%llu "
        "inferences=%llu checksum_errors=%llu malformed=%llu "
        "watchdog_restarts=%u\n",
        (unsigned long long)stats.bytes_received,
        (unsigned long long)stats.valid_frames,
        (unsigned long long)stats.cycles_emitted,
        (unsigned long long)stats.windows_emitted,
        (unsigned long long)context.windows,
        (unsigned long long)stats.checksum_errors,
        (unsigned long long)stats.malformed_frames,
        watchdog_restarts);
    if (context.windows != 0u) {
        fprintf(stderr,
            "PS INFER STATS windows=%llu avg_ms=%.3f min_ms=%.3f max_ms=%.3f threads=%u\n",
            (unsigned long long)context.windows,
            (double)context.infer_total_us / (double)context.windows / 1000.0,
            (double)context.infer_min_us / 1000.0,
            (double)context.infer_max_us / 1000.0,
            sw_threads);
    }
    if (pipeline != NULL) {
        unsigned node;
        fprintf(stderr,
                "LAST active=%u received=%u\n",
                (unsigned)stats.last_active_nodes,
                (unsigned)stats.last_received_nodes);
        for (node = 0u; node < CSI_RX_COUNT; ++node) {
            fprintf(stderr,
                    "RX%u present=%llu missing=%llu\n",
                    node,
                    (unsigned long long)stats.rx_present[node],
                    (unsigned long long)stats.rx_missing[node]);
        }
    }

    wise_server_stop(context.tcp);
    udp_sender_stop(&context.udp);
    fprintf(stderr,
        "UDP STATS enqueued=%llu queue_dropped=%llu sent=%llu "
        "send_errors=%llu eagain=%llu enobufs=%llu bytes=%llu\n",
        (unsigned long long)context.udp.enqueued,
        (unsigned long long)context.udp.queue_dropped,
        (unsigned long long)context.udp.sent,
        (unsigned long long)context.udp.send_errors,
        (unsigned long long)context.udp.eagain,
        (unsigned long long)context.udp.enobufs,
        (unsigned long long)context.udp.bytes_sent);

    csi_pipeline_destroy(pipeline);
    if (context.dump != NULL) {
        fclose(context.dump);
    }
    if (descriptor >= 0) {
        close(descriptor);
    }
    cnn_engine_close(&engine);
    return exit_code;
}
