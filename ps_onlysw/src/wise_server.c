#define _POSIX_C_SOURCE 200809L
#include "wise_server.h"
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#define MAX_PAYLOAD 8272u
#define QUEUE_DEPTH 64u
#define MAX_AGE_US 250000u
#define STATUS_TTL_US 5000000u

typedef struct {
    uint8_t type;
    size_t length;
    uint64_t timestamp_us;
    uint8_t payload[MAX_PAYLOAD];
} packet_t;
typedef struct {
    int listener;
    pthread_t thread;
    pthread_mutex_t lock;
    bool running, connected, reset;
    unsigned head, count;
    uint32_t sequence;
    packet_t queue[QUEUE_DEPTH], status;
    uint64_t sent, dropped, reconnects;
} channel_t;
struct wise_server { channel_t csi, pose; };

static uint64_t now_us(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint64_t)t.tv_sec * 1000000u + (uint64_t)t.tv_nsec / 1000u;
}
static uint16_t rd16(const uint8_t *p) { return p[0] | (uint16_t)p[1] << 8; }
static void wr16(uint8_t *p, uint16_t x) { p[0] = x; p[1] = x >> 8; }
static void wr32(uint8_t *p, uint32_t x)
{ for (unsigned i = 0; i < 4; ++i) p[i] = (uint8_t)(x >> (8u * i)); }
static void wr64(uint8_t *p, uint64_t x)
{ for (unsigned i = 0; i < 8; ++i) p[i] = (uint8_t)(x >> (8u * i)); }

static int publish(channel_t *c, uint8_t type, const uint8_t *data, size_t length)
{
    packet_t *p;
    uint64_t stamp = now_us();
    pthread_mutex_lock(&c->lock);
    if (type == 3u) {
        c->status.type = type; c->status.length = length;
        c->status.timestamp_us = stamp;
        memcpy(c->status.payload, data, length);
    }
    if (!c->connected || c->reset) { pthread_mutex_unlock(&c->lock); return 0; }
    if (c->count == QUEUE_DEPTH) {
        /* Close the whole TCP stream, never discard part of a framed message. */
        c->dropped += c->count + 1u;
        c->reset = true; c->count = 0;
        pthread_mutex_unlock(&c->lock); return 0;
    }
    p = &c->queue[(c->head + c->count) % QUEUE_DEPTH];
    p->type = type; p->length = length; p->timestamp_us = stamp;
    memcpy(p->payload, data, length); ++c->count;
    pthread_mutex_unlock(&c->lock);
    return 0;
}

static bool cancelled(channel_t *c)
{
    bool value;
    pthread_mutex_lock(&c->lock);
    value = !c->running || c->reset;
    pthread_mutex_unlock(&c->lock);
    return value;
}
static int send_packet(channel_t *c, int fd, const packet_t *p)
{
    uint8_t wire[24u + MAX_PAYLOAD];
    size_t offset = 0, length = 24u + p->length;
    uint64_t deadline = now_us() + MAX_AGE_US;
    memcpy(wire, "WISE", 4); wire[4] = 2; wire[5] = p->type;
    wr16(wire + 6, 24); wr32(wire + 8, (uint32_t)p->length);
    wr32(wire + 12, c->sequence++); wr64(wire + 16, p->timestamp_us);
    memcpy(wire + 24, p->payload, p->length);
    while (offset < length && !cancelled(c) && now_us() < deadline) {
        ssize_t n = send(fd, wire + offset, length - offset, MSG_NOSIGNAL | MSG_DONTWAIT);
        if (n > 0) { offset += (size_t)n; continue; }
        if (n < 0 && errno == EINTR) continue;
        if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            struct pollfd out = {fd, POLLOUT, 0};
            if (poll(&out, 1, 20) < 0 && errno != EINTR) return -1;
            if (out.revents & (POLLERR | POLLHUP | POLLNVAL)) return -1;
            continue;
        }
        return -1;
    }
    if (offset != length) return -1;
    ++c->sent;
    return 0;
}
static void disconnect(channel_t *c, int fd)
{
    pthread_mutex_lock(&c->lock);
    c->connected = false; c->count = 0; c->reset = false;
    pthread_mutex_unlock(&c->lock);
    if (fd >= 0) { shutdown(fd, SHUT_RDWR); close(fd); }
}
static void *worker(void *arg)
{
    channel_t *c = arg;
    int client = -1;
    packet_t p;
    for (;;) {
        bool running;
        pthread_mutex_lock(&c->lock); running = c->running; pthread_mutex_unlock(&c->lock);
        if (!running) break;
        if (client < 0) {
            struct pollfd in = {c->listener, POLLIN, 0};
            if (poll(&in, 1, 20) <= 0) continue;
            client = accept(c->listener, NULL, NULL);
            if (client < 0) continue;
            int one = 1, buffer_bytes = 32768;
            setsockopt(client, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
            setsockopt(client, SOL_SOCKET, SO_SNDBUF, &buffer_bytes, sizeof(buffer_bytes));
#ifdef TCP_NOTSENT_LOWAT
            setsockopt(client, IPPROTO_TCP, TCP_NOTSENT_LOWAT, &one, sizeof(one));
#endif
            pthread_mutex_lock(&c->lock);
            c->head = c->count = 0; c->reset = false; ++c->reconnects;
            p = c->status;
            c->connected = true;
            pthread_mutex_unlock(&c->lock);
            /* Replay only a recent STATUS; otherwise wait for PS's periodic request. */
            if (p.length && now_us() - p.timestamp_us <= STATUS_TTL_US && send_packet(c, client, &p)) {
                disconnect(c, client); client = -1;
            }
            continue;
        }
        struct pollfd in = {client, POLLIN, 0};
        if (poll(&in, 1, 0) > 0) {
            /* This version is PS -> PC only: EOF or unexpected PC data resets it. */
            if (in.revents & (POLLIN | POLLERR | POLLHUP | POLLNVAL)) {
                disconnect(c, client); client = -1; continue;
            }
        }
        bool have = false, reset;
        pthread_mutex_lock(&c->lock);
        reset = c->reset;
        if (!reset && c->count) {
            p = c->queue[c->head]; c->head = (c->head + 1u) % QUEUE_DEPTH;
            --c->count; have = true;
        }
        pthread_mutex_unlock(&c->lock);
        if (reset || (have && (now_us() - p.timestamp_us > MAX_AGE_US || send_packet(c, client, &p)))) {
            disconnect(c, client); client = -1;
        } else if (!have) {
            struct timespec pause = {0, 1000000}; nanosleep(&pause, NULL);
        }
    }
    disconnect(c, client);
    return NULL;
}
static int start_channel(channel_t *c, const char *ip, uint16_t port)
{
    struct sockaddr_in addr = {.sin_family = AF_INET, .sin_port = htons(port)};
    int one = 1;
    c->listener = -1;
    if (inet_pton(AF_INET, ip, &addr.sin_addr) != 1) return -1;
    if (pthread_mutex_init(&c->lock, NULL)) return -1;
    c->listener = socket(AF_INET, SOCK_STREAM, 0);
    if (c->listener < 0) goto fail;
    setsockopt(c->listener, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    if (bind(c->listener, (struct sockaddr *)&addr, sizeof(addr)) || listen(c->listener, 1)) goto fail;
    if (fcntl(c->listener, F_SETFL, O_NONBLOCK) < 0) goto fail;
    c->running = true;
    if (pthread_create(&c->thread, NULL, worker, c)) goto fail;
    return 0;
fail:
    if (c->listener >= 0) close(c->listener);
    pthread_mutex_destroy(&c->lock); return -1;
}
static void stop_channel(channel_t *c)
{
    pthread_mutex_lock(&c->lock); c->running = false; pthread_mutex_unlock(&c->lock);
    pthread_join(c->thread, NULL); close(c->listener);
    fprintf(stderr, "WISE TCP sent=%llu resets/accepts=%llu dropped=%llu\n",
            (unsigned long long)c->sent, (unsigned long long)c->reconnects,
            (unsigned long long)c->dropped);
    pthread_mutex_destroy(&c->lock);
}
wise_server_t *wise_server_start(const char *ip, uint16_t csi_port, uint16_t pose_port)
{
    if (!ip || !csi_port || !pose_port || csi_port == pose_port) return NULL;
    wise_server_t *s = calloc(1, sizeof(*s));
    if (!s) return NULL;
    if (start_channel(&s->csi, ip, csi_port)) { free(s); return NULL; }
    if (start_channel(&s->pose, ip, pose_port)) { stop_channel(&s->csi); free(s); return NULL; }
    return s;
}
void wise_server_stop(wise_server_t *s)
{ if (s) { stop_channel(&s->csi); stop_channel(&s->pose); free(s); } }
int wise_server_usb(wise_server_t *s, uint8_t type, uint32_t uart_seq,
                    const uint8_t *payload, size_t length)
{
    if (!s) return 0;
    if (!payload || length > MAX_PAYLOAD) return -1;
    if (type == 1u) {
        if (length < 44u || payload[7] > 8u || length != 44u + 22u * payload[7]) return -1;
        return publish(&s->csi, 3, payload, length);
    }
    if (type == 3u) {
        if (length != 76u) return -1;
        return publish(&s->csi, 4, payload, length);
    }
    if (type != 2u || length < 32u || payload[28] > 8u || payload[30] > 1u) return -1;
    uint8_t out[MAX_PAYLOAD] = {0}, seen = 0, mask = 0, received = 0;
    size_t cursor = 32, dest = 16;
    for (unsigned i = 0; i < payload[28]; ++i) {
        if (cursor + 6u > length) return -1;
        uint8_t id = payload[cursor], valid = payload[cursor + 1];
        uint16_t n = rd16(payload + cursor + 4);
        if (id >= 8 || (seen & (1u << id)) || valid > 1u || n > 1024 || (n & 1u) ||
            (bool)valid != (bool)n || cursor + 6u + n > length || dest + 8u + n > MAX_PAYLOAD) return -1;
        seen |= 1u << id; mask |= valid << id; received += valid;
        out[dest] = id; out[dest + 1] = valid; out[dest + 2] = payload[cursor + 2];
        wr16(out + dest + 4, n);
        memcpy(out + dest + 8, payload + cursor + 6, n);
        cursor += 6u + n; dest += 8u + n;
    }
    if (cursor != length || received != payload[29]) return -1;
    memcpy(out, payload + 4, 4); wr32(out + 4, uart_seq);
    out[8] = payload[28]; out[9] = received; out[10] = payload[28];
    out[11] = mask; out[12] = payload[30];
    return publish(&s->csi, 1, out, dest);
}
int wise_server_pose(wise_server_t *s, uint32_t window, uint32_t end_seq,
                     uint32_t infer_us, float scale, const int8_t pose[24])
{
    uint8_t out[40]; uint32_t bits;
    if (!s) return 0;
    if (!pose || !isfinite(scale) || scale <= 0) return -1;
    _Static_assert(sizeof(float) == 4, "IEEE binary32 required");
    memcpy(&bits, &scale, 4);
    wr32(out, window); wr32(out + 4, end_seq); wr32(out + 8, infer_us); wr32(out + 12, bits);
    memcpy(out + 16, pose, 24);
    return publish(&s->pose, 2, out, sizeof(out));
}
