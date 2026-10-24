
/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */


#include "al_gbe_ethernetif.h"

#include <rtthread.h>
#include "lwip/tcpip.h"
#include "lwip/timeouts.h"
#include <rtconfig.h>

#include <string.h>

#define TCP_CLIENT_IPERF_STACKSIZE          5120
#define TCP_CLIENT_IPERF_PRIO               ETH_INPUT_THREAD_PRIO


/* define MAC Address */
#define MAC_ADDR0               (0x64)
#define MAC_ADDR1               (0x00)
#define MAC_ADDR2               (0x6a)
#define MAC_ADDR3               (0x19)
#define MAC_ADDR4               (0x74)
#define MAC_ADDR5               (0x77)

/* define IP address、netmask and gateway */
#define DEFAULT_IP_ADDRESS      "192.168.31.10"
#define DEFAULT_NET_MASK        "255.255.255.0"
#define DEFAULT_GW_ADDRESS      "192.168.31.1"

/* define GBE device ID */
#define GBE_DEV_ID              ETH_GBE0_ID

/*
   This configuration requires reference to the CFG_CTRL_GBE register description,
   and Different Phy may have different phase configurations.

   Note:
   If configured to 0, the phase configuration in the phy driver file will be used,
   However, it is necessary to check whether the configuration in the phy driver is reasonable.
 */
#define YT8531_PHY_PHASE_1000M  0x621
#define YT8531_PHY_PHASE_100M   0x361

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
#define LINK_SPEED          ETH_PHY_SPEED_DEFAULT

/* Specify the phy address. If the phy address is 0, the eth controller will automatically detect it */
#define ETH_PHY_ADDR        0

extern struct netif gnetif;

static struct eth_netif_cfg gbe_netif_cfg =
{
    .eth_dev_id = GBE_DEV_ID,
    .eth_mac_addr = {MAC_ADDR0, MAC_ADDR1, MAC_ADDR2, MAC_ADDR3, MAC_ADDR4, MAC_ADDR5},

    .eth_phy_addr = ETH_PHY_ADDR,
    .eth_phy_speed = LINK_SPEED,
    .eth_phy_phase_1000M = YT8531_PHY_PHASE_1000M,
    .eth_phy_phase_100M = YT8531_PHY_PHASE_100M,

    .netif   = &gnetif,
    .ip_addr  = DEFAULT_IP_ADDRESS,
    .net_mask = DEFAULT_NET_MASK,
    .gate_way = DEFAULT_GW_ADDRESS,
};

extern void tcp_client_iperf(void);

int main(void)
{
    struct rt_thread *thread;
    rt_kprintf("RTT LwIP TCP client iperf start>>>\r\n");

    /* Initialize the LwIP stack */
    tcpip_init(NULL, NULL);

    eth_netif_config(&gbe_netif_cfg);

    sys_thread_new("client_iperf", (lwip_thread_fn)tcp_client_iperf, 0, TCP_CLIENT_IPERF_STACKSIZE, TCP_CLIENT_IPERF_PRIO);

    /* suspend thread */
    thread = rt_thread_self();
    rt_thread_suspend(thread);

    while (1);
}