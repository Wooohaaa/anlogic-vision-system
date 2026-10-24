/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "al_gbe_ethernetif.h"

#include "lwip/init.h"
#include "lwip/timeouts.h"
#include "netif/ethernet.h"

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

extern void udp_echoserver_init(struct netif *netif);

int main(void)
{
    int i;
    AL_LOG(AL_LOG_LEVEL_INFO, "LwIP multi eth udp echo example>>>\r\n");

    /* Initialize the LwIP stack */
    lwip_init();

    for (int i = 0; i < TEST_GBE_COUNT; i++)
    {
        eth_netif_config(&gbe_netif_list[i]);
        udp_echoserver_init(&lwip_netif_list[i]);
    }

    while (1)
    {
        for (i = 0; i < TEST_GBE_COUNT; i++)
        {
            ethernetif_input(&lwip_netif_list[i]);

            /* Handle timeouts */
            sys_check_timeouts();
        }

    }

    return 0;
}