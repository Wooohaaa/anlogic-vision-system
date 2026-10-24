/*
 * Copyright (c) 2001-2004 Swedish Institute of Computer Science.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification,
 * are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 * 3. The name of the author may not be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR IMPLIED
 * WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT
 * SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
 * OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
 * IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY
 * OF SUCH DAMAGE.
 *
 * This file is part of the lwIP TCP/IP stack.
 *
 * Author: Adam Dunkels <adam@sics.se>
 */

/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef __AL_GBE_ETHERNETIF_H_
#define __AL_GBE_ETHERNETIF_H_

#ifdef __cplusplus
extern "C" {
#endif

#include "al_hal.h"
#include "lwip/netif.h"
#include "netif/ethernet.h"

#ifdef HAVE_GBEPS_DRIVER

#if defined(GBE0PS_ENABLE) && defined(GBE1PS_ENABLE)
#define GBE_COUNT                   2
#else
#define GBE_COUNT                   1
#endif

#define TX_MAX_PBUF_CHAIN_COUNT     16

/*
   If it is defined as 1536, it will cause memory stampede,
   here it is defined as 1560, which can work normally.
   need check.
*/
#define ETH_RX_BUFFER_SIZE          (1600UL)

/* Maximum Ethernet payload size */
#define ETH_MAX_PAYLOAD             (1500UL)

#define GBE_MAC_ADDR0    (0x64)
#define GBE_MAC_ADDR1    (0x00)
#define GBE_MAC_ADDR2    (0x6a)
#define GBE_MAC_ADDR3    (0x19)
#define GBE_MAC_ADDR4    (0x74)
#define GBE_MAC_ADDR5    (0x7f)

#define IP_ADDR0        192
#define IP_ADDR1        168
#define IP_ADDR2        31
#define IP_ADDR3        222

#define GW_ADDR0        192
#define GW_ADDR1        168
#define GW_ADDR2        31
#define GW_ADDR3        1

#define NETMASK_ADDR0        255
#define NETMASK_ADDR1        255
#define NETMASK_ADDR2        255
#define NETMASK_ADDR3        0

#define _STR(x)         #x
#define STR(x)          _STR(x)

#define ETH_IP_ADDRESS  STR(IP_ADDR0) "." STR(IP_ADDR1) "." STR(IP_ADDR2) "." STR(IP_ADDR3)
#define ETH_NET_MASK    STR(NETMASK_ADDR0) "." STR(NETMASK_ADDR1) "." STR(NETMASK_ADDR2) "." STR(NETMASK_ADDR3)
#define ETH_GATE_WAY    STR(GW_ADDR0) "." STR(GW_ADDR1) "." STR(GW_ADDR2) "." STR(GW_ADDR3)

/* Currently, eth_phy_speed_enum needs to be consistent with AL_GBE_SpeedEnum */
typedef AL_GBE_SpeedEnum        eth_phy_speed_enum;
#define ETH_PHY_SPEED_1G        AL_GBE_SPEED_1G
#define ETH_PHY_SPEED_10M       AL_GBE_SPEED_10M
#define ETH_PHY_SPEED_100M      AL_GBE_SPEED_100M
#define ETH_PHY_SPEED_AUTONEG   AL_GBE_SPEED_AUTONEG
#define ETH_PHY_SPEED_DEFAULT   AL_GBE_SPEED_DEFAULT

typedef enum
{
    ETH_GBE0_ID         = 0,
    ETH_GBE1_ID         = 1,
} eth_dev_id_enum;

struct eth_netif_cfg
{
    eth_dev_id_enum eth_dev_id;
    AL_VOID        *eth_handle;
    AL_U8           eth_mac_addr[ETH_HWADDR_LEN];

    /*
      When two Ethernet controllers are used simultaneously, if the two PHyS are linked to one mdio bus,
      the driver cannot distinguish which phy each Ethernet corresponds to and needs to specify the phy address.
      If only one Ethernet controller is used and there is only one phy, the address can be configured as the
      broadcast address 0.
     */
    AL_U8 eth_phy_addr;

    eth_phy_speed_enum eth_phy_speed;

    /*
      This configuration requires reference to the CFG_CTRL_GBE register description,
      and Different Phy may have different phase configurations.

      Note:
      If configured to 0, the phase configuration in the phy driver file will be used,
      However, it is necessary to check whether the configuration in the phy driver is reasonable.
    */
    AL_U32 eth_phy_phase_1000M;
    AL_U32 eth_phy_phase_100M;

    struct netif *netif;
    char *ip_addr;
    char *net_mask;
    char *gate_way;
};

struct gbe_netif_cfg_info
{
    u8_t init_id;
    struct eth_netif_cfg eth_netif_cfg;
};

int eth_netif_config(struct eth_netif_cfg *eth_netif_cfg);
void netif_config(void);
void eth_link_detect(struct netif *netif);

#if NO_SYS
void ethernetif_input(struct netif *netif);
#endif

#if LWIP_PTP
#define PTP_EVENT_PORT    319
#define PTP_GENERAL_PORT  320

#if !NO_SYS

AL_S32 AlGbe_PtpGetRxTimeStamp(AL_GBE_TimeStampStruct *RxTimeStamp, const AL_U8 *PtpMsgHead);

AL_S32 AlGbe_PtpGetTxTimeStamp(AL_GBE_TimeStampStruct *TxTimeStamp);

#endif

#endif

#endif

#ifdef __cplusplus
}
#endif

#endif /* AL_GBE_ETHERNETIF_H */
