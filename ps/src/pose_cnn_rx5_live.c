#define _DEFAULT_SOURCE
#define _POSIX_C_SOURCE 200809L

#include "csi_pipeline.h"
#include "pose_cnn_regs.h"
#include "pose_cnn_lock.h"

#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <math.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

#define CSR_MAP_BYTES              0x00010000u
#define DDR_RESERVED_BASE          0x3F000000u
#define DDR_RESERVED_BYTES         0x01000000u
#define WEIGHT_PHYS                0x3F000000u
#define INPUT_PHYS                 0x3F100000u
#define OUTPUT_PHYS                0x3F200000u

#define DEFAULT_BLOB_PATH          "/usr/share/pose-cnn-rx5/blob_rx5_test.bin"
#define READ_CHUNK                 16384u
#define POLL_INTERVAL_MS           250
#define STREAM_STALL_MS            5000u
#define SERIAL_WRITE_TIMEOUT_MS    1000u
#define LOAD_TIMEOUT_MS            1000L
#define INFER_TIMEOUT_MS           1000L

typedef struct {
    void *mapping;
    size_t mapping_bytes;
    volatile uint8_t *ptr;
} phys_mapping_t;

typedef struct {
    int mem_fd;
    phys_mapping_t csr_map;
    phys_mapping_t weight_map;
    phys_mapping_t input_map;
    phys_mapping_t output_map;
    volatile uint32_t *csr;
    float output_scale;
    uint32_t scale_bits;
} cnn_engine_t;

typedef struct {
    FILE *dump;
    uint64_t windows;
    uint64_t max_windows;
    csi_pipeline_t *pipeline;
    cnn_engine_t *engine;
} live_context_t;

static volatile sig_atomic_t stop_requested = 0;

static void barrier(void)
{
    __sync_synchronize();
}

static uint64_t monotonic_ms(void)
{
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) {
        return 0u;
    }
    return (uint64_t)now.tv_sec * 1000u + (uint64_t)now.tv_nsec / 1000000u;
}

static long elapsed_ms(const struct timespec *start, const struct timespec *now)
{
    return (now->tv_sec - start->tv_sec) * 1000L +
           (now->tv_nsec - start->tv_nsec) / 1000000L;
}

static void on_signal(int signal_number)
{
    (void)signal_number;
    stop_requested = 1;
}

static uint32_t reg_read(volatile uint32_t *csr, unsigned offset)
{
    uint32_t value = csr[offset / 4u];
    barrier();
    return value;
}

static void reg_write(
    volatile uint32_t *csr,
    unsigned offset,
    uint32_t value)
{
    barrier();
    csr[offset / 4u] = value;
    barrier();
}

static int map_physical(
    int fd,
    uint32_t phys,
    size_t bytes,
    phys_mapping_t *out)
{
    long page_size = sysconf(_SC_PAGESIZE);
    uint32_t page_mask;
    uint32_t page_base;
    size_t page_offset;
    size_t map_bytes;
    void *mapping;

    if (page_size <= 0 ||
        ((unsigned long)page_size & ((unsigned long)page_size - 1ul)) != 0ul) {
        fprintf(stderr, "invalid page size: %ld\n", page_size);
        return -1;
    }
    page_mask = (uint32_t)page_size - 1u;
    page_base = phys & ~page_mask;
    page_offset = (size_t)(phys - page_base);
    map_bytes = page_offset + bytes;
    map_bytes = (map_bytes + (size_t)page_size - 1u) &
                ~((size_t)page_size - 1u);
    mapping = mmap(
        NULL,
        map_bytes,
        PROT_READ | PROT_WRITE,
        MAP_SHARED,
        fd,
        (off_t)page_base);
    if (mapping == MAP_FAILED) {
        fprintf(stderr,
                "mmap phys=0x%08" PRIx32 " bytes=%zu: %s\n",
                phys,
                bytes,
                strerror(errno));
        return -1;
    }
    out->mapping = mapping;
    out->mapping_bytes = map_bytes;
    out->ptr = (volatile uint8_t *)mapping + page_offset;
    return 0;
}

static void unmap_physical(phys_mapping_t *mapping)
{
    if (mapping->mapping != NULL && mapping->mapping != MAP_FAILED) {
        munmap(mapping->mapping, mapping->mapping_bytes);
    }
    memset(mapping, 0, sizeof(*mapping));
}

static int load_exact_file(
    const char *path,
    uint8_t *buffer,
    size_t expected_bytes)
{
    FILE *file = fopen(path, "rb");
    long length;
    size_t received;

    if (file == NULL) {
        fprintf(stderr, "open %s: %s\n", path, strerror(errno));
        return -1;
    }
    if (fseek(file, 0, SEEK_END) != 0 ||
        (length = ftell(file)) < 0 ||
        fseek(file, 0, SEEK_SET) != 0) {
        fprintf(stderr, "size %s: %s\n", path, strerror(errno));
        fclose(file);
        return -1;
    }
    if ((size_t)length != expected_bytes) {
        fprintf(stderr,
                "wrong size %s: got %ld expected %zu\n",
                path,
                length,
                expected_bytes);
        fclose(file);
        return -1;
    }
    received = fread(buffer, 1u, expected_bytes, file);
    if (received != expected_bytes || ferror(file)) {
        fprintf(stderr,
                "read %s: got %zu expected %zu\n",
                path,
                received,
                expected_bytes);
        fclose(file);
        return -1;
    }
    fclose(file);
    return 0;
}

static int validate_blob_header(const uint8_t *blob)
{
    uint32_t words[3];
    memcpy(words, blob, sizeof(words));
    if (words[0] != POSE_CNN_BLOB_MAGIC ||
        words[1] != POSE_CNN_BLOB_VERSION ||
        words[2] != POSE_CNN_BLOB_WORDS) {
        fprintf(stderr,
                "bad blob header: magic=0x%08" PRIx32
                " version=%" PRIu32 " words=%" PRIu32 "\n",
                words[0],
                words[1],
                words[2]);
        return -1;
    }
    return 0;
}

static int wait_complete(
    volatile uint32_t *csr,
    const char *operation,
    long timeout_ms,
    uint32_t *status_out,
    long *elapsed_out)
{
    struct timespec start;
    struct timespec now;
    const struct timespec delay = {0, 100000L};

    clock_gettime(CLOCK_MONOTONIC, &start);
    for (;;) {
        uint32_t status = reg_read(csr, POSE_CNN_STATUS);
        if ((status & POSE_CNN_ST_BUSY) == 0u &&
            (status & (POSE_CNN_ST_DONE | POSE_CNN_ST_ERROR)) != 0u) {
            clock_gettime(CLOCK_MONOTONIC, &now);
            *status_out = status;
            *elapsed_out = elapsed_ms(&start, &now);
            return 0;
        }
        clock_gettime(CLOCK_MONOTONIC, &now);
        if (elapsed_ms(&start, &now) >= timeout_ms) {
            fprintf(stderr,
                    "%s timeout: status=0x%08" PRIx32 "\n",
                    operation,
                    status);
            return -1;
        }
        nanosleep(&delay, NULL);
    }
}

static int start_and_wait(
    volatile uint32_t *csr,
    uint32_t command,
    const char *operation,
    long timeout_ms,
    uint32_t *status_out,
    long *elapsed_out)
{
    reg_write(csr, POSE_CNN_CONTROL, POSE_CNN_CTRL_CLEAR);
    reg_write(csr, POSE_CNN_CMD, command);
    reg_write(csr, POSE_CNN_CONTROL, POSE_CNN_CTRL_START);
    return wait_complete(
        csr,
        operation,
        timeout_ms,
        status_out,
        elapsed_out);
}

static int validate_status(
    const char *operation,
    uint32_t status,
    int require_cfg)
{
    if ((status & POSE_CNN_ST_ERROR) != 0u) {
        fprintf(stderr,
                "%s failed: status=0x%08" PRIx32
                " error_code=%" PRIu32 "\n",
                operation,
                status,
                POSE_CNN_ST_ERR_CODE(status));
        return -1;
    }
    if ((status & POSE_CNN_ST_DONE) == 0u ||
        (status & POSE_CNN_ST_BUSY) != 0u ||
        (require_cfg && (status & POSE_CNN_ST_CFG_OK) == 0u)) {
        fprintf(stderr,
                "%s unexpected status=0x%08" PRIx32 "\n",
                operation,
                status);
        return -1;
    }
    return 0;
}

static int cnn_engine_open(cnn_engine_t *engine, const char *blob_path)
{
    uint8_t *blob = NULL;
    uint32_t status;
    long load_ms;

    memset(engine, 0, sizeof(*engine));
    engine->mem_fd = -1;
    if (WEIGHT_PHYS < DDR_RESERVED_BASE ||
        OUTPUT_PHYS + POSE_CNN_OUTPUT_BYTES >
            DDR_RESERVED_BASE + DDR_RESERVED_BYTES) {
        fprintf(stderr, "CNN DDR layout exceeds reserved memory\n");
        return -1;
    }
    blob = (uint8_t *)malloc(POSE_CNN_BLOB_BYTES);
    if (blob == NULL) {
        fprintf(stderr, "weight blob allocation failed\n");
        return -1;
    }
    if (load_exact_file(blob_path, blob, POSE_CNN_BLOB_BYTES) != 0 ||
        validate_blob_header(blob) != 0) {
        free(blob);
        return -1;
    }
    engine->mem_fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (engine->mem_fd < 0) {
        fprintf(stderr, "open /dev/mem: %s\n", strerror(errno));
        free(blob);
        return -1;
    }
    if (map_physical(
            engine->mem_fd,
            POSE_CNN_BASEADDR,
            CSR_MAP_BYTES,
            &engine->csr_map) != 0 ||
        map_physical(
            engine->mem_fd,
            WEIGHT_PHYS,
            POSE_CNN_BLOB_BYTES,
            &engine->weight_map) != 0 ||
        map_physical(
            engine->mem_fd,
            INPUT_PHYS,
            POSE_CNN_INPUT_BYTES,
            &engine->input_map) != 0 ||
        map_physical(
            engine->mem_fd,
            OUTPUT_PHYS,
            POSE_CNN_OUTPUT_BYTES,
            &engine->output_map) != 0) {
        free(blob);
        return -1;
    }
    engine->csr = (volatile uint32_t *)engine->csr_map.ptr;
    status = reg_read(engine->csr, POSE_CNN_STATUS);
    if ((status & POSE_CNN_ST_BUSY) != 0u) {
        fprintf(stderr,
                "CNN is busy before LOAD: status=0x%08" PRIx32 "\n",
                status);
        free(blob);
        return -1;
    }
    reg_write(engine->csr, POSE_CNN_WEIGHT_ADDR, WEIGHT_PHYS);
    reg_write(engine->csr, POSE_CNN_INPUT_ADDR, INPUT_PHYS);
    reg_write(engine->csr, POSE_CNN_OUTPUT_ADDR, OUTPUT_PHYS);
    if (reg_read(engine->csr, POSE_CNN_WEIGHT_ADDR) != WEIGHT_PHYS ||
        reg_read(engine->csr, POSE_CNN_INPUT_ADDR) != INPUT_PHYS ||
        reg_read(engine->csr, POSE_CNN_OUTPUT_ADDR) != OUTPUT_PHYS) {
        fprintf(stderr, "CNN address register readback failed\n");
        free(blob);
        return -1;
    }
    memcpy((void *)engine->weight_map.ptr, blob, POSE_CNN_BLOB_BYTES);
    barrier();
    free(blob);
    if (start_and_wait(
            engine->csr,
            POSE_CNN_CMD_LOAD,
            "LOAD",
            LOAD_TIMEOUT_MS,
            &status,
            &load_ms) != 0 ||
        validate_status("LOAD", status, 1) != 0) {
        return -1;
    }
    engine->scale_bits = reg_read(engine->csr, POSE_CNN_SCALE);
    memcpy(&engine->output_scale,
           &engine->scale_bits,
           sizeof(engine->output_scale));
    if (!isfinite(engine->output_scale) || engine->output_scale <= 0.0f) {
        fprintf(stderr,
                "invalid output scale: bits=0x%08" PRIx32 "\n",
                engine->scale_bits);
        return -1;
    }
    printf(
        "CNN LOAD PASS status=0x%08" PRIx32
        " load_ms=%ld output_scale=%.9g bits=0x%08" PRIx32 "\n",
        status,
        load_ms,
        (double)engine->output_scale,
        engine->scale_bits);
    return 0;
}

static void cnn_engine_close(cnn_engine_t *engine)
{
    unmap_physical(&engine->output_map);
    unmap_physical(&engine->input_map);
    unmap_physical(&engine->weight_map);
    unmap_physical(&engine->csr_map);
    if (engine->mem_fd >= 0) {
        close(engine->mem_fd);
    }
    memset(engine, 0, sizeof(*engine));
    engine->mem_fd = -1;
}

static int cnn_engine_infer(
    cnn_engine_t *engine,
    const int8_t *input,
    size_t input_bytes,
    int8_t output[POSE_CNN_OUTPUT_BYTES],
    uint32_t *status_out,
    long *infer_ms)
{
    if (input_bytes != POSE_CNN_INPUT_BYTES) {
        fprintf(stderr,
                "wrong live input size: got %zu expected %u\n",
                input_bytes,
                POSE_CNN_INPUT_BYTES);
        return -1;
    }
    memcpy((void *)engine->input_map.ptr, input, input_bytes);
    memset((void *)engine->output_map.ptr, 0, POSE_CNN_OUTPUT_BYTES);
    barrier();
    if (start_and_wait(
            engine->csr,
            POSE_CNN_CMD_INFER,
            "INFER",
            INFER_TIMEOUT_MS,
            status_out,
            infer_ms) != 0 ||
        validate_status("INFER", *status_out, 1) != 0) {
        return -1;
    }
    barrier();
    memcpy(output, (const void *)engine->output_map.ptr, POSE_CNN_OUTPUT_BYTES);
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
    uint32_t trigger_seq,
    void *user)
{
    live_context_t *context = (live_context_t *)user;
    csi_pipeline_stats_t stats = {0};
    int8_t pose[POSE_CNN_OUTPUT_BYTES];
    uint32_t status;
    long infer_ms;
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
            &status,
            &infer_ms) != 0) {
        return -1;
    }
    context->windows = window;
    printf(
        "LIVE window=%llu trigger=%u shape=[%u,%u,%u] bytes=%zu "
        "active=%u received=%u infer_ms=%ld status=0x%08" PRIx32 "\n",
        (unsigned long long)window,
        trigger_seq,
        (unsigned)CSI_INPUT_CHANNELS,
        (unsigned)CSI_SUBCARRIERS,
        (unsigned)CSI_WINDOW_SIZE,
        input_bytes,
        (unsigned)stats.last_active_nodes,
        (unsigned)stats.last_received_nodes,
        infer_ms,
        status);
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
        "example: %s /dev/ttyACM0 0.02 10\n",
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
    int lock_fd = -1;
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

    memset(&engine, 0, sizeof(engine));
    engine.mem_fd = -1;
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

    printf("WiSensing RX5 live CSI to FPGA CNN\n");
    printf(
        "CSR=0x%08x weight=0x%08x input=0x%08x output=0x%08x\n",
        POSE_CNN_BASEADDR,
        WEIGHT_PHYS,
        INPUT_PHYS,
        OUTPUT_PHYS);
    printf("blob=%s input_scale=%.9g\n", blob_path, (double)input_scale);
    if (strcmp(blob_path, DEFAULT_BLOB_PATH) == 0) {
        printf("NOTE: bundled blob is for integration testing, not the final trained model.\n");
    }
    lock_fd = pose_cnn_lock_acquire();
    if (lock_fd < 0) goto cleanup;
    if (cnn_engine_open(&engine, blob_path) != 0) {
        goto cleanup;
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
    csi_pipeline_destroy(pipeline);
    if (context.dump != NULL) {
        fclose(context.dump);
    }
    if (descriptor >= 0) {
        close(descriptor);
    }
    cnn_engine_close(&engine);
    if (lock_fd >= 0) close(lock_fd);
    return exit_code;
}
