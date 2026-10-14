#include "../include/tx_rx_status.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static void status(uint8_t *p, unsigned active)
{
    memset(p, 0, 44u + 22u * 5u);
    p[0] = 1u; /* RUN */
    p[4] = 5u; /* connected */
    p[5] = (uint8_t)active; /* running node count, frozen at RUN start */
    p[6] = 5u; /* saved */
    p[7] = 5u; /* entries */
    for (unsigned i = 0; i < 5u; ++i) {
        uint8_t *node = p + 44u + 22u * i;
        node[0] = (uint8_t)i;
        node[1] = (uint8_t)i;
        node[3] = 0x07u; /* CONNECTED|SAVED|LIVE */
    }
}

int main(void)
{
    uint8_t p[44u + 22u * 5u];
    status(p, 4u);
    assert(tx_rx5_needs_run_restart(p, sizeof(p)));
    assert(!tx_rx5_needs_run_restart(p, sizeof(p)-1u));
    p[0] = 0u;
    assert(!tx_rx5_needs_run_restart(p, sizeof(p)));
    p[0] = 1u;
    p[5] = 5u;
    assert(!tx_rx5_needs_run_restart(p, sizeof(p)));
    p[5] = 4u;
    p[44u + 22u * 4u + 3u] = 0x03u; /* fifth not LIVE */
    assert(!tx_rx5_needs_run_restart(p, sizeof(p)));
    p[44u + 22u * 4u + 3u] = 0x07u;
    p[44u + 22u * 4u + 1u] = 3u; /* duplicate saved index */
    assert(!tx_rx5_needs_run_restart(p, sizeof(p)));
    status(p, 3u);
    assert(tx_rx5_needs_run_restart(p, sizeof(p)));
    puts("tx_rx5_needs_run_restart PASS");
    return 0;
}
