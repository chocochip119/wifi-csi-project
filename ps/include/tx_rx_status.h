#ifndef WISENSING_TX_RX_STATUS_H
#define WISENSING_TX_RX_STATUS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* The existing TX USB STATUS is 44 bytes + 22 bytes per RX.
 * active_count (p[5]) is a RUN-start snapshot, while node LIVE flags are
 * updated by later heartbeats. Never fabricate a fifth active slot from
 * node flags: restart RUN after all five nodes have become ready instead. */
static inline bool tx_rx5_needs_run_restart(const uint8_t *p, size_t len)
{
    unsigned slots = 0u;
    unsigned orders = 0u;
    if (p == NULL || len != 44u + 22u * 5u)
        return false;
    if (p[0] != 1u || p[4] != 5u || p[5] == 0u || p[5] >= 5u ||
        p[6] != 5u || p[7] != 5u)
        return false;
    for (unsigned i = 0u; i < 5u; ++i) {
        const uint8_t *node = p + 44u + 22u * i;
        const unsigned slot = node[0];
        const unsigned saved = node[1];
        const uint8_t flags = node[3];
        if (slot >= 5u || saved >= 5u || (flags & 0x07u) != 0x07u ||
            (slots & (1u << slot)) != 0u || (orders & (1u << saved)) != 0u)
            return false;
        slots |= 1u << slot;
        orders |= 1u << saved;
    }
    return slots == 0x1fu && orders == 0x1fu;
}
#endif
