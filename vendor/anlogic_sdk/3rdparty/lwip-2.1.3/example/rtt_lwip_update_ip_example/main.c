/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "al_gbe_ethernetif.h"
#include "netif/ethernet.h"
#include "lwip/tcpip.h"
#include "lwip/inet.h"

#include <rtthread.h>
#include <rtconfig.h>

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

static struct netif lwip_netif;

static struct eth_netif_cfg gbe_netif_cfg =
{
    .eth_dev_id = GBE_DEV_ID,
    .eth_mac_addr = {MAC_ADDR0, MAC_ADDR1, MAC_ADDR2, MAC_ADDR3, MAC_ADDR4, MAC_ADDR5},

    .eth_phy_addr = ETH_PHY_ADDR,
    .eth_phy_speed = LINK_SPEED,
    .eth_phy_phase_1000M = YT8531_PHY_PHASE_1000M,
    .eth_phy_phase_100M = YT8531_PHY_PHASE_100M,

    .netif   = &lwip_netif,
    .ip_addr  = DEFAULT_IP_ADDRESS,
    .net_mask = DEFAULT_NET_MASK,
    .gate_way = DEFAULT_GW_ADDRESS,
};

int main()
{
    AL_LOG(AL_LOG_LEVEL_INFO, "RTThread LwIP update ip example>>>\r\n");
    struct rt_thread *thread;

    /* Initialize the LwIP stack */
    tcpip_init(NULL, NULL);

    eth_netif_config(&gbe_netif_cfg);

    /* suspend thread */
    thread = rt_thread_self();
    rt_thread_suspend(thread);

    return 0;
}

int lwip_ip_update(int argc, char **argv)
{
    int error;
    ip_addr_t ip_update;
    ip_addr_t netmask_update;
    ip_addr_t gw_update;

    if (argc < 4)
    {
        AL_LOG(AL_LOG_LEVEL_ERROR, "Too few parameters, The command is as follows:\r\n");
        AL_LOG(AL_LOG_LEVEL_ERROR, "IPUpdate 192.168.31.222 255.255.255.0 192.168.31.1\r\n");
        return 0;
    }

    error = inet_aton(argv[1], &ip_update);
    if (!error)
    {
        AL_LOG(AL_LOG_LEVEL_ERROR, "Invalid IP Address\r\n");
        return 0;
    }
    error = inet_aton(argv[2], &netmask_update);
    if (!error)
    {
        AL_LOG(AL_LOG_LEVEL_ERROR, "Invalid NetMask\r\n");
        return 0;
    }
    error = ip_addr_netmask_valid(&netmask_update);
    if (!error)
    {
        AL_LOG(AL_LOG_LEVEL_ERROR, "Invalid NetMask\r\n");
        return 0;
    }
    error = inet_aton(argv[3], &gw_update);
    if (!error)
    {
        AL_LOG(AL_LOG_LEVEL_ERROR, "Invalid GateWay\r\n");
        return 0;
    }

    netif_set_down(&lwip_netif);
    netif_set_addr(&lwip_netif, &ip_update, &netmask_update, &gw_update);
    netif_set_up(&lwip_netif);

    AL_LOG(AL_LOG_LEVEL_INFO, "LwIP IP Address update successfully\r\n");

    AL_LOG(AL_LOG_LEVEL_INFO, "Static IP  : %s\r\n", argv[1]);
    AL_LOG(AL_LOG_LEVEL_INFO, "Netmask    : %s\r\n", argv[2]);
    AL_LOG(AL_LOG_LEVEL_INFO, "Gateway    : %s\r\n", argv[3]);
    AL_LOG(AL_LOG_LEVEL_INFO, "Mac Address: %02x:%02x:%02x:%02x:%02x:%02x\r\n",
                                            lwip_netif.hwaddr[0],
                                            lwip_netif.hwaddr[1],
                                            lwip_netif.hwaddr[2],
                                            lwip_netif.hwaddr[3],
                                            lwip_netif.hwaddr[4],
                                            lwip_netif.hwaddr[5]);

    return 0;
}

MSH_CMD_EXPORT_ALIAS(lwip_ip_update, IPUpdate, IPUpdate IPAdddr NetMask GateWay);