/*
 * Host replay for ps/src/loc_ridge.c (no board, no POSIX).
 * Replay file: repeated [u8 usb_type][u64 t_ns][u32 length][payload], little-endian.
 * Prints one "R" line per prediction and a final "S" stats line.
 *
 *   gcc -std=c11 -O2 -Ips/include ps/src/loc_ridge.c ps/tests/loc_ridge_replay.c -lm -o loc_ridge_replay
 *   loc_ridge_replay MODEL REPLAY [STRIDE_S]
 */
#include "loc_ridge.h"

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void on_result(const loc_result_t *r, void *user)
{
    (void)user;
    printf("R %" PRIu32 " %" PRIu32 " %u %u %u %d %d %" PRIu64 " %" PRIu64,
           r->window_id, r->end_trigger_seq, r->class_code, r->occupied, r->window_cycles,
           r->x_cm, r->y_cm, r->window_start_us, r->window_end_us);
    for (unsigned i = 0; i < r->n_scores; ++i) printf(" %.9g", (double)r->scores[i]);
    putchar('\n');
}

int main(int argc, char **argv)
{
    char err[256] = "";
    static uint8_t payload[65536];
    loc_engine_t *engine;
    loc_stats_t s;
    FILE *in;

    if (argc < 3 || argc > 4) {
        fprintf(stderr, "usage: %s MODEL REPLAY [STRIDE_S]\n", argv[0]);
        return 2;
    }
    engine = loc_engine_open(argv[1], argc == 4 ? atof(argv[3]) : 0.0, on_result, NULL, err, sizeof(err));
    if (!engine) { fprintf(stderr, "open failed: %s\n", err); return 1; }
    in = fopen(argv[2], "rb");
    if (!in) { fprintf(stderr, "cannot open %s\n", argv[2]); loc_engine_close(engine); return 1; }
    for (;;) {
        uint8_t head[13];
        uint64_t t_ns;
        uint32_t length;
        if (fread(head, 1, sizeof(head), in) != sizeof(head)) break;
        memcpy(&t_ns, head + 1, 8);
        memcpy(&length, head + 9, 4);
        if (length > sizeof(payload) || fread(payload, 1, length, in) != length) {
            fprintf(stderr, "truncated replay\n");
            fclose(in); loc_engine_close(engine); return 1;
        }
        loc_engine_usb(engine, head[0], payload, length, t_ns);
    }
    fclose(in);
    loc_engine_get_stats(engine, &s);
    printf("S status=%" PRIu64 " invalid_status=%" PRIu64 " ack_resets=%" PRIu64 " frames=%" PRIu64
           " not_ready=%" PRIu64 " chronology=%" PRIu64 " invalid=%" PRIu64 " valid=%" PRIu64
           " rate_limited=%" PRIu64 " gaps=%" PRIu64 " stale=%" PRIu64 " overflow=%" PRIu64
           " short=%" PRIu64 " predictions=%" PRIu64 "\n",
           s.status_frames, s.invalid_status, s.ack_resets, s.cycle_frames, s.not_ready_frames,
           s.chronology_rejects, s.invalid_cycles, s.valid_cycles, s.rate_limited_cycles, s.gaps,
           s.stale_resets, s.buffer_overflows, s.short_windows, s.predictions);
    loc_engine_close(engine);
    return 0;
}
