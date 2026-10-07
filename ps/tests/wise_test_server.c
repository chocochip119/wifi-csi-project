/* Host-only transport harness: no /dev/mem, serial device, or FPGA. */
#define _POSIX_C_SOURCE 200809L
#include "csi_pipeline.h"
#include "wise_server.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static wise_server_t *server;
static int result;
static void frame(uint8_t type, uint32_t seq, const uint8_t *data, size_t length, void *user)
{ (void)user; result = wise_server_usb(server, type, seq, data, length); }
int main(int argc, char **argv)
{
    if (argc != 3) return 2;
    server = wise_server_start("127.0.0.1", (uint16_t)atoi(argv[1]), (uint16_t)atoi(argv[2]));
    if (!server) return 3;
    csi_pipeline_t *pipe = csi_pipeline_create(0.02f);
    if (!pipe) { wise_server_stop(server); return 4; }
    csi_pipeline_set_frame_callback(pipe, frame, NULL);
    puts("READY"); fflush(stdout);
    char *line = NULL; size_t capacity = 0;
    while (getline(&line, &capacity, stdin) > 0) {
        if (line[0] == 'Q') break;
        if (line[0] == 'P') {
            int8_t pose[24]; for (int i = 0; i < 24; ++i) pose[i] = (int8_t)(i - 12);
            result = wise_server_pose(server, 7, 123, 23000, 0.01f, pose);
        } else {
            uint8_t data[12304]; size_t n = 0; char *p = line + 2; unsigned value;
            while (*p && *p != '\n' && n < sizeof(data)) {
                if (sscanf(p, "%2x", &value) != 1) break;
                data[n++] = (uint8_t)value; p += 2;
            }
            result = 99;
            if (line[0] == 'B') {
                /* Reuse one USB cycle payload quickly to exercise queue overflow. */
                for (int i = 0; i < 3000; ++i) result = wise_server_usb(server, 2, (uint32_t)i, data, n);
            } else {
                for (size_t offset = 0; offset < n; offset += 7) {
                    size_t chunk = n - offset < 7 ? n - offset : 7;
                    if (csi_pipeline_feed(pipe, data + offset, chunk, NULL, NULL, NULL) < 0) result = -2;
                }
            }
        }
        printf("RESULT %d\n", result); fflush(stdout);
    }
    free(line); csi_pipeline_destroy(pipe); wise_server_stop(server); return 0;
}
