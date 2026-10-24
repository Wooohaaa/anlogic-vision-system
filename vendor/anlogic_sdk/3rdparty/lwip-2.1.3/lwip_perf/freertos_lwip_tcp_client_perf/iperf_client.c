/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <sys/types.h>
#include <sys/socket.h>
#include <lwip/sys.h>
#include "lwipopts.h"
#include "lwip/tcp.h"
#include "lwip/ip_addr.h"
#include "lwip/inet.h"
#include "lwip/sockets.h"
#include "lwip/sys.h"

/* used as indices into kLabel[] */
enum {
    KCONV_UNIT,
    KCONV_KILO,
    KCONV_MEGA,
    KCONV_GIGA,
};

/* labels for formats [KMG] */
const char kLabel[] =
{
    ' ',
    'K',
    'M',
    'G'
};

/* used as type of print */
enum measure_t {
    BYTES,
    SPEED
};

/* Report Type */
enum report_type {
    /* The Intermediate report */
    INTER_REPORT,
    /* The client side test is done */
    TCP_DONE_CLIENT,
    /* Remote side aborted the test */
    TCP_ABORTED_REMOTE
};

struct interim_report {
    u64_t start_time;
    u64_t last_report_time;
    u32_t total_bytes;
};

struct perf_stats {
    u8_t client_id;
    u64_t start_time;
    u64_t total_bytes;
    struct interim_report i_report;
};

/* seconds between periodic bandwidth reports */
#define INTERIM_REPORT_INTERVAL 5

/* Client port to connect */
#define TCP_CONN_PORT 5001

/* Server to connect with */
#define TCP_SERVER_IP_ADDRESS "192.168.31.168"

/* time in seconds to transmit packets */
#define TCP_TIME_INTERVAL 30

/* Report interval time in ms */
#define REPORT_INTERVAL_TIME (INTERIM_REPORT_INTERVAL * 1000)
/* End time in ms */
#define END_TIME (TCP_TIME_INTERVAL * 1000)

#define TCP_SEND_BUFSIZE    6000

static char send_buf[TCP_SEND_BUFSIZE];
static struct perf_stats client;

void show_app_info()
{
    printf("\r\n");
    printf("TCP client connecting to %s on port %d\r\n",
            TCP_SERVER_IP_ADDRESS, TCP_CONN_PORT);
    printf("On Host: Run $iperf -s -i %d -w 2M\r\n",
            INTERIM_REPORT_INTERVAL);
}

void print_tcp_txperf_header(int sock)
{
    int size;

    struct sockaddr_in local, remote;

    size = sizeof(local);
    getsockname(sock, (struct sockaddr *) &local, (socklen_t *)&size);
    getpeername(sock, (struct sockaddr *) &remote, (socklen_t *) &size);

    printf("[%3d] local %s port %d connected with ",
            client.client_id, inet_ntoa(local.sin_addr),
            ntohs(local.sin_port));
    printf("%s port %d\r\n", inet_ntoa(remote.sin_addr),
            ntohs(local.sin_port));

    printf("[ ID] Interval    Transfer     Bandwidth\r\n");

}

static void stats_buffer(char* outString, double data, enum measure_t type)
{
    int conv = KCONV_UNIT;
    const char *format;
    double unit = 1024.0;

    if (type == SPEED)
        unit = 1000.0;

    while (data >= unit && conv <= KCONV_GIGA) {
        data /= unit;
        conv++;
    }

    /* Fit data in 4 places */
    if (data < 9.995) { /* 9.995 rounded to 10.0 */
        format = "%4.2f %c"; /* #.## */
    } else if (data < 99.95) { /* 99.95 rounded to 100 */
        format = "%4.1f %c"; /* ##.# */
    } else {
        format = "%4.0f %c"; /* #### */
    }
    sprintf(outString, format, data, kLabel[conv]);
}

/** The report function of a TCP client session */
static void tcp_conn_report(u64_t diff, enum report_type report_type)
{
    u64_t total_len;
    double duration, bandwidth = 0;
    char data[16], perf[16], time[64];

    if (report_type == INTER_REPORT) {
        total_len = client.i_report.total_bytes;
    } else {
        client.i_report.last_report_time = 0;
        total_len = client.total_bytes;
    }

    /* Converting duration from milliseconds to secs,
     * and bandwidth to bits/sec .
     */
    duration = diff / 1000.0; /* secs */
    if (duration)
        bandwidth = (total_len / duration) * 8.0;

    stats_buffer(data, total_len, BYTES);
    stats_buffer(perf, bandwidth, SPEED);

    /* On 32-bit platforms, printf is not able to print
     * u64_t values, so converting these values in strings and
     * displaying results
     */
    sprintf(time, "%4.1f-%4.1f sec",
            (double)client.i_report.last_report_time,
            (double)(client.i_report.last_report_time + duration));
    printf("[%3d] %s  %sBytes  %sbits/sec\r\n", client.client_id,
            time, data, perf);

    if (report_type == INTER_REPORT)
        client.i_report.last_report_time += duration;
}

int tcp_send_perf_traffic(int sock)
{
    int bytes_send;
    u8_t apiflags = MSG_MORE;

    client.start_time = sys_now();
    client.client_id++;
    client.i_report.last_report_time = 0;
    client.i_report.start_time = 0;
    client.i_report.total_bytes = 0;
    client.total_bytes = 0;

    print_tcp_txperf_header(sock);

    while (1) {
        if ((bytes_send = lwip_send(sock, send_buf, sizeof(send_buf),
                        apiflags)) < 0) {
            printf("TCP Client: Either connection aborted"
                    " from remote or Error on tcp_write\r\n");
            u64_t now = sys_now();
            u64_t diff_ms = now - client.start_time;
            tcp_conn_report(diff_ms, TCP_ABORTED_REMOTE);
            break;
        }

        client.total_bytes += bytes_send;

        if (END_TIME || REPORT_INTERVAL_TIME) {
            u64_t now = sys_now();
            if (REPORT_INTERVAL_TIME) {
                client.i_report.total_bytes += bytes_send;
                if (client.i_report.start_time) {
                    u64_t diff_ms = now -
                        client.i_report.start_time;
                    if (diff_ms >= REPORT_INTERVAL_TIME) {
                        tcp_conn_report(diff_ms,
                                INTER_REPORT);
                        client.i_report.start_time = 0;
                        client.i_report.total_bytes = 0;
                    }
                } else {
                    client.i_report.start_time = now;
                }
            }

            if (END_TIME) {
                /* this session is time-limited */
                u64_t diff_ms = now - client.start_time;
                if (diff_ms >= END_TIME) {
                    /* time specified is over */
                    /* close the connection */
                    tcp_conn_report(diff_ms,
                            TCP_DONE_CLIENT);
                    printf("TCP test passed Successfully\r\n");
                    break;
                }
            }
        }
    }

    close(sock);
    return 0;
}

void tcp_client_iperf(void)
{
    int sock, i;
    struct sockaddr_in address;

    show_app_info();

    /* set up address to connect to */
    memset(&address, 0, sizeof(address));

    while (1) {
        if ((sock = socket(AF_INET, SOCK_STREAM, 0)) < 0) {
            printf("TCP Client: Error in creating Socket\r\n");
            continue;
        }
        address.sin_family = AF_INET;
        address.sin_port = htons(TCP_CONN_PORT);
        address.sin_addr.s_addr = inet_addr(TCP_SERVER_IP_ADDRESS);

        if (connect(sock, (struct sockaddr*)&address, sizeof(address)) < 0) {
            printf("TCP Client: Error on tcp_connect\r\n");
            close(sock);
            vTaskDelay(1000);
        } else {
            break;
        }
    }

    /* initialize data buffer being sent */
    for (i = 0; i < TCP_SEND_BUFSIZE; i++)
        send_buf[i] = (i % 10) + '0';

    tcp_send_perf_traffic(sock);

    vTaskDelete(NULL);
}