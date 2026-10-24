/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "al_gbe_hal.h"
#include "al_gbe_ethernetif.h"

#include "lwipopts.h"
#include "lwip/sys.h"
#include "lwip/ip_addr.h"
#include "lwip/err.h"
#include "lwip/tcp.h"
#include "lwip/inet.h"

static struct tcp_pcb *c_pcb;

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
    u32_t report_interval_time;
};

struct perf_stats {
    u8_t client_id;
    u64_t start_time;
    u64_t end_time;
    u64_t total_bytes;
    struct interim_report i_report;
};

/* seconds between periodic bandwidth reports */
#define INTERIM_REPORT_INTERVAL 5

/* server port to listen on/connect to */
#define TCP_CONN_PORT 5001

#define TCP_TIME_INTERVAL 30
#define TCP_SERVER_IP_ADDRESS "192.168.31.148"

#define TCP_SEND_BUFSIZE (5*TCP_MSS)

static struct tcp_pcb *c_pcb;
static char send_buf[TCP_SEND_BUFSIZE];
static struct perf_stats client;

void print_iperf_info()
{
#if LWIP_IPV6==1
    printf("TCP client connecting to %s on port %d\r\n",
            TCP_SERVER_IPV6_ADDRESS, TCP_CONN_PORT);
    printf("On Host: Run $iperf -V -s -i %d -w 2M\r\n",
            INTERIM_REPORT_INTERVAL);
#else
    printf("TCP client connecting to %s on port %d\r\n",
            TCP_SERVER_IP_ADDRESS, TCP_CONN_PORT);
    printf("On Host: Run $iperf -s -i %d -w 2M\r\n",
            INTERIM_REPORT_INTERVAL);
#endif /* LWIP_IPV6 */
}

static void print_tcp_conn_stats()
{
#if LWIP_IPv6==1
    printf("[%3d] local %s port %d connected with ",
            client.client_id, inet6_ntoa(c_pcb->local_ip),
            c_pcb->local_port);
    printf("%s port %d\r\n",inet6_ntoa(c_pcb->remote_ip),
            c_pcb->remote_port);
#else
    printf("[%3d] local %s port %d connected with ",
            client.client_id, inet_ntoa(c_pcb->local_ip),
            c_pcb->local_port);
    printf("%s port %d\r\n",inet_ntoa(c_pcb->remote_ip),
            c_pcb->remote_port);
#endif /* LWIP_IPV6 */

    printf("[ ID] Interval\t\tTransfer   Bandwidth\r\n");
}

static void stats_buffer(char* outString,
        double data, enum measure_t type)
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
static void tcp_conn_report(u64_t diff,
        enum report_type report_type)
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

/** Close a tcp session */
static void tcp_client_close(struct tcp_pcb *pcb)
{
    err_t err;

    if (pcb != NULL) {
        tcp_sent(pcb, NULL);
        tcp_err(pcb, NULL);
        err = tcp_close(pcb);
        if (err != ERR_OK) {
            /* Free memory with abort */
            tcp_abort(pcb);
        }
    }
}

/** Error callback, tcp session aborted */
static void tcp_client_err(void *arg, err_t err)
{
    LWIP_UNUSED_ARG(err);
    u64_t now = sys_now();
    u64_t diff_ms = now - client.start_time;

    tcp_client_close(c_pcb);
    c_pcb = NULL;
    tcp_conn_report(diff_ms, TCP_ABORTED_REMOTE);
    printf("TCP connection aborted\r\n");
}

static err_t tcp_send_perf_traffic(void)
{
    err_t err;
    u8_t apiflags = TCP_WRITE_FLAG_COPY | TCP_WRITE_FLAG_MORE;

    if (c_pcb == NULL) {
        return ERR_CONN;
    }

    while (tcp_sndbuf(c_pcb) > TCP_SEND_BUFSIZE) {
        err = tcp_write(c_pcb, send_buf, TCP_SEND_BUFSIZE, apiflags);
        if (err != ERR_OK) {
            printf("TCP client: Error on tcp_write: %d\r\n",
                    err);
            return err;
        }

        err = tcp_output(c_pcb);
        if (err != ERR_OK) {
            printf("TCP client: Error on tcp_output: %d\r\n",
                    err);
            return err;
        }
        client.total_bytes += TCP_SEND_BUFSIZE;
        client.i_report.total_bytes += TCP_SEND_BUFSIZE;
    }

    if (client.end_time || client.i_report.report_interval_time) {
        u64_t now = sys_now();
        if (client.i_report.report_interval_time) {
            if (client.i_report.start_time) {
                u64_t diff_ms = now - client.i_report.start_time;
                u64_t rtime_ms = client.i_report.report_interval_time;
                if (diff_ms >= rtime_ms) {
                    tcp_conn_report(diff_ms, INTER_REPORT);
                    client.i_report.start_time = 0;
                    client.i_report.total_bytes = 0;
                }
            } else {
                client.i_report.start_time = now;
            }
        }

        if (client.end_time) {
            /* this session is time-limited */
            u64_t diff_ms = now - client.start_time;
            if (diff_ms >= client.end_time) {
                /* time specified is over,
                 * close the connection */
                tcp_conn_report(diff_ms, TCP_DONE_CLIENT);
                printf("TCP test passed Successfully\r\n");
                tcp_client_close(c_pcb);
                c_pcb = NULL;
                return ERR_OK;
            }
        }
    }
    return ERR_OK;
}

/** TCP sent callback, try to send more data */
static err_t tcp_client_sent(void *arg, struct tcp_pcb *tpcb, u16_t len)
{
    return tcp_send_perf_traffic();
}

/** TCP connected callback (active connection), send data now */
static err_t tcp_client_connected(void *arg, struct tcp_pcb *tpcb, err_t err)
{
    if (err != ERR_OK) {
        tcp_client_close(tpcb);
        printf("Connection error\r\n");
        return err;
    }
    /* store state */
    c_pcb = tpcb;

    client.start_time = sys_now();
    client.end_time = TCP_TIME_INTERVAL * 1000; /* ms */
    client.client_id++;
    client.total_bytes = 0;

    /* report interval time in ms */
    client.i_report.report_interval_time = INTERIM_REPORT_INTERVAL * 1000;
    client.i_report.last_report_time = 0;
    client.i_report.start_time = 0;
    client.i_report.total_bytes = 0;

    print_tcp_conn_stats();

    /* set callback values & functions */
    tcp_arg(c_pcb, NULL);
    tcp_sent(c_pcb, tcp_client_sent);
    tcp_err(c_pcb, tcp_client_err);

    /* initiate data transfer */
    return ERR_OK;
}

void transfer_data(void)
{
    if (client.client_id)
        tcp_send_perf_traffic();
}

void iperf_init(void)
{
    err_t err;
    struct tcp_pcb* pcb;
    ip_addr_t remote_addr;
    u32_t i;

#if LWIP_IPV6==1
    remote_addr.type= IPADDR_TYPE_V6;
    err = inet6_aton(TCP_SERVER_IPV6_ADDRESS, &remote_addr);
#else
    err = inet_aton(TCP_SERVER_IP_ADDRESS, &remote_addr);
#endif /* LWIP_IPV6 */

    if (!err) {
        printf("Invalid Server IP address: %d\r\n", err);
        return;
    }

    /* Create Client PCB */
    pcb = tcp_new_ip_type(IPADDR_TYPE_ANY);
    if (!pcb) {
        printf("Error in PCB creation. out of memory\r\n");
        return;
    }

    err = tcp_connect(pcb, &remote_addr, TCP_CONN_PORT,
            tcp_client_connected);
    if (err) {
        printf("Error on tcp_connect: %d\r\n", err);
        tcp_client_close(pcb);
        return;
    }
    client.client_id = 0;

    /* initialize data buffer being sent with same as used in iperf */
    for (i = 0; i < TCP_SEND_BUFSIZE; i++)
        send_buf[i] = (i % 10) + '0';

    return;
}