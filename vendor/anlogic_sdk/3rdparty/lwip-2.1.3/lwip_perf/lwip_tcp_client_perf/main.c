/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "al_gbe_ethernetif.h"
#include "al_gbe_hal.h"

#include "lwip/init.h"
#include "lwip/priv/tcp_priv.h"
#include "lwip/timeouts.h"

extern struct netif gnetif;

extern void print_iperf_info(void);
extern void iperf_init(void);
extern void transfer_data(void);

int main()
{
    printf("Lwip tcp client iperf>>>\r\n");

    /* Initialize the LwIP stack */
    lwip_init();

    netif_config();

    print_iperf_info();
    iperf_init();

    while (1)
    {
        tcp_fasttmr();

        /* Read a received packet from the Ethernet buffers and send it
        to the lwIP for handling */
        ethernetif_input(&gnetif);

        /* Handle timeouts */
        sys_check_timeouts();
        transfer_data();
    }

    return 0;
}
