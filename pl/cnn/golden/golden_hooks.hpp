#pragma once
// G-01 observation only. Never writes any model tensor or parameter.
#include <cstdio>
#include <cstdlib>
#include <cstdint>

inline FILE* g01_file(const char* name) {
    FILE* f = std::fopen(name, "wb");
    if (!f) { std::perror(name); std::exit(2); }
    return f;
}
inline void g01_close(FILE* f) {
    if (std::ferror(f) || std::fclose(f)) { std::fprintf(stderr, "dump write failed\n"); std::exit(2); }
}
inline void g01_dump_i8(const char* name, const qint8_t* values, int count) {
    FILE* f = g01_file(name);
    for (int i = 0; i < count; ++i) std::fprintf(f, "%02x\n", (unsigned)((int)values[i] & 255));
    g01_close(f);
}
inline void g01_dump_flatten(const qint8_t values[NODE_COUNT][RECEIVER_FLATTEN_DIM]) {
    FILE* f = g01_file("encoder_flat_i8.hex");
    for (int rx = 0; rx < NODE_COUNT; ++rx)
        for (int i = 0; i < RECEIVER_FLATTEN_DIM; ++i)
            std::fprintf(f, "%02x\n", (unsigned)((int)values[rx][i] & 255));
    g01_close(f);
}
static std::int32_t g01_acc[3][HIDDEN_DIM] = {};
static bool g01_acc_seen[3][HIDDEN_DIM] = {};
inline void g01_capture_acc(int stage, int index, qint32_t value) {
    const int count = stage == 3 ? POSE_DIM : HIDDEN_DIM;
    if (stage < 1 || stage > 3 || index < 0 || index >= count || g01_acc_seen[stage-1][index]) {
        std::fprintf(stderr, "invalid/duplicate acc hook stage=%d index=%d\n", stage, index); std::exit(2);
    }
    g01_acc[stage-1][index] = (int)value;
    g01_acc_seen[stage-1][index] = true;
}
inline void g01_dump_accs() {
    for (int stage = 1; stage <= 3; ++stage) {
        char name[40]; std::snprintf(name, sizeof name, "fc%d_acc_i32.hex", stage);
        FILE* f = g01_file(name);
        const int count = stage == 3 ? POSE_DIM : HIDDEN_DIM;
        for (int i = 0; i < count; ++i) {
            if (!g01_acc_seen[stage-1][i]) { std::fprintf(stderr, "missing acc hook\n"); std::exit(2); }
            std::fprintf(f, "%08x\n", (unsigned)(std::uint32_t)g01_acc[stage-1][i]);
        }
        g01_close(f);
    }
}
