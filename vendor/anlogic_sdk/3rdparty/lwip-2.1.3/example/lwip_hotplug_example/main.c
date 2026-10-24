/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "al_gbe_ethernetif.h"

#include "lwip/init.h"
#include "lwip/timeouts.h"
#include "al_core.h"

/* Timer interrupt occurs in 50ms */
#define TICK_RATE_HZ                20
#define ETH_LINK_DETECT_INTERVAL    20

extern struct netif gnetif;

static int DetectEthLinkStatus = 0;

void timer_handler(void * Param)
{
    DetectEthLinkStatus++;

    if (DetectEthLinkStatus == ETH_LINK_DETECT_INTERVAL) {
        eth_link_detect(&gnetif);
        DetectEthLinkStatus = 0;
    }
}



int main()
{
    AL_SysTick Systick = {
        .Ticks = AlSys_GetTimerFreq() / TICK_RATE_HZ,
        .CallBack = timer_handler,
        .Priv = NULL
    };

    AlSys_StartTick(&Systick);

    printf("lwip start>>> \r\n");

    /* Initialize the LwIP stack */
    lwip_init();

    netif_config();

    AlIntr_SetLocalInterrupt(AL_FUNC_ENABLE);

    while (1)
    {
        /* Read a received packet from the Ethernet buffers and send it
        to the lwIP for handling */
        ethernetif_input(&gnetif);

        /* Handle timeouts */
        sys_check_timeouts();
    }

    return 0;
}
