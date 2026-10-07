#ifndef WISE_SERVER_H
#define WISE_SERVER_H
#include <stddef.h>
#include <stdint.h>
typedef struct wise_server wise_server_t;
/* IPv4 servers, one PC per port. Producers only copy into bounded queues. */
wise_server_t *wise_server_start(const char *bind_ip, uint16_t csi_port, uint16_t pose_port);
void wise_server_stop(wise_server_t *server);
/* USB frame has already passed the serial checksum. Invalid payloads are rejected. */
int wise_server_usb(wise_server_t *server, uint8_t type, uint32_t uart_seq,
                    const uint8_t *payload, size_t length);
int wise_server_pose(wise_server_t *server, uint32_t window_id, uint32_t end_seq,
                     uint32_t infer_us, float scale, const int8_t pose[24]);
#endif
