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


#include "al_gbe_ethernetif.h"
#include "al_hal.h"

#ifdef HAVE_GBEPS_DRIVER

#include "lwipopts.h"
#include "lwip/sys.h"
#include "lwip/inet.h"
#include "lwip/netif.h"
#include "netif/etharp.h"
#include "lwip/ip.h"
#include "lwip/udp.h"
#include "lwip/snmp.h"

#include <string.h>

/* Define those to better describe your network interface. */
#define IFNAME0 'A'
#define IFNAME1 'L'

#if !NO_SYS
#include "arch/sys_arch.h"
#include "lwip/sys.h"

#include "lwip/tcpip.h"

#if defined(RTOS_FREERTOS)
#define PHY_LINK_DETECT_THREAD_STACKSIZE        (3072/8)
#define PHY_LINK_DETECT_THREAD_PRIO             6

#elif defined(RTOS_RTTHREAD)
#define PHY_LINK_DETECT_THREAD_STACKSIZE        3072
#define PHY_LINK_DETECT_THREAD_PRIO             16

#endif

#ifdef RTOS_FREERTOS
extern volatile portBASE_TYPE xInsideISR;
#endif

#endif /* !NO_SYS */

typedef struct
{
#if !NO_SYS
    sys_sem_t gbe_rx_done_sem;
    sys_thread_t eth_input_handle;
    sys_thread_t phy_link_handle;
#endif

    u8_t gbe_rx_buff[AL_GBE_RX_DESC_CNT][ETH_RX_BUFFER_SIZE] CACHE_LINE_ALIGN;
    u8_t gbe_tx_buff[AL_GBE_TX_DESC_CNT][ETH_RX_BUFFER_SIZE] CACHE_LINE_ALIGN;

    /* Tx config, Configure the Tx descriptor function according to this */
    AL_GBE_TxDescConfigStruct tx_config;
} gbe_netif_desc;

gbe_netif_desc gbe_netif_list[GBE_COUNT];

/* Tx and Rx descriptors define, AL_GBE_RX_DESC_CNT and AL_GBE_TX_DESC_CNT at least four */
AL_GBE_DMADescStruct gbe_dma_rx_desc_list[GBE_COUNT][AL_GBE_RX_DESC_CNT] __attribute__((section(".noncacheable"))) CACHE_LINE_ALIGN;
AL_GBE_DMADescStruct gbe_dma_tx_desc_list[GBE_COUNT][AL_GBE_TX_DESC_CNT] __attribute__((section(".noncacheable"))) CACHE_LINE_ALIGN;

static volatile u8_t current_init_id = 0;
struct gbe_netif_cfg_info gbe_netif_cfg_list[GBE_COUNT] = {0};

/* Netif for lwip */
struct netif gnetif;

void eth_link_detect(struct netif *netif);

#if (LWIP_PTP) && (!NO_SYS)

#define PTP_HEADER_LENGTH       34

sys_mbox_t ptp_tx_mbox;
sys_mbox_t ptp_rx_mbox;

struct gbe_ptp_time_stamp
{
    AL_GBE_TimeStampStruct time_stamp;
    u8_t ptp_msg_head[PTP_HEADER_LENGTH];
};

AL_VOID AlGbe_PtpStoreTxTimeStamp(const AL_GBE_TimeStampStruct *tx_time_stamp)
{
    err_t ret;

    AL_GBE_TimeStampStruct *time_stamp = mem_calloc(1, sizeof(AL_GBE_TimeStampStruct));
    memcpy(time_stamp, tx_time_stamp, sizeof(AL_GBE_TimeStampStruct));

    ret = sys_mbox_trypost(&ptp_tx_mbox, time_stamp);
    if (ret != ERR_OK)
    {
        mem_free(time_stamp);
        AL_LOG(AL_LOG_LEVEL_ERROR, "AlGbe_PtpStoreTxTimeStamp failed\r\n");
    }

}

AL_S32 AlGbe_PtpGetTxTimeStamp(AL_GBE_TimeStampStruct *tx_time_stamp)
{
    AL_S32 ret;

    AL_GBE_TimeStampStruct *time_stamp;

    ret = sys_arch_mbox_fetch(&ptp_tx_mbox, (void **)&time_stamp, 0);
    if (ret == SYS_ARCH_TIMEOUT)
    {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AlGbe_PtpGetTxTimeStamp failed\r\n");
        return AL_GBE_DESC_TX_TIMESTAMP_STATUS_ERROR;
    }

    memcpy(tx_time_stamp, time_stamp, sizeof(AL_GBE_TimeStampStruct));
    mem_free(time_stamp);

    return AL_OK;
}

AL_VOID AlGbe_PtpStoreRxTimeStamp(const AL_GBE_TimeStampStruct *rx_time_stamp, const AL_U8 *ptp_msg)
{
    err_t ret;

    struct gbe_ptp_time_stamp *ptp_time_stamp = mem_calloc(1, sizeof(struct gbe_ptp_time_stamp));

    memcpy(&(ptp_time_stamp->time_stamp), rx_time_stamp, sizeof(AL_GBE_TimeStampStruct));
    memcpy(ptp_time_stamp->ptp_msg_head, ptp_msg+SIZEOF_ETH_HDR+IP_HLEN+UDP_HLEN, PTP_HEADER_LENGTH);

    ret = sys_mbox_trypost(&ptp_rx_mbox, ptp_time_stamp);
    if (ret != ERR_OK)
    {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AlGbe_PtpStoreRxTimeStamp failed\r\n");
        mem_free(ptp_time_stamp);
    }

}

AL_S32 AlGbe_PtpGetRxTimeStamp(AL_GBE_TimeStampStruct *rx_time_stamp, const AL_U8 *ptp_msg_head)
{
    AL_S32 ret;

    struct gbe_ptp_time_stamp *ptp_time_stamp;

    ret = sys_arch_mbox_tryfetch(&ptp_rx_mbox, (void **)&ptp_time_stamp);
    if (ret != ERR_OK)
    {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AlGbe_PtpGetRxTimeStamp failed\r\n");
        return AL_GBE_DESC_TX_TIMESTAMP_STATUS_ERROR;
    }

    if (memcmp(ptp_time_stamp->ptp_msg_head, ptp_msg_head, PTP_HEADER_LENGTH))
    {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AlGbe_PtpGetRxTimeStamp failed\r\n");
        mem_free(ptp_time_stamp);
        return AL_GBE_DESC_TX_TIMESTAMP_STATUS_ERROR;
    }

    memcpy(rx_time_stamp, &(ptp_time_stamp->time_stamp), sizeof(AL_GBE_TimeStampStruct));
    mem_free(ptp_time_stamp);

    return AL_OK;
}
#endif /* (LWIP_PTP) && (!NO_SYS) */

#if LWIP_PTP

static void low_level_ptp_init(AL_GBE_HalStruct *gbe_handle)
{
    AL_GBE_PtpConfigStruct ptp_config =
    {
        .UpdateMethod = AL_GBE_PTP_FINE_UPDATE,
    };

#if !NO_SYS

    sys_mbox_new(&ptp_tx_mbox, 64);
    sys_mbox_new(&ptp_rx_mbox, 64);
#endif

    AlGbe_Hal_PtpInit(gbe_handle, &ptp_config);
}

AL_BOOL AlGbe_IsPtpPacket(struct pbuf *p)
{
    const struct ip_hdr *iphdr;
    u16_t iphdr_hlen;
    struct udp_hdr *udphdr;
    u16_t src_port, dest_port;

    iphdr = (struct ip_hdr *)((AL_U8 *)p->payload + SIZEOF_ETH_HDR);

    if ((IPH_PROTO(iphdr)) != IP_PROTO_UDP)
    {
        return AL_FALSE;
    }

    /* obtain IP header length in bytes */
    iphdr_hlen = IPH_HL_BYTES(iphdr);

    udphdr = (struct udp_hdr *)((AL_U8 *)p->payload + SIZEOF_ETH_HDR + iphdr_hlen);

    src_port = lwip_ntohs(udphdr->src);
    dest_port = lwip_ntohs(udphdr->dest);

    if (((src_port == PTP_EVENT_PORT) && (dest_port == PTP_EVENT_PORT)) ||
        ((src_port == PTP_GENERAL_PORT) && (dest_port == PTP_GENERAL_PORT)))
    {
        return AL_TRUE;
    }

    return AL_FALSE;
}

#endif /* LWIP_PTP */

static struct pbuf *low_level_input(struct netif *netif)
{
    struct pbuf *p = NULL;
    struct pbuf *q = NULL;
    AL_GBE_BufferStruct rx_buff;
    uint32_t framelength = 0;
    uint32_t l = 0;
    AL_GBE_HalStruct *gbe_handle = (((struct gbe_netif_cfg_info *)netif->state)->eth_netif_cfg).eth_handle;

#if LWIP_PTP
    gbe_handle->Dev.RxDescList.RxTimeStamp.TimeStampHigh = 0;
    gbe_handle->Dev.RxDescList.RxTimeStamp.TimeStampLow = 0;
#endif /* LWIP_PTP */

    if (AlGbe_Hal_GetRxDataBuffer(gbe_handle, &rx_buff) == AL_OK)
    {
        AlGbe_Hal_GetRxDataLength(gbe_handle, &framelength);

        /* Build Rx descriptor to be ready for next data reception */
        AlGbe_Hal_BuildRxDescriptors(gbe_handle);

        AL_UINTPTR buffer_align = (AL_UINTPTR)GBE_CACHE_ALIGN_MEMORY(rx_buff.Buffer);
        AL_UINTPTR buffer_len_align = GBE_CACHE_ALIGN_SIZE(framelength);

        AlCache_InvalidateDcacheRange((AL_UINTPTR)buffer_align, (AL_UINTPTR)(buffer_align + buffer_len_align));

        p = pbuf_alloc(PBUF_RAW, PBUF_POOL_BUFSIZE, PBUF_POOL);

        if (p != NULL)
        {
            for (q = p, l = 0; q != NULL; q = q->next)
            {
                memcpy((AL_U8 *)q->payload, (AL_U8 *)&rx_buff.Buffer[l], q->len);
                l = l + q->len;
            }
        }

#if LWIP_PTP
        if (gbe_handle->Dev.RxDescList.RxTimeStamp.TimeStampHigh != 0 &&
            gbe_handle->Dev.RxDescList.RxTimeStamp.TimeStampLow != 0)
        {
#if NO_SYS
                p->time_sec = gbe_handle->Dev.RxDescList.RxTimeStamp.TimeStampHigh;
                p->time_nsec = gbe_handle->Dev.RxDescList.RxTimeStamp.TimeStampLow;
#else
                AlGbe_PtpStoreRxTimeStamp(&gbe_handle->Dev.RxDescList.RxTimeStamp, p->payload);
#endif /* NO_SYS */
        }

#endif /* LWIP_PTP */
    }

    return p;
}


void AlGbe_RxDoneCallback(void *CallbackRef)
{
    gbe_netif_desc *gbe_netif = (gbe_netif_desc *)(((AL_GBE_HalStruct *)CallbackRef)->Data);

#if !NO_SYS
#if defined(RTOS_RTTHREAD)
    rt_interrupt_enter();
#elif defined(RTOS_FREERTOS)
    xInsideISR++;
#endif

    sys_sem_signal(&gbe_netif->gbe_rx_done_sem);

#if defined(RTOS_RTTHREAD)
    rt_interrupt_leave();
#elif defined(RTOS_FREERTOS)
    xInsideISR--;
#endif

#else

    (AL_VOID)gbe_netif;

#endif
}

void AlGbe_TxFreeCallback(void *buff)
{
    pbuf_free((struct pbuf *)buff);
}

#if !NO_SYS
/**
 * This function should do the actual transmission of the packet. The packet is
 * contained in the pbuf that is passed to the function. This pbuf
 * might be chained.
 *
 * @param netif the lwip network interface structure for this ethernetif
 * @param p the MAC packet to send (e.g. IP packet including MAC addresses and type)
 * @return ERR_OK if the packet was sent, or ERR_IF if the packet was unable to be sent
 *
 * @note ERR_OK means the packet was sent (but not necessarily transmit complete),
 * and ERR_IF means the packet has more chained buffers than what the interface supports.
 */
static err_t low_level_output(struct netif *netif, struct pbuf *p)
{
    uint32_t i = 0U;
    struct pbuf *q = NULL;
    err_t errval = ERR_OK;
    AL_GBE_HalStruct *gbe_handle = (((struct gbe_netif_cfg_info *)netif->state)->eth_netif_cfg).eth_handle;
    u8_t index = gbe_handle->Dev.InitId;

    AL_GBE_BufferStruct tx_buffer[TX_MAX_PBUF_CHAIN_COUNT];
    memset(tx_buffer, 0, TX_MAX_PBUF_CHAIN_COUNT*sizeof(AL_GBE_BufferStruct));

    for (q = p; q != NULL; q = q->next)
    {
        if (i >= TX_MAX_PBUF_CHAIN_COUNT)
        {
            AL_LOG(AL_LOG_LEVEL_ERROR, "low_level_output TX_MAX_PBUF_CHAIN_COUNT\r\n");
            return ERR_IF;
        }

        tx_buffer[i].Buffer = q->payload;
        tx_buffer[i].Len = q->len;

        if (i > 0)
        {
            tx_buffer[i-1].next = &tx_buffer[i];
        }

        if (q->next == NULL)
        {
            tx_buffer[i].next = NULL;
        }

        i++;
    }

    gbe_netif_list[index].tx_config.Length = p->tot_len;
    gbe_netif_list[index].tx_config.TxBuffer = tx_buffer;
    gbe_netif_list[index].tx_config.pData = p;

#if LWIP_PTP
    gbe_netif_list[index].tx_config.IsPtpMsg = AlGbe_IsPtpPacket(p);
#endif

    AlGbe_Hal_Transmit(gbe_handle, &gbe_netif_list[index].tx_config);

#if LWIP_PTP
    if (gbe_netif_list[index].tx_config.IsPtpMsg == AL_TRUE) {
        AlGbe_PtpStoreTxTimeStamp(&gbe_handle->Dev.TxTimeStamp);
    }
#endif

    return errval;
}

/**
 * This task should be signaled when a receive packet is ready to be read
 * from the interface.
 *
 * @param argument the lwip network interface structure for this ethernetif
 */
static void ethernetif_input(void *parameter)
{
    struct netif *netif = (struct netif *)parameter;
    struct pbuf *p;

    AL_GBE_HalStruct *gbe_handle = (((struct gbe_netif_cfg_info *)netif->state)->eth_netif_cfg).eth_handle;
    u8_t index = gbe_handle->Dev.InitId;

    for ( ;; )
    {
        if ((sys_arch_sem_wait(&gbe_netif_list[index].gbe_rx_done_sem, 0)) != SYS_ARCH_TIMEOUT)
        {
            do
            {
                p = low_level_input( netif );
                if (p != NULL)
                {
                    if (netif->input( p, netif) != ERR_OK )
                    {
                        LWIP_DEBUGF(NETIF_DEBUG, ("ethernetif_input: IP input error\n"));
                        pbuf_free(p);
                    }
                }

            } while(p != NULL);
        }
    }
}


#else

void ethernetif_input(struct netif *netif)
{
  struct pbuf *p = NULL;

    do
    {
        p = low_level_input( netif );
        if (p != NULL)
        {
            if (netif->input( p, netif) != ERR_OK )
            {
                pbuf_free(p);
            }
        }

    } while(p != NULL);
}

static err_t low_level_output(struct netif *netif, struct pbuf *p)
{
    uint32_t i = 0U;
    struct pbuf *q = NULL;
    err_t errval = ERR_OK;
    AL_GBE_HalStruct *gbe_handle = (((struct gbe_netif_cfg_info *)netif->state)->eth_netif_cfg).eth_handle;
    u8_t index = gbe_handle->Dev.InitId;

    AL_GBE_BufferStruct tx_buffer[TX_MAX_PBUF_CHAIN_COUNT];
    memset(tx_buffer, 0, TX_MAX_PBUF_CHAIN_COUNT*sizeof(AL_GBE_BufferStruct));

    for (q = p; q != NULL; q = q->next)
    {
        if(i >= TX_MAX_PBUF_CHAIN_COUNT)
        {
            AL_LOG(AL_LOG_LEVEL_ERROR, "low_level_output TX_MAX_PBUF_CHAIN_COUNT\r\n");
            return ERR_IF;
        }

        tx_buffer[i].Buffer = q->payload;
        tx_buffer[i].Len = q->len;

        if(i > 0)
        {
            tx_buffer[i-1].next = &tx_buffer[i];
        }

        if(q->next == NULL)
        {
            tx_buffer[i].next = NULL;
        }

        i++;
    }

    gbe_netif_list[index].tx_config.Length = p->tot_len;
    gbe_netif_list[index].tx_config.TxBuffer = tx_buffer;
    gbe_netif_list[index].tx_config.pData = p;

#if LWIP_PTP
    gbe_netif_list[index].tx_config.IsPtpMsg = AlGbe_IsPtpPacket(p);
#endif

    AlGbe_Hal_Transmit(gbe_handle, &gbe_netif_list[index].tx_config);

#if LWIP_PTP
    if (gbe_netif_list[index].tx_config.IsPtpMsg == AL_TRUE) {
        p->time_sec = gbe_handle->Dev.TxTimeStamp.TimeStampHigh;
        p->time_nsec = gbe_handle->Dev.TxTimeStamp.TimeStampLow;
    }
#endif

    return errval;
}

#endif /* !NO_SYS */

void eth_link_detect(struct netif *netif)
{
    AL_BOOL link_status;
    static AL_BOOL last_link_status = AL_TRUE;
    AL_U8 speed;
    AL_U8 duplex;

    struct eth_netif_cfg *eth_netif_cfg = &(((struct gbe_netif_cfg_info *)(netif->state))->eth_netif_cfg);
    AL_GBE_HalStruct *gbe_handle = eth_netif_cfg->eth_handle;

    AlGbe_GetPhyLinkStatus(&gbe_handle->Dev.PhyDev, &link_status);
    if ((link_status == AL_FALSE) && (last_link_status == AL_TRUE))
    {
        last_link_status = link_status;
        netif_set_link_down(netif);
        netif_set_down(netif);
        AL_LOG(AL_LOG_LEVEL_ERROR, "AlGbe Device %d phy link down\r\n", eth_netif_cfg->eth_dev_id);
        return ;
    }
    else if ((link_status == AL_FALSE) && (last_link_status == AL_FALSE))
    {
        last_link_status = link_status;
        return ;
    }

    AlGbe_GetPhyLinkSpeedDuplex(&gbe_handle->Dev.PhyDev, &speed, &duplex);

    if (last_link_status == AL_FALSE)
    {

        if (PHY_SPEED_10M == speed)
        {
            gbe_handle->Dev.MacDmaConfig.Speed = AL_GBE_SPEED_10M;
            AL_LOG(AL_LOG_LEVEL_INFO, "AlGbe Device %d phy link up - 10Mbps/%s\r\n", eth_netif_cfg->eth_dev_id,
                                    PHY_FULL_DUPLEX == duplex ? "Full" : "HalfFull");
        }
        else if (PHY_SPEED_100M == speed)
        {
            gbe_handle->Dev.MacDmaConfig.Speed = AL_GBE_SPEED_100M;
            AL_LOG(AL_LOG_LEVEL_INFO, "AlGbe Device %d phy link up - 100Mbps/%s\r\n", eth_netif_cfg->eth_dev_id,
                                    PHY_FULL_DUPLEX == duplex ? "Full" : "HalfFull");
        }
        else
        {
            gbe_handle->Dev.MacDmaConfig.Speed = AL_GBE_SPEED_1G;
            AL_LOG(AL_LOG_LEVEL_INFO, "AlGbe Device %d phy link up - 1Gbps/%s\r\n", eth_netif_cfg->eth_dev_id,
                                    PHY_FULL_DUPLEX == duplex ? "Full" : "HalfFull");
        }

        if (PHY_FULL_DUPLEX == duplex)
        {
            gbe_handle->Dev.MacDmaConfig.DuplexMode = AL_GBE_FULL_DUPLEX_MODE;
        }
        else
        {
            gbe_handle->Dev.MacDmaConfig.DuplexMode = AL_GBE_HALF_DUPLEX_MODE;
        }

        AlGbe_Hal_ConfigDuplexAndSpeed(gbe_handle);

        netif_set_up(netif);
        netif_set_link_up(netif);

    }

    last_link_status = link_status;
}

void eth_phy_link_detect(struct netif *netif)
{
    AL_BOOL link_status;
    AL_BOOL last_link_status = AL_TRUE;
    AL_U8 speed;
    AL_U8 duplex;

    struct eth_netif_cfg *eth_netif_cfg = &(((struct gbe_netif_cfg_info *)(netif->state))->eth_netif_cfg);
    AL_GBE_HalStruct *gbe_handle = eth_netif_cfg->eth_handle;

    while (1)
    {
#if !NO_SYS
        sys_msleep(1000);
#endif

        AlGbe_GetPhyLinkStatus(&gbe_handle->Dev.PhyDev, &link_status);
        if ((link_status == AL_FALSE) && (last_link_status == AL_TRUE))
        {
            last_link_status = link_status;
            netif_set_link_down(netif);
            netif_set_down(netif);
            AL_LOG(AL_LOG_LEVEL_ERROR, "AlGbe Device %d phy link down\r\n", eth_netif_cfg->eth_dev_id);
            continue;
        }
        else if ((link_status == AL_FALSE) && (last_link_status == AL_FALSE))
        {
            last_link_status = link_status;
            continue;
        }

        AlGbe_GetPhyLinkSpeedDuplex(&gbe_handle->Dev.PhyDev, &speed, &duplex);

        if (last_link_status == AL_FALSE)
        {

            if (PHY_SPEED_10M == speed)
            {
                gbe_handle->Dev.MacDmaConfig.Speed = AL_GBE_SPEED_10M;
                AL_LOG(AL_LOG_LEVEL_INFO, "AlGbe Device %d phy link up - 10Mbps/%s\r\n", eth_netif_cfg->eth_dev_id,
                                        PHY_FULL_DUPLEX == duplex ? "Full" : "HalfFull");
            }
            else if (PHY_SPEED_100M == speed)
            {
                gbe_handle->Dev.MacDmaConfig.Speed = AL_GBE_SPEED_100M;
                AL_LOG(AL_LOG_LEVEL_INFO, "AlGbe Device %d phy link up - 100Mbps/%s\r\n", eth_netif_cfg->eth_dev_id,
                                        PHY_FULL_DUPLEX == duplex ? "Full" : "HalfFull");
            }
            else
            {
                gbe_handle->Dev.MacDmaConfig.Speed = AL_GBE_SPEED_1G;
                AL_LOG(AL_LOG_LEVEL_INFO, "AlGbe Device %d phy link up - 1Gbps/%s\r\n", eth_netif_cfg->eth_dev_id,
                                        PHY_FULL_DUPLEX == duplex ? "Full" : "HalfFull");
            }

            if (PHY_FULL_DUPLEX == duplex)
            {
                gbe_handle->Dev.MacDmaConfig.DuplexMode = AL_GBE_FULL_DUPLEX_MODE;
            }
            else
            {
                gbe_handle->Dev.MacDmaConfig.DuplexMode = AL_GBE_HALF_DUPLEX_MODE;
            }

            AlGbe_Hal_ConfigDuplexAndSpeed(gbe_handle);

            netif_set_up(netif);
            netif_set_link_up(netif);

        }

        last_link_status = link_status;
    }
}

err_t low_level_phy_init(AL_GBE_HalStruct *gbe_handle, struct netif *netif, AL_GBE_MacDmaConfigStruct *mac_dma_config)
{
    AL_S32 ret;
    AL_BOOL link_status;
    AL_U8 speed;
    AL_U8 duplex;
    AL_U32 eth_dev_id = gbe_handle->Dev.HwConfig.DeviceId;

    struct eth_netif_cfg *eth_netif_cfg = &((struct gbe_netif_cfg_info *)(netif->state))->eth_netif_cfg;
    gbe_handle->Dev.PhyDev.PhyAddr = eth_netif_cfg->eth_phy_addr;

    ret = AlGbe_DetectPhy(gbe_handle);
    if (ret != 0)
    {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AlGbe_Hal_DetectPhy failed\r\n");
        return ERR_IF;
    }

    /* Initialize the ETH PHY */
    AlGbe_PhyInit(&gbe_handle->Dev.PhyDev);

    if (gbe_handle->Dev.MacDmaConfig.Speed == AL_GBE_SPEED_AUTONEG)
    {

        AL_LOG(AL_LOG_LEVEL_INFO, "AlGbe Device %d get phy link status...\r\n", eth_dev_id);
        ret = AlGbe_GetPhyLinkStatus(&gbe_handle->Dev.PhyDev, &link_status);
        if ((ret != 0) || (link_status != AL_TRUE))
        {
            netif_set_link_down(netif);
            netif_set_down(netif);
            AL_LOG(AL_LOG_LEVEL_ERROR, "AlGbe Device %d phy link down\r\n", eth_dev_id);
            return ERR_IF;
        }

        ret = AlGbe_GetPhyLinkSpeedDuplex(&gbe_handle->Dev.PhyDev, &speed, &duplex);
        if (ret != 0)
        {
            netif_set_link_down(netif);
            netif_set_down(netif);
            AL_LOG(AL_LOG_LEVEL_ERROR, "AlGbe Device %d phy link down\r\n", eth_dev_id);
            return ERR_IF;
        }

        if (PHY_SPEED_10M == speed)
        {
            gbe_handle->Dev.MacDmaConfig.Speed = AL_GBE_SPEED_10M;
            AL_LOG(AL_LOG_LEVEL_INFO, "AlGbe Device %d phy link up - 10Mbps/%s\r\n", eth_dev_id,
                                      PHY_FULL_DUPLEX == duplex ? "Full" : "HalfFull");
        }
        else if (PHY_SPEED_100M == speed)
        {
            gbe_handle->Dev.MacDmaConfig.Speed = AL_GBE_SPEED_100M;
            AL_LOG(AL_LOG_LEVEL_INFO, "AlGbe Device %d phy link up - 100Mbps/%s\r\n", eth_dev_id,
                                      PHY_FULL_DUPLEX == duplex ? "Full" : "HalfFull");
        }
        else
        {
            gbe_handle->Dev.MacDmaConfig.Speed = AL_GBE_SPEED_1G;
            AL_LOG(AL_LOG_LEVEL_INFO, "AlGbe Device %d phy link up - 1Gbps/%s\r\n", eth_dev_id,
                                      PHY_FULL_DUPLEX == duplex ? "Full" : "HalfFull");
        }

        if (PHY_FULL_DUPLEX == duplex)
        {
            gbe_handle->Dev.MacDmaConfig.DuplexMode = AL_GBE_FULL_DUPLEX_MODE;
        }
        else
        {
            gbe_handle->Dev.MacDmaConfig.DuplexMode = AL_GBE_HALF_DUPLEX_MODE;
        }

        AlGbe_Hal_ConfigDuplexAndSpeed(gbe_handle);

    }
    else
    {
        AL_LOG(AL_LOG_LEVEL_INFO, "AlGbe phy fix link success\r\n");
        AlGbe_Hal_ConfigDuplexAndSpeed(gbe_handle);
    }

    return ERR_OK;
}

err_t low_level_init(struct netif *netif)
{
    AL_S32 ret;
    AL_GBE_InitStruct init_config;
    AL_GBE_MacDmaConfigStruct mac_dma_config;
    AL_GBE_HalStruct *gbe_handle;

    struct eth_netif_cfg *eth_netif_cfg = &((struct gbe_netif_cfg_info *)(netif->state))->eth_netif_cfg;
    AL_S32 eth_dev_id = eth_netif_cfg->eth_dev_id;
    u8_t init_id = ((struct gbe_netif_cfg_info *)(netif->state))->init_id;

    memset(&init_config, 0, sizeof(init_config));
    memset(&mac_dma_config, 0, sizeof(mac_dma_config));

    /* Initialize Gbe driver first */
    init_config.MacAddr[0] = eth_netif_cfg->eth_mac_addr[0];
    init_config.MacAddr[1] = eth_netif_cfg->eth_mac_addr[1];
    init_config.MacAddr[2] = eth_netif_cfg->eth_mac_addr[2];
    init_config.MacAddr[3] = eth_netif_cfg->eth_mac_addr[3];
    init_config.MacAddr[4] = eth_netif_cfg->eth_mac_addr[4];
    init_config.MacAddr[5] = eth_netif_cfg->eth_mac_addr[5];

    init_config.RxDescList = gbe_dma_rx_desc_list[init_id];
    init_config.TxDescList = gbe_dma_tx_desc_list[init_id];
    init_config.RxBuffLen = ETH_RX_BUFFER_SIZE;

    init_config.MediaInterface = AL_GBE_RGMII_MODE;

#if defined (PSGBE0_INTERFACE_TYPE)
    if (eth_dev_id == 0)
    {
        if (PSGBE0_INTERFACE_TYPE == 0)
        {
            init_config.MediaInterface = AL_GBE_RGMII_MODE;
        }
        else if (PSGBE0_INTERFACE_TYPE == 1)
        {
            init_config.MediaInterface = AL_GBE_GMII_MODE;
        }
        else if (PSGBE0_INTERFACE_TYPE == 2) {
            init_config.MediaInterface = AL_GBE_RMII_MODE;
        }
        else
        {
            init_config.MediaInterface = AL_GBE_MII_MODE;
        }

    }
#endif /* defined (PSGBE0_INTERFACE_TYPE) */

#if defined (PSGBE1_INTERFACE_TYPE)
    if (eth_dev_id == 1)
    {
        if (PSGBE1_INTERFACE_TYPE == 0)
        {
            init_config.MediaInterface = AL_GBE_RGMII_MODE;
        }
        else if (PSGBE1_INTERFACE_TYPE == 1)
        {
            init_config.MediaInterface = AL_GBE_GMII_MODE;
        }
        else if (PSGBE1_INTERFACE_TYPE == 2)
        {
            init_config.MediaInterface = AL_GBE_RMII_MODE;
        }
        else
        {
            init_config.MediaInterface = AL_GBE_MII_MODE;
        }

    }

#endif /* defined (PSGBE1_INTERFACE_TYPE) */

    init_config.GbePhyPhase1000M = eth_netif_cfg->eth_phy_phase_1000M;
    init_config.GbePhyPhase100M = eth_netif_cfg->eth_phy_phase_100M;

    mac_dma_config.DuplexMode = AL_GBE_FULL_DUPLEX_MODE;

#if defined (GBE_SPEED_AUTONEG)
    mac_dma_config.Speed = AL_GBE_SPEED_AUTONEG;
#elif defined (GBE_SPEED_1G)
    mac_dma_config.Speed = AL_GBE_SPEED_1G;
#elif defined (GBE_SPEED_100M)
    mac_dma_config.Speed = AL_GBE_SPEED_100M;
#elif defined (GBE_SPEED_10M)
    mac_dma_config.Speed = AL_GBE_SPEED_10M;
#else
    mac_dma_config.Speed = AL_GBE_SPEED_AUTONEG;
#endif /* GBE_SPEED_AUTONEG */

    if (eth_netif_cfg->eth_phy_speed != ETH_PHY_SPEED_DEFAULT)
    {
        mac_dma_config.Speed = eth_netif_cfg->eth_phy_speed;
    }

    ret = AlGbe_Hal_Init(&gbe_handle, eth_dev_id, &init_config, &mac_dma_config, AL_NULL);
    if (ret != AL_OK)
    {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AlGbe_Hal_Init failed\r\n");
        return ERR_IF;
    }

    /* Use static buffer to config tx/rx descriptor buffer */
    ret = AlGbe_Hal_ConfigRxDescBuffer(gbe_handle, (AL_U8 *)(gbe_netif_list[init_id].gbe_rx_buff), AL_GBE_RX_DESC_CNT, ETH_RX_BUFFER_SIZE);
    if (ret != AL_OK)
    {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AlGbe_Hal_ConfigRxDescBuffer failed\r\n");
        return ERR_IF;
    }
    ret = AlGbe_Hal_ConfigTxDescBuffer(gbe_handle, (AL_U8 *)(gbe_netif_list[init_id].gbe_tx_buff), AL_GBE_TX_DESC_CNT, ETH_RX_BUFFER_SIZE);
    if (ret != AL_OK)
    {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AlGbe_Hal_ConfigTxDescBuffer failed\r\n");
        return ERR_IF;
    }

    AlGbe_Hal_RegisterTxFreeCallBack(gbe_handle, AlGbe_TxFreeCallback);
    AlGbe_Hal_RegisterIntrHandlerCallBack(gbe_handle, AL_GBE_INTR_RX_COMPLETE, AlGbe_RxDoneCallback);

    AlGbe_Hal_SetData(gbe_handle, &gbe_netif_list[init_id]);
    eth_netif_cfg->eth_handle = gbe_handle;
    gbe_handle->Dev.InitId = init_id;

    /* set MAC hardware address length */
    netif->hwaddr_len = ETH_HWADDR_LEN;

    /* set MAC hardware address */
    netif->hwaddr[0] = init_config.MacAddr[0];
    netif->hwaddr[1] = init_config.MacAddr[1];
    netif->hwaddr[2] = init_config.MacAddr[2];
    netif->hwaddr[3] = init_config.MacAddr[3];
    netif->hwaddr[4] = init_config.MacAddr[4];
    netif->hwaddr[5] = init_config.MacAddr[5];

    /* maximum transfer unit */
    netif->mtu = ETH_MAX_PAYLOAD;

    /* device capabilities */
    /* don't set NETIF_FLAG_ETHARP if this device is not an ethernet one */
    netif->flags |= NETIF_FLAG_BROADCAST | NETIF_FLAG_ETHARP;

#if LWIP_PTP
    netif->flags |= NETIF_FLAG_IGMP;
#endif

    /* Set Tx packet config common parameters */
    memset(&gbe_netif_list[init_id].tx_config, 0 , sizeof(AL_GBE_TxDescConfigStruct));
    gbe_netif_list[init_id].tx_config.Attributes = AL_GBE_TX_PACKETS_FEATURES_CSUM | AL_GBE_TX_PACKETS_FEATURES_CRCPAD;
#if LWIP_PTP
    gbe_netif_list[init_id].tx_config.Attributes |= AL_GBE_TX_PACKETS_FEATURES_TTSE;
#endif

#if CHECKSUM_BY_HARDWARE
    gbe_netif_list[init_id].tx_config.ChecksumCtrl = AL_GBE_CHECKSUM_IPHDR_PAYLOAD_INSERT_PHDR_CALC;
#endif
    gbe_netif_list[init_id].tx_config.CRCPadCtrl = AL_GBE_CRC_PAD_INSERT;

#if !NO_SYS
    /* create a binary semaphore used for Tx and Rx done */
    ret = sys_sem_new(&gbe_netif_list[init_id].gbe_rx_done_sem, 0);
    if (ret != ERR_OK)
    {
      AL_LOG(AL_LOG_LEVEL_ERROR, "sys_sem_new gbe_rx_done_sem failed\r\n");
      return ret;
    }

    gbe_netif_list[init_id].eth_input_handle = sys_thread_new(ETH_INPUT_THREAD_NAME, ethernetif_input, netif,
                                                ETH_INPUT_THREAD_STACKSIZE, ETH_INPUT_THREAD_PRIO);
    if (gbe_netif_list[init_id].eth_input_handle == NULL)
    {
        AL_LOG(AL_LOG_LEVEL_ERROR, "sys_thread_new eth_input_handle failed\r\n");
    }
#endif /* !NO_SYS */

    ret = low_level_phy_init(gbe_handle, netif, &mac_dma_config);
    if (ret == ERR_OK)
    {
        netif_set_up(netif);
        netif_set_link_up(netif);
    }

#if LWIP_PTP
    low_level_ptp_init(gbe_handle);
#endif

#if NO_SYS
    AlGbe_Hal_StartMacDma(gbe_handle);
#else

#if defined(RTOS_RTTHREAD)
    gbe_netif_list[init_id].phy_link_handle = sys_thread_new("PHY Link detect", (lwip_thread_fn)eth_phy_link_detect, netif,
                                            PHY_LINK_DETECT_THREAD_STACKSIZE, PHY_LINK_DETECT_THREAD_PRIO + eth_dev_id);
#elif defined(RTOS_FREERTOS)
    gbe_netif_list[init_id].phy_link_handle = sys_thread_new("PHY Link detect", (lwip_thread_fn)eth_phy_link_detect, netif,
                                            PHY_LINK_DETECT_THREAD_STACKSIZE, PHY_LINK_DETECT_THREAD_PRIO - eth_dev_id);
#endif
    if (gbe_netif_list[init_id].phy_link_handle == NULL)
    {
        AL_LOG(AL_LOG_LEVEL_ERROR, "sys_thread_new phy_link_handle failed\r\n");
    }

    AlGbe_Hal_StartMacDmaIntr(gbe_handle);
#endif

    AL_LOG(AL_LOG_LEVEL_INFO, "AlGbe Device %d Init success\r\n", eth_dev_id);

#if !NO_SYS
    AL_LOG(AL_LOG_LEVEL_INFO, "\r\n");
#endif

    return ERR_OK;
}

/**
  * @brief Should be called at the beginning of the program to set up the
  * network interface. It calls the function low_level_init() to do the
  * actual setup of the hardware.
  *
  * This function should be passed as a parameter to netif_add().
  *
  * @param netif the lwip network interface structure for this ethernetif
  * @return ERR_OK if the loopif is initialized
  *         ERR_MEM if private data couldn't be allocated
  *         any other err_t on error
  */
err_t ethernetif_init(struct netif *netif)
{
  LWIP_ASSERT("netif != NULL", (netif != NULL));

#if LWIP_NETIF_HOSTNAME
  /* Initialize interface hostname */
  netif->hostname = "lwip";
#endif /* LWIP_NETIF_HOSTNAME */

  /*
   * Initialize the snmp variables and counters inside the struct netif.
   * The last argument should be replaced with your link speed, in units
   * of bits per second.
   */
  MIB2_INIT_NETIF(netif, snmp_ifType_ethernet_csmacd, LINK_SPEED_OF_YOUR_NETIF_IN_BPS);

  netif->name[0] = IFNAME0;
  netif->name[1] = IFNAME1 + netif->num;

  /* We directly use etharp_output() here to save a function call.
   * You can instead declare your own function an call etharp_output()
   * from it if you have to do some checks before sending (e.g. if link
   * is available...) */
  netif->output = etharp_output;
  netif->linkoutput = low_level_output;

  /* initialize the hardware */
  low_level_init(netif);

  return ERR_OK;
}

void netif_config(void)
{
    int error;
    ip_addr_t ipaddr;
    ip_addr_t netmask;
    ip_addr_t gw;

    int init_id = 0;

    gbe_netif_cfg_list[init_id].init_id = init_id;

    gbe_netif_cfg_list[init_id].eth_netif_cfg.eth_dev_id = GBE_DEVICE_ID;
    gbe_netif_cfg_list[init_id].eth_netif_cfg.eth_mac_addr[0] = GBE_MAC_ADDR0;
    gbe_netif_cfg_list[init_id].eth_netif_cfg.eth_mac_addr[1] = GBE_MAC_ADDR1;
    gbe_netif_cfg_list[init_id].eth_netif_cfg.eth_mac_addr[2] = GBE_MAC_ADDR2;
    gbe_netif_cfg_list[init_id].eth_netif_cfg.eth_mac_addr[3] = GBE_MAC_ADDR3;
    gbe_netif_cfg_list[init_id].eth_netif_cfg.eth_mac_addr[4] = GBE_MAC_ADDR4;
    gbe_netif_cfg_list[init_id].eth_netif_cfg.eth_mac_addr[5] = GBE_MAC_ADDR5;
    gbe_netif_cfg_list[init_id].eth_netif_cfg.eth_phy_addr = 0;
    gbe_netif_cfg_list[init_id].eth_netif_cfg.eth_phy_speed = AL_GBE_SPEED_DEFAULT;
    gbe_netif_cfg_list[init_id].eth_netif_cfg.eth_phy_phase_1000M = 0x0;
    gbe_netif_cfg_list[init_id].eth_netif_cfg.eth_phy_phase_100M = 0x0;

    gbe_netif_cfg_list[init_id].eth_netif_cfg.netif   = &gnetif;

    gbe_netif_cfg_list[init_id].eth_netif_cfg.ip_addr  = ETH_IP_ADDRESS;
    gbe_netif_cfg_list[init_id].eth_netif_cfg.net_mask = ETH_NET_MASK;
    gbe_netif_cfg_list[init_id].eth_netif_cfg.gate_way = ETH_GATE_WAY;

    /* IP addr、netmask and gateway, Must be configured */
    error = inet_aton(gbe_netif_cfg_list[init_id].eth_netif_cfg.ip_addr, &ipaddr);
    if (!error)
    {
        AL_LOG(AL_LOG_LEVEL_ERROR, "Invalid IP Address\r\n");
        return ;
    }
    error = inet_aton(gbe_netif_cfg_list[init_id].eth_netif_cfg.net_mask, &netmask);
    if (!error)
    {
        AL_LOG(AL_LOG_LEVEL_ERROR, "Invalid net_mask\r\n");
        return ;
    }
    error = inet_aton(gbe_netif_cfg_list[init_id].eth_netif_cfg.gate_way, &gw);
    if (!error)
    {
        AL_LOG(AL_LOG_LEVEL_ERROR, "Invalid gate_way\r\n");
        return ;
    }

    #if NO_SYS
        netif_add(gbe_netif_cfg_list[init_id].eth_netif_cfg.netif, &ipaddr, &netmask, &gw,
                  &gbe_netif_cfg_list[init_id], &ethernetif_init, &ethernet_input);
    #else
        netif_add(gbe_netif_cfg_list[init_id].eth_netif_cfg.netif, &ipaddr, &netmask, &gw,
                  &gbe_netif_cfg_list[init_id], &ethernetif_init, &tcpip_input);
    #endif

    /* Registers the default network interface */
    netif_set_default(gbe_netif_cfg_list[init_id].eth_netif_cfg.netif);

    AL_LOG(AL_LOG_LEVEL_INFO, "Static IP  : %s\r\n", gbe_netif_cfg_list[init_id].eth_netif_cfg.ip_addr);
    AL_LOG(AL_LOG_LEVEL_INFO, "Netmask    : %s\r\n", gbe_netif_cfg_list[init_id].eth_netif_cfg.net_mask);
    AL_LOG(AL_LOG_LEVEL_INFO, "Gateway    : %s\r\n", gbe_netif_cfg_list[init_id].eth_netif_cfg.gate_way);
    AL_LOG(AL_LOG_LEVEL_INFO, "Mac Address: %02x:%02x:%02x:%02x:%02x:%02x\r\n",
                            gbe_netif_cfg_list[init_id].eth_netif_cfg.eth_mac_addr[0],
                            gbe_netif_cfg_list[init_id].eth_netif_cfg.eth_mac_addr[1],
                            gbe_netif_cfg_list[init_id].eth_netif_cfg.eth_mac_addr[2],
                            gbe_netif_cfg_list[init_id].eth_netif_cfg.eth_mac_addr[3],
                            gbe_netif_cfg_list[init_id].eth_netif_cfg.eth_mac_addr[4],
                            gbe_netif_cfg_list[init_id].eth_netif_cfg.eth_mac_addr[5]);
    AL_LOG(AL_LOG_LEVEL_INFO, "\r\n");
}

int eth_netif_config(struct eth_netif_cfg *eth_netif_cfg)
{
    int error;
    ip_addr_t ipaddr, netmask, gw;
    u8_t init_id;

    if ((eth_netif_cfg == NULL) || (eth_netif_cfg->netif == NULL) ||
        (eth_netif_cfg->ip_addr == NULL) || (eth_netif_cfg->net_mask == NULL) || (eth_netif_cfg->gate_way == NULL))
    {
        AL_LOG(AL_LOG_LEVEL_ERROR, "eth_netif_config Invalid param\r\n");
        return ERR_VAL;
    }

    if ((eth_netif_cfg->eth_dev_id < 0) || (eth_netif_cfg->eth_dev_id >= AL_GBE_NUM_INSTANCE))
    {
        AL_LOG(AL_LOG_LEVEL_ERROR, "Invalid GBE Device ID\r\n");
        return ERR_VAL;
    }

    if (eth_netif_cfg->eth_phy_phase_1000M == 0)
    {
        AL_LOG(AL_LOG_LEVEL_INFO, "INFO: The phase configuration of gbe phy 1000M is 0, "
                                  "and the default configuration in the phy driver will be used\r\n");
    }

    if (eth_netif_cfg->eth_phy_phase_100M == 0)
    {
        AL_LOG(AL_LOG_LEVEL_INFO, "INFO: The phase configuration of gbe phy 100M is 0, "
                                  "and the default configuration in the phy driver will be used\r\n");
    }

    /* IP addr、netmask and gateway, Must be configured */
    error = inet_aton(eth_netif_cfg->ip_addr, &ipaddr);
    if (!error)
    {
        AL_LOG(AL_LOG_LEVEL_ERROR, "Invalid IP Address\r\n");
        return ERR_VAL;
    }
    error = inet_aton(eth_netif_cfg->net_mask, &netmask);
    if (!error)
    {
        AL_LOG(AL_LOG_LEVEL_ERROR, "Invalid net_mask\r\n");
        return ERR_VAL;
    }
    error = inet_aton(eth_netif_cfg->gate_way, &gw);
    if (!error)
    {
        AL_LOG(AL_LOG_LEVEL_ERROR, "Invalid gate_way\r\n");
        return ERR_VAL;
    }

    SYS_ARCH_DECL_PROTECT(old_level);
    SYS_ARCH_PROTECT(old_level);

    init_id = current_init_id;
    current_init_id++;
    SYS_ARCH_UNPROTECT(old_level);

    if (init_id >= GBE_COUNT)
    {
        AL_LOG(AL_LOG_LEVEL_ERROR, "Invalid config ID\r\n");
        return ERR_VAL;
    }

    gbe_netif_cfg_list[init_id].init_id = init_id;
    memcpy(&gbe_netif_cfg_list[init_id].eth_netif_cfg, eth_netif_cfg, sizeof(struct eth_netif_cfg));

    #if NO_SYS
        netif_add(gbe_netif_cfg_list[init_id].eth_netif_cfg.netif, &ipaddr, &netmask, &gw,
                  &gbe_netif_cfg_list[init_id], &ethernetif_init, &ethernet_input);
    #else
        netif_add(gbe_netif_cfg_list[init_id].eth_netif_cfg.netif, &ipaddr, &netmask, &gw,
                  &gbe_netif_cfg_list[init_id], &ethernetif_init, &tcpip_input);
    #endif

    /* Registers the default network interface */
    netif_set_default(gbe_netif_cfg_list[init_id].eth_netif_cfg.netif);

    AL_LOG(AL_LOG_LEVEL_INFO, "Static IP  : %s\r\n", gbe_netif_cfg_list[init_id].eth_netif_cfg.ip_addr);
    AL_LOG(AL_LOG_LEVEL_INFO, "Netmask    : %s\r\n", gbe_netif_cfg_list[init_id].eth_netif_cfg.net_mask);
    AL_LOG(AL_LOG_LEVEL_INFO, "Gateway    : %s\r\n", gbe_netif_cfg_list[init_id].eth_netif_cfg.gate_way);
    AL_LOG(AL_LOG_LEVEL_INFO, "Mac Address: %02x:%02x:%02x:%02x:%02x:%02x\r\n",
                            gbe_netif_cfg_list[init_id].eth_netif_cfg.eth_mac_addr[0],
                            gbe_netif_cfg_list[init_id].eth_netif_cfg.eth_mac_addr[1],
                            gbe_netif_cfg_list[init_id].eth_netif_cfg.eth_mac_addr[2],
                            gbe_netif_cfg_list[init_id].eth_netif_cfg.eth_mac_addr[3],
                            gbe_netif_cfg_list[init_id].eth_netif_cfg.eth_mac_addr[4],
                            gbe_netif_cfg_list[init_id].eth_netif_cfg.eth_mac_addr[5]);
    AL_LOG(AL_LOG_LEVEL_INFO, "\r\n");

    return ERR_OK;
}

#endif /* HAVE_PS_GBE */