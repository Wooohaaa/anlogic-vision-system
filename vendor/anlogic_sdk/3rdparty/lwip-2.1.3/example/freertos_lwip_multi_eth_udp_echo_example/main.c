/*
    FreeRTOS V9.0.0 - Copyright (C) 2016 Real Time Engineers Ltd.
    All rights reserved

    VISIT http://www.FreeRTOS.org TO ENSURE YOU ARE USING THE LATEST VERSION.

    This file is part of the FreeRTOS distribution.

    FreeRTOS is free software; you can redistribute it and/or modify it under
    the terms of the GNU General Public License (version 2) as published by the
    Free Software Foundation >>>> AND MODIFIED BY <<<< the FreeRTOS exception.

    ***************************************************************************
    >>!   NOTE: The modification to the GPL is included to allow you to     !<<
    >>!   distribute a combined work that includes FreeRTOS without being   !<<
    >>!   obliged to provide the source code for proprietary components     !<<
    >>!   outside of the FreeRTOS kernel.                                   !<<
    ***************************************************************************

    FreeRTOS is distributed in the hope that it will be useful, but WITHOUT ANY
    WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
    FOR A PARTICULAR PURPOSE.  Full license text is available on the following
    link: http://www.freertos.org/a00114.html

    ***************************************************************************
     *                                                                       *
     *    FreeRTOS provides completely free yet professionally developed,    *
     *    robust, strictly quality controlled, supported, and cross          *
     *    platform software that is more than just the market leader, it     *
     *    is the industry's de facto standard.                               *
     *                                                                       *
     *    Help yourself get started quickly while simultaneously helping     *
     *    to support the FreeRTOS project by purchasing a FreeRTOS           *
     *    tutorial book, reference manual, or both:                          *
     *    http://www.FreeRTOS.org/Documentation                              *
     *                                                                       *
    ***************************************************************************

    http://www.FreeRTOS.org/FAQHelp.html - Having a problem?  Start by reading
    the FAQ page "My application does not run, what could be wrong?".  Have you
    defined configASSERT()?

    http://www.FreeRTOS.org/support - In return for receiving this top quality
    embedded software for free we request you assist our global community by
    participating in the support forum.

    http://www.FreeRTOS.org/training - Investing in training allows your team to
    be as productive as possible as early as possible.  Now you can receive
    FreeRTOS training directly from Richard Barry, CEO of Real Time Engineers
    Ltd, and the world's leading authority on the world's leading RTOS.

    http://www.FreeRTOS.org/plus - A selection of FreeRTOS ecosystem products,
    including FreeRTOS+Trace - an indispensable productivity tool, a DOS
    compatible FAT file system, and our tiny thread aware UDP/IP stack.

    http://www.FreeRTOS.org/labs - Where new FreeRTOS products go to incubate.
    Come and try FreeRTOS+TCP, our new open source TCP/IP stack for FreeRTOS.

    http://www.OpenRTOS.com - Real Time Engineers ltd. license FreeRTOS to High
    Integrity Systems ltd. to sell under the OpenRTOS brand.  Low cost OpenRTOS
    licenses offer ticketed support, indemnification and commercial middleware.

    http://www.SafeRTOS.com - High Integrity Systems also provide a safety
    engineered and independently SIL3 certified version for use in safety and
    mission critical applications that require provable dependability.

    1 tab == 4 spaces!
*/

/* Kernel includes. */
#include "FreeRTOS.h" /* Must come first. */
#include "queue.h"    /* RTOS queue related API prototypes. */
#include "semphr.h"   /* Semaphore related API prototypes. */
#include "task.h"     /* RTOS task related API prototypes. */
#include "timers.h"   /* Software timer related API prototypes. */

#include "al_gbe_ethernetif.h"
#include "netif/ethernet.h"
#include "lwip/tcpip.h"

#include <stdio.h>
#include <stdlib.h>

#define UDP_ECHO_THREAD_STACK_SIZE      (4096 / (sizeof( StackType_t )))
#define UDP_ECHO_THREAD_PRIO            (ETH_INPUT_THREAD_PRIO)

/* define MAC Address */
#define MAC0_ADDR0              (0x64)
#define MAC0_ADDR1              (0x00)
#define MAC0_ADDR2              (0x6a)
#define MAC0_ADDR3              (0x19)
#define MAC0_ADDR4              (0x74)
#define MAC0_ADDR5              (0x7f)

#define MAC1_ADDR0              (0x64)
#define MAC1_ADDR1              (0x00)
#define MAC1_ADDR2              (0x6a)
#define MAC1_ADDR3              (0x19)
#define MAC1_ADDR4              (0x74)
#define MAC1_ADDR5              (0x77)

/* define IP address、netmask and gateway */
#define ETH0_IP_ADDRESS         "192.168.31.10"
#define ETH0_NET_MASK           "255.255.255.0"
#define ETH0_GW_ADDRESS         "192.168.31.1"

#define ETH1_IP_ADDRESS         "192.168.32.20"
#define ETH1_NET_MASK           "255.255.255.0"
#define ETH1_GW_ADDRESS         "192.168.32.1"

/*
   This configuration requires reference to the CFG_CTRL_GBE register description,
   and Different Phy may have different phase configurations.

   Note:
   If configured to 0, the phase configuration in the phy driver file will be used,
   However, it is necessary to check whether the configuration in the phy driver is reasonable.
 */
#define GBE0_PHY_YT8531_RGMII_PHASE_1000M   0x621
#define GBE0_PHY_YT8531_RGMII_PHASE_100M    0x361

#define GBE1_PHY_YT8531_GMII_PHASE_1000M    0xC50
#define GBE1_PHY_YT8531_GMII_PHASE_100M     0xC90

/*
   ETH_PHY_SPEED_1G        = 0,
   ETH_PHY_SPEED_10M       = 2,
   ETH_PHY_SPEED_100M      = 3,
   ETH_PHY_SPEED_AUTONEG   = 4,
   ETH_PHY_SPEED_DEFAULT   = 5,

   Note:
     1. ETH_PHY_SPEED_1G 、ETH_PHY_SPEED_100M 、ETH_PHY_SPEED_10M
     When configuring this, it means setting phy to the fixed link mode, which requires support
     from the phy driver. Refer to the implementation of the phy driver.

     2. ETH_PHY_SPEED_DEFAULT
     When configuring this, The default speed configuration in lwipopts.h will be used.
 */
#define LINK_SPEED              ETH_PHY_SPEED_DEFAULT

#define TEST_GBE_COUNT          2

static struct netif lwip_netif_list[TEST_GBE_COUNT];

static struct eth_netif_cfg gbe_netif_list[TEST_GBE_COUNT] =
{
    {
        .eth_dev_id = ETH_GBE0_ID,
        .eth_mac_addr = {MAC0_ADDR0, MAC0_ADDR1, MAC0_ADDR2, MAC0_ADDR3, MAC0_ADDR4, MAC0_ADDR5},

        .eth_phy_addr = 4,
        .eth_phy_speed = LINK_SPEED,
        .eth_phy_phase_1000M = GBE0_PHY_YT8531_RGMII_PHASE_1000M,
        .eth_phy_phase_100M = GBE0_PHY_YT8531_RGMII_PHASE_100M,

        .netif   = &lwip_netif_list[0],
        .ip_addr  = ETH0_IP_ADDRESS,
        .net_mask = ETH0_NET_MASK,
        .gate_way = ETH0_GW_ADDRESS,
    },
    {
        .eth_dev_id = ETH_GBE1_ID,
        .eth_mac_addr = {MAC1_ADDR0, MAC1_ADDR1, MAC1_ADDR2, MAC1_ADDR3, MAC1_ADDR4, MAC1_ADDR5},

        .eth_phy_addr = 1,
        .eth_phy_speed = LINK_SPEED,
        .eth_phy_phase_1000M = GBE1_PHY_YT8531_GMII_PHASE_1000M,
        .eth_phy_phase_100M = GBE1_PHY_YT8531_GMII_PHASE_100M,

        .netif   = &lwip_netif_list[1],
        .ip_addr  = ETH1_IP_ADDRESS,
        .net_mask = ETH1_NET_MASK,
        .gate_way = ETH1_GW_ADDRESS,
    }
};

void udpserv(void *param);

void eth_init_thread(void *arg)
{
    /* Initialize the LwIP stack */
    tcpip_init(NULL, NULL);

    for (int i = 0; i < TEST_GBE_COUNT; i++)
    {
        eth_netif_config(&gbe_netif_list[i]);
        sys_thread_new("udpecho", udpserv, &lwip_netif_list[i], UDP_ECHO_THREAD_STACK_SIZE, UDP_ECHO_THREAD_PRIO);
    }

    vTaskDelete(NULL);

    while(1);
}

int main(void)
{
    AL_LOG(AL_LOG_LEVEL_INFO, "FreeRTOS LwIP multi eth udp echo example>>>\r\n");

    sys_thread_new("eth_init_thread", eth_init_thread, NULL, DEFAULT_THREAD_STACKSIZE, configMAX_PRIORITIES-2);

    vTaskStartScheduler();

    AL_LOG(AL_LOG_LEVEL_INFO, "OS should never run to here\r\n");

    while (1);
}