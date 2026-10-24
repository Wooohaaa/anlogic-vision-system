/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <stdio.h>
#include <string.h>

#include "lwip/sockets.h"
#include "lwipopts.h"

#include "FreeRTOS.h"
#include "task.h"

#define TCP_CONN_PORT 8888
#define TCP_SERVER_IP_ADDRESS "192.168.31.148"

#define RECV_BUF_SIZE   2048
char recv_buf[RECV_BUF_SIZE];

void process_echo_request(void *p)
{
    int sd = *(int *)p;
    int n, nwrote;

    while (1) {
        /* read a max of RECV_BUF_SIZE bytes from socket */
        if ((n = recv(sd, recv_buf, RECV_BUF_SIZE, 0)) < 0) {
            printf("ERROR reading from socket, closing socket\r\n");
            break;
        }

        /* break if client closed connection */
        if (n <= 0)
            break;

        /* handle request */
        if ((nwrote = send(sd, recv_buf, n, 0)) < 0) {
            printf("ERROR responding to client echo request. received = %d, written = %d\r\n", n, nwrote);
            printf("Closing socket %d\r\n", sd);
            break;
        }
    }

    /* close connection */
    close(sd);
}

void tcp_client()
{
    int sock;
    struct sockaddr_in address;

    memset(&address, 0, sizeof(address));

    if ((sock = socket(AF_INET, SOCK_STREAM, 0)) < 0)
        return;

    address.sin_family = AF_INET;
    address.sin_port = htons(TCP_CONN_PORT);
    address.sin_addr.s_addr = inet_addr(TCP_SERVER_IP_ADDRESS);

    printf("\r\nTCP client connect server %s port %d\r\n", TCP_SERVER_IP_ADDRESS, TCP_CONN_PORT);
    if (connect(sock, (struct sockaddr*)&address, sizeof(address)) < 0) {
        printf("TCP Client: Error on tcp_connect\r\n");
        close(sock);
        return;
    }

    process_echo_request(&sock);
}

void tcp_client_thread()
{
    tcp_client();

    printf("TCP client test done\r\n");
    vTaskDelete(NULL);
}