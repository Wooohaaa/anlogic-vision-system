/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <sys/types.h>
#include <sys/socket.h>
#include <lwip/sys.h>

#define BUFSZ   2048

char recv_data[BUFSZ];

int port = 5000;

/**
* @brief  This function is for creating a udp server on Freertos
*/

void udpserv(void *param)
{
    int sock, bytes_read;
    socklen_t addr_len;
    struct sockaddr_in server_addr, client_addr;
    struct timeval timeout;
    fd_set readset;
    struct netif *netif = (struct netif *)param;
    struct ifreq iface;

udp_server:

    /* Create a socket and set it to SOCK_DGRAM(UDP) */
    if ((sock = socket(AF_INET, SOCK_DGRAM, 0)) == -1)
    {
        printf("Create socket error...\r\n");
        goto __exit;
    }

    /* Initialize server side address */
    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(port+netif->num);;
    server_addr.sin_addr.s_addr = netif->ip_addr.addr;;
    memset(&(server_addr.sin_zero), 0, sizeof(server_addr.sin_zero));

    /* Bind socket to server side address */
    if (bind(sock, (struct sockaddr *)&server_addr,
             sizeof(struct sockaddr)) == -1)
    {
        printf("Unable to bind\r\n");
        goto __exit;
    }

    strncpy(iface.ifr_name, netif->name, sizeof(netif->name));
    lwip_itoa(&iface.ifr_name[2], IFNAMSIZ-2, netif->num);
    if (setsockopt(sock, SOL_SOCKET, SO_BINDTODEVICE, &iface, sizeof(iface)) < 0) {
        printf("TCP server: setsockopt failed\r\n");
        goto __exit;
    }

    addr_len = sizeof(struct sockaddr);

    sys_prot_t level = sys_arch_protect();
    printf("UDPServer Waiting for client on IP:%s port:%d...\r\n", inet_ntoa(server_addr.sin_addr), port+netif->num);
    printf("\r\n");
    sys_arch_unprotect(level);


    timeout.tv_sec = 3;
    timeout.tv_usec = 0;

    while (1)
    {
        FD_ZERO(&readset);
        FD_SET(sock, &readset);

        /* Wait for read or write */
        if (select(sock + 1, &readset, NULL, NULL, &timeout) == 0)
            continue;
        /* The maximum size received from sock is BUFSZ-1 bytes*/
        bytes_read = recvfrom(sock, recv_data, BUFSZ - 1, 0,
                              (struct sockaddr *)&client_addr, &addr_len);
        if (bytes_read < 0)
        {
            printf("Received error, close the connect.\r\n");
            goto __exit;
        }
        else if (bytes_read == 0)
        {
            printf("Received warning, recv function return 0.\r\n");
            continue;
        }
        else
        {
            sendto(sock, recv_data, bytes_read, 0,
                        (struct sockaddr *)&client_addr, addr_len);
        }
    }

__exit:

    if (sock >= 0)
    {
        closesocket(sock);
        sock = -1;
    }

    goto udp_server;

    /* It won't run here */
    while(1);
}