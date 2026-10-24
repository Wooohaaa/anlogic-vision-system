/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <stdio.h>
#include <string.h>

#include "lwip/err.h"
#include "lwip/tcp.h"
#include "lwip/inet.h"
#include "al_gbe_ethernetif.h"

#define DEFAULT_TCP_PORT    8888

void print_app_header()
{
#if (LWIP_IPV6==0)
   AL_LOG(AL_LOG_LEVEL_INFO, "-----lwIP TCP echo server ------\r\n");
#else
   AL_LOG(AL_LOG_LEVEL_INFO, "-----lwIPv6 TCP echo server ------\r\n");
#endif
}

err_t recv_callback(void *arg, struct tcp_pcb *tpcb, struct pbuf *p, err_t err)
{
    /* do not read the packet if we are not in ESTABLISHED state */
    if (!p) {
        tcp_close(tpcb);
        tcp_recv(tpcb, NULL);
        return ERR_OK;
    }

    /* indicate that the packet has been received */
    tcp_recved(tpcb, p->len);

    /* echo back the payload */
    /* in this case, we assume that the payload is < TCP_SND_BUF */
    if (tcp_sndbuf(tpcb) > p->len) {
        err = tcp_write(tpcb, p->payload, p->len, 1);
    } else
       AL_LOG(AL_LOG_LEVEL_ERROR, "no space in tcp_sndbuf\n\r");

    /* free the received pbuf */
    pbuf_free(p);

    return ERR_OK;
}

err_t accept_callback(void *arg, struct tcp_pcb *newpcb, err_t err)
{
    static int connection = 1;

    /* set the receive callback for this connection */
    tcp_recv(newpcb, recv_callback);

    /* just use an integer number indicating the connection id as the
       callback argument */
    tcp_arg(newpcb, (void*)(AL_UINTPTR)connection);

    /* increment for subsequent accepted connections */
    connection++;

    return ERR_OK;
}

void tcp_server_init(struct netif *netif)
{
    struct tcp_pcb *pcb;
    err_t err;
    unsigned int port = DEFAULT_TCP_PORT + netif->num;

    print_app_header();

    /* create new TCP PCB structure */
    pcb = tcp_new_ip_type(IPADDR_TYPE_ANY);
    if (!pcb) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "Error creating PCB. Out of Memory\n\r");
        return;
    }

    /* bind to specified @port */
    err = tcp_bind(pcb, &netif->ip_addr, port);
    if (err != ERR_OK) {
       AL_LOG(AL_LOG_LEVEL_ERROR, "Unable to bind to port %d: err = %d\n\r", port, err);
        return;
    }

    tcp_bind_netif(pcb, netif);

    /* we do not need any arguments to callback functions */
    tcp_arg(pcb, NULL);

    /* listen for connections */
    pcb = tcp_listen(pcb);
    if (!pcb) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "Out of memory while tcp_listen\n\r");
        return;
    }

    /* specify callback to use for incoming connections */
    tcp_accept(pcb, accept_callback);

    AL_LOG(AL_LOG_LEVEL_INFO, "TCP echo server started IP:%s port:%d\n\r", inet_ntoa(netif->ip_addr), port);
    AL_LOG(AL_LOG_LEVEL_INFO, "\r\n");

    return;
}