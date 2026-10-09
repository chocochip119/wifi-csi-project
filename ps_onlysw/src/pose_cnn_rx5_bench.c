/*
 * PS(software) vs PL(FPGA) inference speed and bit-exactness benchmark.
 *
 * Feeds the same INT8 windows to the ARM software CNN (pose_cnn_sw.c) and,
 * with --pl, to the pose_cnn IP through /dev/mem, then prints latency
 * statistics and byte-exact comparison results.
 *
 * INPUT_BIN may hold several windows (N x 19200 bytes), e.g. the DUMP_BIN
 * written by pose_cnn_rx5_live / pose_cnn_rx5_live_sw.
 *
 * Build without PL support (host PC test): -DPOSE_BENCH_NO_PL
 */
#define _DEFAULT_SOURCE
#define _POSIX_C_SOURCE 200809L

#include "pose_cnn_sw.h"

#include <errno.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#ifndef POSE_BENCH_NO_PL
#include "pose_cnn_regs.h"
#include "pose_cnn_lock.h"
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>

#define CSR_MAP_BYTES       0x00010000u
#define WEIGHT_PHYS         0x3F000000u
#define INPUT_PHYS          0x3F100000u
#define OUTPUT_PHYS         0x3F200000u
#define PL_TIMEOUT_NS       1000000000ull
#endif

#define DEFAULT_ITERATIONS  100u
#define WARMUP_ITERATIONS   3u

typedef struct {
    double *ms;
    unsigned count;
} samples_t;

static int cmp_double(const void *a, const void *b)
{
    double x = *(const double *)a, y = *(const double *)b;
    return (x > y) - (x < y);
}

/* Prints min/avg/p50/p95/max and returns the average. */
static double print_stats(const char *name, samples_t *s)
{
    double sum = 0.0, avg;
    unsigned i;
    if (s->count == 0u) return 0.0;
    for (i = 0u; i < s->count; ++i) sum += s->ms[i];
    avg = sum / s->count;
    qsort(s->ms, s->count, sizeof(double), cmp_double);
    printf("  %-22s min %9.3f  avg %9.3f  p50 %9.3f  p95 %9.3f  max %9.3f ms\n",
           name, s->ms[0], avg, s->ms[s->count / 2u],
           s->ms[(s->count * 95u) / 100u < s->count ? (s->count * 95u) / 100u : s->count - 1u],
           s->ms[s->count - 1u]);
    return avg;
}

static uint8_t *read_file(const char *path, size_t *bytes)
{
    FILE *f = fopen(path, "rb");
    uint8_t *buf;
    long len;
    if (f == NULL) {
        fprintf(stderr, "open %s: %s\n", path, strerror(errno));
        return NULL;
    }
    if (fseek(f, 0, SEEK_END) != 0 || (len = ftell(f)) < 0 || fseek(f, 0, SEEK_SET) != 0) {
        fprintf(stderr, "size %s failed\n", path);
        fclose(f);
        return NULL;
    }
    buf = (uint8_t *)malloc(len > 0 ? (size_t)len : 1u);
    if (buf == NULL || fread(buf, 1u, (size_t)len, f) != (size_t)len) {
        fprintf(stderr, "read %s failed\n", path);
        free(buf);
        fclose(f);
        return NULL;
    }
    fclose(f);
    *bytes = (size_t)len;
    return buf;
}

static void print_pose(const char *tag, const int8_t *p)
{
    unsigned i;
    printf("%s", tag);
    for (i = 0u; i < POSE_SW_OUTPUT_BYTES; ++i) printf(" %d", p[i]);
    putchar('\n');
}

static unsigned count_diff(const int8_t *a, const int8_t *b)
{
    unsigned i, n = 0u;
    for (i = 0u; i < POSE_SW_OUTPUT_BYTES; ++i) n += a[i] != b[i];
    return n;
}

/* ------------------------------------------------------------------ PL */
#ifndef POSE_BENCH_NO_PL
typedef struct {
    void *mapping;
    size_t mapping_bytes;
    volatile uint8_t *ptr;
} phys_mapping_t;

typedef struct {
    int mem_fd;
    phys_mapping_t csr_map, weight_map, input_map, output_map;
    volatile uint32_t *csr;
} pl_engine_t;

static void barrier(void) { __sync_synchronize(); }

static uint64_t now_ns(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

static uint32_t reg_read(volatile uint32_t *csr, unsigned offset)
{
    uint32_t value = csr[offset / 4u];
    barrier();
    return value;
}

static void reg_write(volatile uint32_t *csr, unsigned offset, uint32_t value)
{
    barrier();
    csr[offset / 4u] = value;
    barrier();
}

static int map_physical(int fd, uint32_t phys, size_t bytes, phys_mapping_t *out)
{
    long page_size = sysconf(_SC_PAGESIZE);
    uint32_t page_base = phys & ~((uint32_t)page_size - 1u);
    size_t page_offset = (size_t)(phys - page_base);
    size_t map_bytes = (page_offset + bytes + (size_t)page_size - 1u) & ~((size_t)page_size - 1u);
    void *mapping = mmap(NULL, map_bytes, PROT_READ | PROT_WRITE, MAP_SHARED, fd, (off_t)page_base);
    if (mapping == MAP_FAILED) {
        fprintf(stderr, "mmap phys=0x%08" PRIx32 ": %s\n", phys, strerror(errno));
        return -1;
    }
    out->mapping = mapping;
    out->mapping_bytes = map_bytes;
    out->ptr = (volatile uint8_t *)mapping + page_offset;
    return 0;
}

static void unmap_physical(phys_mapping_t *m)
{
    if (m->mapping != NULL && m->mapping != MAP_FAILED) munmap(m->mapping, m->mapping_bytes);
    memset(m, 0, sizeof(*m));
}

/* Busy-polls STATUS (no sleep) so the measured time is the IP latency. */
static int pl_run(pl_engine_t *pl, uint32_t cmd, uint32_t *status_out, uint64_t *hw_ns)
{
    uint64_t t0, t;
    uint32_t status;
    reg_write(pl->csr, POSE_CNN_CONTROL, POSE_CNN_CTRL_CLEAR);
    reg_write(pl->csr, POSE_CNN_CMD, cmd);
    t0 = now_ns();
    reg_write(pl->csr, POSE_CNN_CONTROL, POSE_CNN_CTRL_START);
    for (;;) {
        status = reg_read(pl->csr, POSE_CNN_STATUS);
        t = now_ns();
        if ((status & POSE_CNN_ST_BUSY) == 0u &&
            (status & (POSE_CNN_ST_DONE | POSE_CNN_ST_ERROR)) != 0u) break;
        if (t - t0 > PL_TIMEOUT_NS) {
            fprintf(stderr, "PL %s timeout status=0x%08" PRIx32 "\n",
                    cmd == POSE_CNN_CMD_LOAD ? "LOAD" : "INFER", status);
            return -1;
        }
    }
    *status_out = status;
    *hw_ns = t - t0;
    if ((status & POSE_CNN_ST_ERROR) != 0u || (status & POSE_CNN_ST_CFG_OK) == 0u) {
        fprintf(stderr, "PL %s failed status=0x%08" PRIx32 " err=%" PRIu32 "\n",
                cmd == POSE_CNN_CMD_LOAD ? "LOAD" : "INFER", status, POSE_CNN_ST_ERR_CODE(status));
        return -1;
    }
    return 0;
}

static void pl_close(pl_engine_t *pl)
{
    unmap_physical(&pl->output_map);
    unmap_physical(&pl->input_map);
    unmap_physical(&pl->weight_map);
    unmap_physical(&pl->csr_map);
    if (pl->mem_fd >= 0) close(pl->mem_fd);
    pl->mem_fd = -1;
}

static int pl_open(pl_engine_t *pl, const uint8_t *blob, uint32_t sw_scale_bits)
{
    uint32_t status, scale_bits;
    uint64_t load_ns;

    memset(pl, 0, sizeof(*pl));
    pl->mem_fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (pl->mem_fd < 0) {
        fprintf(stderr, "open /dev/mem: %s (root required)\n", strerror(errno));
        return -1;
    }
    if (map_physical(pl->mem_fd, POSE_CNN_BASEADDR, CSR_MAP_BYTES, &pl->csr_map) ||
        map_physical(pl->mem_fd, WEIGHT_PHYS, POSE_CNN_BLOB_BYTES, &pl->weight_map) ||
        map_physical(pl->mem_fd, INPUT_PHYS, POSE_CNN_INPUT_BYTES, &pl->input_map) ||
        map_physical(pl->mem_fd, OUTPUT_PHYS, POSE_CNN_OUTPUT_BYTES, &pl->output_map)) {
        pl_close(pl);
        return -1;
    }
    pl->csr = (volatile uint32_t *)pl->csr_map.ptr;
    if ((reg_read(pl->csr, POSE_CNN_STATUS) & POSE_CNN_ST_BUSY) != 0u) {
        fprintf(stderr, "PL busy before LOAD\n");
        pl_close(pl);
        return -1;
    }
    reg_write(pl->csr, POSE_CNN_WEIGHT_ADDR, WEIGHT_PHYS);
    reg_write(pl->csr, POSE_CNN_INPUT_ADDR, INPUT_PHYS);
    reg_write(pl->csr, POSE_CNN_OUTPUT_ADDR, OUTPUT_PHYS);
    memcpy((void *)pl->weight_map.ptr, blob, POSE_CNN_BLOB_BYTES);
    barrier();
    if (pl_run(pl, POSE_CNN_CMD_LOAD, &status, &load_ns) != 0) {
        pl_close(pl);
        return -1;
    }
    scale_bits = reg_read(pl->csr, POSE_CNN_SCALE);
    printf("PL  LOAD PASS status=0x%08" PRIx32 " load=%.3f ms scale_bits=0x%08" PRIx32 "%s\n",
           status, load_ns / 1e6, scale_bits,
           scale_bits == sw_scale_bits ? " (== SW)" : " (!= SW scale)");
    return 0;
}

/* e2e = input copy + START..DONE + output copy, i.e. what the live app pays. */
static int pl_infer(pl_engine_t *pl, const int8_t *input, int8_t *out,
                    uint64_t *hw_ns, uint64_t *e2e_ns)
{
    uint32_t status;
    uint64_t t0 = now_ns();
    memcpy((void *)pl->input_map.ptr, input, POSE_CNN_INPUT_BYTES);
    memset((void *)pl->output_map.ptr, 0, POSE_CNN_OUTPUT_BYTES);
    barrier();
    if (pl_run(pl, POSE_CNN_CMD_INFER, &status, hw_ns) != 0) return -1;
    barrier();
    memcpy(out, (const void *)pl->output_map.ptr, POSE_CNN_OUTPUT_BYTES);
    *e2e_ns = now_ns() - t0;
    return 0;
}
#endif

/* ---------------------------------------------------------------- main */

static void usage(const char *prog)
{
    fprintf(stderr,
        "usage: %s BLOB INPUT_BIN [-n ITER] [-t THREADS] [-e EXPECTED_BIN] [--pl]\n"
        "  BLOB          weights_5rx.bin (685136 bytes)\n"
        "  INPUT_BIN     N x 19200-byte INT8 windows (live DUMP_BIN works)\n"
        "  -n ITER       timed iterations per engine (default %u)\n"
        "  -t THREADS    SW threads 1..%u (default 1; Zynq-7020 has 2 cores)\n"
        "  -e EXPECTED   24-byte expected pose for the first window\n"
        "  --pl          also run the FPGA IP via /dev/mem (root, bitstream loaded)\n",
        prog, DEFAULT_ITERATIONS, POSE_SW_MAX_THREADS);
}

int main(int argc, char **argv)
{
    const char *blob_path, *input_path, *expected_path = NULL;
    unsigned iterations = DEFAULT_ITERATIONS, threads = 1u, windows, i;
    int use_pl = 0, argi, exit_code = 1, all_match = 1;
    uint8_t *blob = NULL, *inputs = NULL, *expected = NULL;
    size_t blob_bytes = 0u, input_bytes = 0u, expected_bytes = 0u;
    pose_cnn_sw_t *sw = NULL;
    int8_t *sw_out = NULL;
    samples_t sw_total = {0}, sw_enc = {0}, sw_fc = {0};
    double sw_avg;
    char err[160];
#ifndef POSE_BENCH_NO_PL
    pl_engine_t pl;
    int lock_fd = -1, pl_open_ok = 0;
    samples_t pl_hw = {0}, pl_e2e = {0};
    unsigned pl_mismatch_windows = 0u;
    pl.mem_fd = -1;
#endif

    if (argc < 3) {
        usage(argv[0]);
        return 2;
    }
    blob_path = argv[1];
    input_path = argv[2];
    for (argi = 3; argi < argc; ++argi) {
        if (strcmp(argv[argi], "-n") == 0 && argi + 1 < argc) {
            iterations = (unsigned)strtoul(argv[++argi], NULL, 10);
        } else if (strcmp(argv[argi], "-t") == 0 && argi + 1 < argc) {
            threads = (unsigned)strtoul(argv[++argi], NULL, 10);
        } else if (strcmp(argv[argi], "-e") == 0 && argi + 1 < argc) {
            expected_path = argv[++argi];
        } else if (strcmp(argv[argi], "--pl") == 0) {
            use_pl = 1;
        } else {
            usage(argv[0]);
            return 2;
        }
    }
    if (iterations == 0u) {
        fprintf(stderr, "ITER must be > 0\n");
        return 2;
    }
#ifdef POSE_BENCH_NO_PL
    if (use_pl) {
        fprintf(stderr, "built with POSE_BENCH_NO_PL: --pl unavailable\n");
        return 2;
    }
#endif

    blob = read_file(blob_path, &blob_bytes);
    inputs = read_file(input_path, &input_bytes);
    if (blob == NULL || inputs == NULL) goto cleanup;
    if (input_bytes == 0u || input_bytes % POSE_SW_INPUT_BYTES != 0u) {
        fprintf(stderr, "INPUT_BIN size %zu is not a multiple of %u\n",
                input_bytes, POSE_SW_INPUT_BYTES);
        goto cleanup;
    }
    windows = (unsigned)(input_bytes / POSE_SW_INPUT_BYTES);
    if (expected_path != NULL) {
        expected = read_file(expected_path, &expected_bytes);
        if (expected == NULL || expected_bytes != POSE_SW_OUTPUT_BYTES) {
            fprintf(stderr, "EXPECTED must be %u bytes\n", POSE_SW_OUTPUT_BYTES);
            goto cleanup;
        }
    }

    sw = pose_cnn_sw_create(blob, blob_bytes, threads, err, sizeof(err));
    if (sw == NULL) {
        fprintf(stderr, "SW create failed: %s\n", err);
        goto cleanup;
    }
    sw_out = (int8_t *)malloc((size_t)windows * POSE_SW_OUTPUT_BYTES);
    sw_total.ms = (double *)malloc(iterations * sizeof(double));
    sw_enc.ms = (double *)malloc(iterations * sizeof(double));
    sw_fc.ms = (double *)malloc(iterations * sizeof(double));
    if (sw_out == NULL || sw_total.ms == NULL || sw_enc.ms == NULL || sw_fc.ms == NULL) {
        fprintf(stderr, "out of memory\n");
        goto cleanup;
    }

    printf("RX5 pose CNN benchmark: windows=%u iterations=%u sw_threads=%u output_scale=%.9g\n",
           windows, iterations, threads, (double)pose_cnn_sw_output_scale(sw));

    /* reference outputs for every window (also serves as warm-up) */
    for (i = 0u; i < windows; ++i) {
        pose_cnn_sw_infer(sw, (const int8_t *)inputs + (size_t)i * POSE_SW_INPUT_BYTES,
                          POSE_SW_INPUT_BYTES, sw_out + (size_t)i * POSE_SW_OUTPUT_BYTES,
                          NULL, NULL);
    }
    for (i = windows; i < WARMUP_ITERATIONS; ++i) {
        int8_t tmp[POSE_SW_OUTPUT_BYTES];
        pose_cnn_sw_infer(sw, (const int8_t *)inputs, POSE_SW_INPUT_BYTES, tmp, NULL, NULL);
    }
    print_pose("SW  pose[0]:", sw_out);
    if (expected != NULL) {
        unsigned d = count_diff(sw_out, (const int8_t *)expected);
        printf("SW  vs EXPECTED: %s (%u/24 bytes differ)\n", d == 0u ? "BIT-EXACT PASS" : "FAIL", d);
        if (d != 0u) {
            print_pose("EXP pose[0]:", (const int8_t *)expected);
            all_match = 0;
        }
    }

    for (i = 0u; i < iterations; ++i) {
        pose_cnn_sw_timing_t t;
        int8_t tmp[POSE_SW_OUTPUT_BYTES];
        unsigned w = i % windows;
        pose_cnn_sw_infer(sw, (const int8_t *)inputs + (size_t)w * POSE_SW_INPUT_BYTES,
                          POSE_SW_INPUT_BYTES, tmp, &t, NULL);
        sw_total.ms[i] = t.total_ns / 1e6;
        sw_enc.ms[i] = t.encoder_ns / 1e6;
        sw_fc.ms[i] = t.fc_ns / 1e6;
    }
    sw_total.count = sw_enc.count = sw_fc.count = iterations;

#ifndef POSE_BENCH_NO_PL
    if (use_pl) {
        int8_t *pl_out = NULL;
        lock_fd = pose_cnn_lock_acquire();
        if (lock_fd < 0) goto cleanup;
        if (pl_open(&pl, blob, pose_cnn_sw_scale_bits(sw)) != 0) goto cleanup;
        pl_open_ok = 1;
        pl_hw.ms = (double *)malloc(iterations * sizeof(double));
        pl_e2e.ms = (double *)malloc(iterations * sizeof(double));
        pl_out = (int8_t *)malloc((size_t)windows * POSE_SW_OUTPUT_BYTES);
        if (pl_hw.ms == NULL || pl_e2e.ms == NULL || pl_out == NULL) {
            free(pl_out);
            fprintf(stderr, "out of memory\n");
            goto cleanup;
        }
        for (i = 0u; i < windows; ++i) {
            uint64_t hw, e2e;
            int8_t *o = pl_out + (size_t)i * POSE_SW_OUTPUT_BYTES;
            if (pl_infer(&pl, (const int8_t *)inputs + (size_t)i * POSE_SW_INPUT_BYTES,
                         o, &hw, &e2e) != 0) {
                free(pl_out);
                goto cleanup;
            }
            if (count_diff(o, sw_out + (size_t)i * POSE_SW_OUTPUT_BYTES) != 0u) {
                if (pl_mismatch_windows == 0u) {
                    printf("first PL/SW mismatch at window %u\n", i);
                    print_pose("  SW:", sw_out + (size_t)i * POSE_SW_OUTPUT_BYTES);
                    print_pose("  PL:", o);
                }
                pl_mismatch_windows++;
            }
        }
        printf("PL  vs SW: %u/%u windows differ -> %s\n", pl_mismatch_windows, windows,
               pl_mismatch_windows == 0u ? "BIT-EXACT PASS" : "FAIL");
        if (pl_mismatch_windows != 0u) all_match = 0;
        free(pl_out);

        for (i = 0u; i < iterations; ++i) {
            uint64_t hw, e2e;
            int8_t tmp[POSE_SW_OUTPUT_BYTES];
            unsigned w = i % windows;
            if (pl_infer(&pl, (const int8_t *)inputs + (size_t)w * POSE_SW_INPUT_BYTES,
                         tmp, &hw, &e2e) != 0) goto cleanup;
            pl_hw.ms[i] = hw / 1e6;
            pl_e2e.ms[i] = e2e / 1e6;
        }
        pl_hw.count = pl_e2e.count = iterations;
    }
#endif

    printf("\nLatency per window (%u iterations)\n", iterations);
    sw_avg = print_stats("PS  SW total", &sw_total);
    print_stats("PS  SW encoder", &sw_enc);
    print_stats("PS  SW fc", &sw_fc);
#ifndef POSE_BENCH_NO_PL
    if (use_pl) {
        double hw_avg = print_stats("PL  HW (START->DONE)", &pl_hw);
        double e2e_avg = print_stats("PL  e2e (copy+run)", &pl_e2e);
        printf("\nSpeed-up PL vs PS: %.1fx (e2e), %.1fx (HW only)\n",
               e2e_avg > 0.0 ? sw_avg / e2e_avg : 0.0, hw_avg > 0.0 ? sw_avg / hw_avg : 0.0);
        printf("Max window rate : PS %.1f win/s, PL %.1f win/s\n",
               sw_avg > 0.0 ? 1000.0 / sw_avg : 0.0, e2e_avg > 0.0 ? 1000.0 / e2e_avg : 0.0);
    } else
#endif
    {
        printf("Max window rate : PS %.1f win/s\n", sw_avg > 0.0 ? 1000.0 / sw_avg : 0.0);
    }
    exit_code = all_match ? 0 : 1;

cleanup:
#ifndef POSE_BENCH_NO_PL
    if (pl_open_ok) pl_close(&pl);
    if (lock_fd >= 0) close(lock_fd);
    free(pl_hw.ms);
    free(pl_e2e.ms);
#endif
    free(sw_total.ms);
    free(sw_enc.ms);
    free(sw_fc.ms);
    free(sw_out);
    pose_cnn_sw_destroy(sw);
    free(expected);
    free(inputs);
    free(blob);
    return exit_code;
}
