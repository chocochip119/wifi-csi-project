#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#include "pose_cnn_regs.h"
#include "pose_cnn_lock.h"

#define CSR_MAP_BYTES       0x00010000u
#define DDR_RESERVED_BASE   0x3F000000u
#define DDR_RESERVED_BYTES  0x01000000u
#define WEIGHT_PHYS         0x3F000000u
#define INPUT_PHYS          0x3F100000u
#define OUTPUT_PHYS         0x3F200000u

#define DEFAULT_DATA_DIR    "/usr/share/pose-cnn-rx5"
#define DEFAULT_BLOB_PATH   DEFAULT_DATA_DIR "/blob_rx5_test.bin"
#define DEFAULT_INPUT_PATH  DEFAULT_DATA_DIR "/input_rx5_test.bin"
#define DEFAULT_EXPECT_PATH DEFAULT_DATA_DIR "/pose_expected.bin"

#define EXPECTED_SCALE_BITS 0x3BD997A8u
#define LOAD_TIMEOUT_MS     1000L
#define INFER_TIMEOUT_MS    1000L

typedef struct {
    void *mapping;
    size_t mapping_bytes;
    volatile uint8_t *ptr;
} phys_mapping_t;

static void barrier(void)
{
    __sync_synchronize();
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

static long elapsed_ms(const struct timespec *start, const struct timespec *now)
{
    return (now->tv_sec - start->tv_sec) * 1000L +
           (now->tv_nsec - start->tv_nsec) / 1000000L;
}

static int map_physical(int fd, uint32_t phys, size_t bytes, phys_mapping_t *out)
{
    long page_size = sysconf(_SC_PAGESIZE);
    uint32_t page_mask;
    uint32_t page_base;
    size_t page_offset;
    size_t map_bytes;
    void *mapping;

    if (page_size <= 0 || ((unsigned long)page_size & ((unsigned long)page_size - 1ul)) != 0ul) {
        fprintf(stderr, "invalid page size: %ld\n", page_size);
        return -1;
    }

    page_mask = (uint32_t)page_size - 1u;
    page_base = phys & ~page_mask;
    page_offset = (size_t)(phys - page_base);
    map_bytes = page_offset + bytes;
    map_bytes = (map_bytes + (size_t)page_size - 1u) & ~((size_t)page_size - 1u);

    mapping = mmap(NULL, map_bytes, PROT_READ | PROT_WRITE, MAP_SHARED, fd, (off_t)page_base);
    if (mapping == MAP_FAILED) {
        fprintf(stderr, "mmap phys=0x%08" PRIx32 " bytes=%zu: %s\n",
                phys, bytes, strerror(errno));
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
    mapping->mapping = NULL;
    mapping->mapping_bytes = 0u;
    mapping->ptr = NULL;
}

static int load_exact_file(const char *path, uint8_t *buffer, size_t expected_bytes)
{
    FILE *file = fopen(path, "rb");
    long length;
    size_t received;

    if (file == NULL) {
        fprintf(stderr, "open %s: %s\n", path, strerror(errno));
        return -1;
    }
    if (fseek(file, 0, SEEK_END) != 0 || (length = ftell(file)) < 0 ||
        fseek(file, 0, SEEK_SET) != 0) {
        fprintf(stderr, "size %s: %s\n", path, strerror(errno));
        fclose(file);
        return -1;
    }
    if ((size_t)length != expected_bytes) {
        fprintf(stderr, "wrong size %s: got %ld expected %zu\n",
                path, length, expected_bytes);
        fclose(file);
        return -1;
    }
    received = fread(buffer, 1u, expected_bytes, file);
    if (received != expected_bytes || ferror(file)) {
        fprintf(stderr, "read %s: got %zu expected %zu\n",
                path, received, expected_bytes);
        fclose(file);
        return -1;
    }
    fclose(file);
    return 0;
}

static int validate_blob_header(const uint8_t *blob)
{
    uint32_t words[5];
    memcpy(words, blob, sizeof(words));

    if (words[0] != POSE_CNN_BLOB_MAGIC ||
        words[1] != POSE_CNN_BLOB_VERSION ||
        words[2] != POSE_CNN_BLOB_WORDS) {
        fprintf(stderr,
                "bad blob header: magic=0x%08" PRIx32 " version=%" PRIu32
                " words=%" PRIu32 "\n",
                words[0], words[1], words[2]);
        return -1;
    }
    return 0;
}

static int check_rw_register(volatile uint32_t *csr,
                             unsigned offset,
                             uint32_t value,
                             const char *name)
{
    uint32_t readback;
    reg_write(csr, offset, value);
    readback = reg_read(csr, offset);
    if (readback != value) {
        fprintf(stderr, "FAIL register %s: wrote 0x%08" PRIx32
                " read 0x%08" PRIx32 "\n", name, value, readback);
        return -1;
    }
    printf("REGISTER PASS %-11s = 0x%08" PRIx32 "\n", name, readback);
    return 0;
}

static int wait_complete(volatile uint32_t *csr,
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
            fprintf(stderr, "FAIL %s timeout: status=0x%08" PRIx32 "\n",
                    operation, status);
            return -1;
        }
        nanosleep(&delay, NULL);
    }
}

static int start_and_wait(volatile uint32_t *csr,
                          uint32_t command,
                          const char *operation,
                          long timeout_ms,
                          uint32_t *status_out,
                          long *elapsed_out)
{
    reg_write(csr, POSE_CNN_CONTROL, POSE_CNN_CTRL_CLEAR);
    reg_write(csr, POSE_CNN_CMD, command);
    reg_write(csr, POSE_CNN_CONTROL, POSE_CNN_CTRL_START);
    return wait_complete(csr, operation, timeout_ms, status_out, elapsed_out);
}

static int validate_status(const char *operation, uint32_t status, int require_cfg)
{
    if ((status & POSE_CNN_ST_ERROR) != 0u) {
        fprintf(stderr, "FAIL %s: status=0x%08" PRIx32 " error_code=%" PRIu32 "\n",
                operation, status, POSE_CNN_ST_ERR_CODE(status));
        return -1;
    }
    if ((status & POSE_CNN_ST_DONE) == 0u ||
        (status & POSE_CNN_ST_BUSY) != 0u ||
        (require_cfg && (status & POSE_CNN_ST_CFG_OK) == 0u)) {
        fprintf(stderr, "FAIL %s unexpected status=0x%08" PRIx32 "\n",
                operation, status);
        return -1;
    }
    return 0;
}

static void print_pose(const volatile int8_t *pose)
{
    unsigned i;
    printf("POSE int8:");
    for (i = 0u; i < POSE_CNN_OUTPUT_BYTES; ++i) {
        printf(" %d", (int)pose[i]);
    }
    putchar('\n');
}

int main(int argc, char **argv)
{
    const char *blob_path = argc > 1 ? argv[1] : DEFAULT_BLOB_PATH;
    const char *input_path = argc > 2 ? argv[2] : DEFAULT_INPUT_PATH;
    const char *expected_path = argc > 3 ? argv[3] : DEFAULT_EXPECT_PATH;
    uint8_t *blob_file = NULL;
    uint8_t *input_file = NULL;
    uint8_t expected[POSE_CNN_OUTPUT_BYTES];
    int fd = -1;
    int lock_fd = -1;
    phys_mapping_t csr_map = {0};
    phys_mapping_t weight_map = {0};
    phys_mapping_t input_map = {0};
    phys_mapping_t output_map = {0};
    volatile uint32_t *csr;
    volatile int8_t *pose;
    uint32_t status;
    uint32_t scale_bits;
    long operation_ms;
    unsigned i;
    int result = EXIT_FAILURE;

    printf("WiSensing RX5 pose CNN board test\n");
    printf("CSR=0x%08x weight=0x%08x input=0x%08x output=0x%08x\n",
           POSE_CNN_BASEADDR, WEIGHT_PHYS, INPUT_PHYS, OUTPUT_PHYS);
    printf("shape=[15,128,10] input=%u blob=%u output=%u\n",
           POSE_CNN_INPUT_BYTES, POSE_CNN_BLOB_BYTES, POSE_CNN_OUTPUT_BYTES);

    if (WEIGHT_PHYS < DDR_RESERVED_BASE ||
        OUTPUT_PHYS + POSE_CNN_OUTPUT_BYTES > DDR_RESERVED_BASE + DDR_RESERVED_BYTES) {
        fprintf(stderr, "internal DDR layout exceeds reserved memory\n");
        goto cleanup;
    }

    blob_file = malloc(POSE_CNN_BLOB_BYTES);
    input_file = malloc(POSE_CNN_INPUT_BYTES);
    if (blob_file == NULL || input_file == NULL) {
        fprintf(stderr, "malloc failed\n");
        goto cleanup;
    }
    if (load_exact_file(blob_path, blob_file, POSE_CNN_BLOB_BYTES) != 0 ||
        load_exact_file(input_path, input_file, POSE_CNN_INPUT_BYTES) != 0 ||
        load_exact_file(expected_path, expected, sizeof(expected)) != 0 ||
        validate_blob_header(blob_file) != 0) {
        goto cleanup;
    }

    lock_fd = pose_cnn_lock_acquire();
    if (lock_fd < 0) goto cleanup;
    fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        fprintf(stderr, "open /dev/mem: %s\n", strerror(errno));
        goto cleanup;
    }
    if (map_physical(fd, POSE_CNN_BASEADDR, CSR_MAP_BYTES, &csr_map) != 0 ||
        map_physical(fd, WEIGHT_PHYS, POSE_CNN_BLOB_BYTES, &weight_map) != 0 ||
        map_physical(fd, INPUT_PHYS, POSE_CNN_INPUT_BYTES, &input_map) != 0 ||
        map_physical(fd, OUTPUT_PHYS, POSE_CNN_OUTPUT_BYTES, &output_map) != 0) {
        goto cleanup;
    }

    csr = (volatile uint32_t *)csr_map.ptr;
    pose = (volatile int8_t *)output_map.ptr;
    status = reg_read(csr, POSE_CNN_STATUS);
    if ((status & POSE_CNN_ST_BUSY) != 0u) {
        fprintf(stderr, "IP is busy before test: status=0x%08" PRIx32 "\n", status);
        goto cleanup;
    }

    if (check_rw_register(csr, POSE_CNN_WEIGHT_ADDR, WEIGHT_PHYS, "WEIGHT_ADDR") != 0 ||
        check_rw_register(csr, POSE_CNN_INPUT_ADDR, INPUT_PHYS, "INPUT_ADDR") != 0 ||
        check_rw_register(csr, POSE_CNN_OUTPUT_ADDR, OUTPUT_PHYS, "OUTPUT_ADDR") != 0) {
        goto cleanup;
    }

    memcpy((void *)weight_map.ptr, blob_file, POSE_CNN_BLOB_BYTES);
    memset((void *)output_map.ptr, 0xA5, POSE_CNN_OUTPUT_BYTES);
    barrier();

    if (start_and_wait(csr, POSE_CNN_CMD_LOAD, "LOAD", LOAD_TIMEOUT_MS,
                       &status, &operation_ms) != 0 ||
        validate_status("LOAD", status, 1) != 0) {
        goto cleanup;
    }
    scale_bits = reg_read(csr, POSE_CNN_SCALE);
    printf("LOAD PASS status=0x%08" PRIx32 " scale_bits=0x%08" PRIx32
           " elapsed_ms=%ld\n", status, scale_bits, operation_ms);
    if (scale_bits != EXPECTED_SCALE_BITS) {
        fprintf(stderr, "FAIL SCALE: got 0x%08" PRIx32 " expected 0x%08x\n",
                scale_bits, EXPECTED_SCALE_BITS);
        goto cleanup;
    }

    memcpy((void *)input_map.ptr, input_file, POSE_CNN_INPUT_BYTES);
    memset((void *)output_map.ptr, 0xA5, POSE_CNN_OUTPUT_BYTES);
    barrier();

    if (start_and_wait(csr, POSE_CNN_CMD_INFER, "INFER", INFER_TIMEOUT_MS,
                       &status, &operation_ms) != 0 ||
        validate_status("INFER", status, 1) != 0) {
        goto cleanup;
    }
    barrier();
    print_pose(pose);
    for (i = 0u; i < POSE_CNN_OUTPUT_BYTES; ++i) {
        uint8_t actual = ((volatile uint8_t *)output_map.ptr)[i];
        if (actual != expected[i]) {
            fprintf(stderr,
                    "FAIL OUTPUT[%u]: got 0x%02x (%d) expected 0x%02x (%d)\n",
                    i, actual, (int)(int8_t)actual,
                    expected[i], (int)(int8_t)expected[i]);
            goto cleanup;
        }
    }

    printf("INFER PASS status=0x%08" PRIx32 " elapsed_ms=%ld\n",
           status, operation_ms);
    printf("BIT-EXACT PASS: output matches pose_expected.bin (24/24 bytes)\n");
    printf("BOARD RX5 CNN PASS: S00 CSR + M00 HP0 + LOAD + INFER verified\n");
    result = EXIT_SUCCESS;

cleanup:
    unmap_physical(&output_map);
    unmap_physical(&input_map);
    unmap_physical(&weight_map);
    unmap_physical(&csr_map);
    if (fd >= 0) {
        close(fd);
    }
    free(input_file);
    free(blob_file);
    if (lock_fd >= 0) close(lock_fd);
    return result;
}
