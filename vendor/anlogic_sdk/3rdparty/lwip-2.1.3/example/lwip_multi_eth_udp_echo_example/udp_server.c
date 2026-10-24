/*
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
 */

#include "lwip/pbuf.h"
#include "lwip/udp.h"
#include "lwip/sys.h"
#include "lwip/inet.h"

#include <string.h>
#include <stdio.h>

#define UDP_LOCAL_PORT  8888

void udp_echoserver_receive_callback(void *arg, struct udp_pcb *upcb, struct pbuf *p, const ip_addr_t *addr, u16_t port);

void udp_echoserver_init(struct netif *netif)
{
    struct udp_pcb *upcb;
    err_t err;

    /* Create a new UDP control block  */
    upcb = udp_new();

    if (upcb)
    {
        /* Bind the upcb to the UDP_PORT port */
        /* Using IP_ADDR_ANY allow the upcb to be used by any local interface */
        err = udp_bind(upcb,  &netif->ip_addr, UDP_LOCAL_PORT + netif->num);

        if(err == ERR_OK)
        {
            printf("UDP Server Waiting for client on IP:%s port:%d...\r\n", inet_ntoa(netif->ip_addr), UDP_LOCAL_PORT+ netif->num);
            printf("\r\n");

            /* Set a receive callback for the upcb */
            udp_recv(upcb, udp_echoserver_receive_callback, NULL);
        }
        else
        {
            udp_remove(upcb);
        }

        udp_bind_netif(upcb, netif);
    }
}

void udp_echoserver_receive_callback(void *arg, struct udp_pcb *upcb, struct pbuf *p, const ip_addr_t *addr, u16_t port)
{
    if (p != NULL) {
        udp_sendto(upcb, p, addr, port);
        pbuf_free(p);
    }

}