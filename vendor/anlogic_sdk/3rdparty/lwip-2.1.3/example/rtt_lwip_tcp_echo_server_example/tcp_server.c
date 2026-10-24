/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <stdio.h>
#include <string.h>

#include "lwip/sockets.h"
#include "lwipopts.h"

#include <rtthread.h>

#define SERVER_PORT     8888

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

void tcp_server()
{
    int sock;
    int new_sd;
    int size;
    struct sockaddr_in address, remote;

    memset(&address, 0, sizeof(address));

    if ((sock = socket(AF_INET, SOCK_STREAM, 0)) < 0)
        return;

    address.sin_family = AF_INET;
    address.sin_port = htons(SERVER_PORT);
    address.sin_addr.s_addr = INADDR_ANY;

    if (bind(sock, (struct sockaddr *)&address, sizeof (address)) < 0) {
        printf("TCP server: Unable to bind to port %d\r\n", SERVER_PORT);
        close(sock);
        return;
    }

    printf("\r\nTCP server listening on port %d\r\n", SERVER_PORT);
    if (listen(sock, 1) < 0) {
        printf("TCP server: tcp_listen failed\r\n");
        close(sock);
        return;
    }

    size = sizeof(remote);

    if ((new_sd = accept(sock, (struct sockaddr *)&remote, (socklen_t *)&size)) < 0) {
        printf("TCP server: accept failed\r\n");
        close(sock);
        return;
    }

    printf("TCP server connected with %s\r\n", inet_ntoa(remote.sin_addr));

    process_echo_request(&new_sd);

    close(sock);
}

void tcp_server_thread()
{
    struct rt_thread *thread;

    tcp_server();

    printf("TCP server test done\r\n");

    thread = rt_thread_self();
    rt_thread_delete(thread);
}