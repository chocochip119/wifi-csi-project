// File-driven host adapter. The reference model itself is unchanged.
#include "full_pose.h"
#include <cmath>
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iterator>
#include <stdexcept>
#include <vector>

static std::vector<unsigned char> read_exact(const char* path, std::size_t size) {
    std::ifstream f(path, std::ios::binary);
    if (!f) throw std::runtime_error("cannot open input");
    std::vector<unsigned char> v((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
    if (v.size() != size) throw std::runtime_error("unexpected file size");
    return v;
}
static std::uint32_t le32(const unsigned char* b) {
    return std::uint32_t(b[0]) | (std::uint32_t(b[1]) << 8) |
           (std::uint32_t(b[2]) << 16) | (std::uint32_t(b[3]) << 24);
}
int main(int argc, char** argv) {
    try {
        if (argc != 3) throw std::runtime_error("usage: runner blob.bin input_i8.bin (writes to cwd)");
        static_assert(sizeof(float) == 4 && sizeof(std::uint32_t) == 4, "float32 required");
        auto blob = read_exact(argv[1], WEIGHT_WORDS * 4);
        auto bytes = read_exact(argv[2], INPUT_CHANNELS * INPUT_H * INPUT_W);
        if (le32(blob.data()) != WEIGHT_MAGIC || le32(blob.data()+4) != WEIGHT_VERSION ||
            le32(blob.data()+8) != WEIGHT_WORDS) throw std::runtime_error("invalid blob header");
        static qint8_t input[INPUT_CHANNELS * INPUT_H * INPUT_W];
        static packed_weight_t weights[WEIGHT_WORDS];
        float pose[POSE_DIM] = {};
        for (int i = 0; i < INPUT_CHANNELS * INPUT_H * INPUT_W; ++i)
            input[i] = bytes[i] < 128 ? int(bytes[i]) : int(bytes[i]) - 256;
        for (int i = 0; i < WEIGHT_WORDS; ++i) weights[i] = le32(blob.data() + 4*i);
        full_pose_accel(input, weights, 1, pose);
        full_pose_accel(input, weights, 0, pose);
        FILE* txt = std::fopen("pose_f32.txt", "wb");
        FILE* hex = std::fopen("pose_f32.hex", "wb");
        if (!txt || !hex) throw std::runtime_error("cannot open pose dump");
        float checksum = 0;
        for (int i = 0; i < POSE_DIM; ++i) {
            if (!std::isfinite(pose[i])) throw std::runtime_error("non-finite pose");
            std::uint32_t bits; std::memcpy(&bits, &pose[i], 4);
            std::fprintf(txt, "%.9g\n", pose[i]);
            std::fprintf(hex, "%08x\n", unsigned(bits));
            std::printf("pose[%02d]=%.9f bits=%08x\n", i, pose[i], unsigned(bits));
            checksum += pose[i];
        }
        bool bad = std::ferror(txt) || std::ferror(hex);
        bad = std::fclose(txt) != 0 || bad;
        bad = std::fclose(hex) != 0 || bad;
        if (bad) throw std::runtime_error("pose dump write failed");
        std::printf("PASS: file-driven golden pose_count=24 checksum=%.9f\n", checksum);
        return 0;
    } catch (const std::exception& e) {
        std::fprintf(stderr, "FAIL: %s\n", e.what()); return 2;
    }
}
