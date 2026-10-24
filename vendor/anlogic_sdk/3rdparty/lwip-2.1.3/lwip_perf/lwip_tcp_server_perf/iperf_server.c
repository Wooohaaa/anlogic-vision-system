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
static struct perf_stats server;

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

/* Report type */
enum report_type {
    /* The Intermediate report */
    INTER_REPORT,
    /* The server side test is done */
    TCP_DONE_SERVER,
    /* Remote side aborted the test */
    TCP_ABORTED_REMOTE
};

struct interim_report {
    AL_U64 start_time;
    AL_U64 last_report_time;
    AL_U32 total_bytes;
    AL_U32 report_interval_time;
};

struct perf_stats {
    AL_U8 client_id;
    AL_U64 start_time;
    AL_U64 end_time;
    AL_U64 total_bytes;
    struct interim_report i_report;
};

/* seconds between periodic bandwidth reports */
#define INTERIM_REPORT_INTERVAL 5

/* server port to listen on/connect to */
#define TCP_CONN_PORT 5001

extern struct netif gnetif;

void print_iperf_info(void)
{
    printf("TCP server listening on port %d\r\n",
            TCP_CONN_PORT);
#if LWIP_IPV6==1
    printf("On Host: Run $iperf -V -c %s%%<interface> -i %d -t 300 -w 2M\r\n",
            inet6_ntoa(gnetif.ip6_addr[0]),
            INTERIM_REPORT_INTERVAL);
#else
    printf("On Host: Run $iperf -c %s -i %d -t 300 -w 2M\r\n",
            inet_ntoa(gnetif.ip_addr),
            INTERIM_REPORT_INTERVAL);
#endif /* LWIP_IPV6 */
}

static void print_tcp_conn_stats(void)
{
#if LWIP_IPV6==1
    printf("[%3d] local %s port %d connected with ",
            server.client_id, inet6_ntoa(c_pcb->local_ip),
            c_pcb->local_port);
    printf("%s port %d\r\n",inet6_ntoa(c_pcb->remote_ip),
            c_pcb->remote_port);
#else
    printf("[%3d] local %s port %d connected with ",
            server.client_id, inet_ntoa(c_pcb->local_ip),
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


/** The report function of a TCP server session */
static void tcp_conn_report(AL_U64 diff,
        enum report_type report_type)
{
    AL_U64 total_len;
    double duration, bandwidth = 0;
    char data[16], perf[16], time[64];

    if (report_type == INTER_REPORT) {
        total_len = server.i_report.total_bytes;
    } else {
        server.i_report.last_report_time = 0;
        total_len = server.total_bytes;
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
     * AL_U64 values, so converting these values in strings and
     * displaying results
     */
    sprintf(time, "%4.1f-%4.1f sec",
            (double)server.i_report.last_report_time,
            (double)(server.i_report.last_report_time + duration));
    printf("[%3d] %s  %sBytes  %sbits/sec\r\n", server.client_id,
            time, data, perf);

    if (report_type == INTER_REPORT)
        server.i_report.last_report_time += duration;
}

/** Close a tcp session */
static void tcp_server_close(struct tcp_pcb *pcb)
{
    err_t err;

    if (pcb != NULL) {
        tcp_recv(pcb, NULL);
        tcp_err(pcb, NULL);
        err = tcp_close(pcb);
        if (err != ERR_OK) {
            /* Free memory with abort */
            tcp_abort(pcb);
        }
    }
}

/** Error callback, tcp session aborted */
static void tcp_server_err(void *arg, err_t err)
{
    LWIP_UNUSED_ARG(err);
    AL_U64 now = sys_now();
    AL_U64 diff_ms = now - server.start_time;
    tcp_server_close(c_pcb);
    c_pcb = NULL;
    tcp_conn_report(diff_ms, TCP_ABORTED_REMOTE);
    printf("TCP connection aborted\r\n");
}


/** Receive data on a tcp session */
static err_t tcp_recv_perf_traffic(void *arg, struct tcp_pcb *tpcb,
        struct pbuf *p, err_t err)
{
    static AL_U64 now;
    if (p == NULL) {
        AL_U64 diff_ms = now - server.start_time;
        tcp_server_close(tpcb);
        tcp_conn_report(diff_ms, TCP_DONE_SERVER);
        printf("TCP test passed Successfully\r\n");
        return ERR_OK;
    }

    /* Record total bytes for final report */
    server.total_bytes += p->tot_len;

    if (server.i_report.report_interval_time) {
        now = sys_now();
        /* Record total bytes for interim report */
        server.i_report.total_bytes += p->tot_len;
        if (server.i_report.start_time) {
            AL_U64 diff_ms = now - server.i_report.start_time;

            if (diff_ms >= server.i_report.report_interval_time) {
                tcp_conn_report(diff_ms, INTER_REPORT);
                /* Reset Interim report counters */
                server.i_report.start_time = 0;
                server.i_report.total_bytes = 0;
            }
        } else {
            /* Save start time for interim report */
            server.i_report.start_time = now;
        }
    }

    tcp_recved(tpcb, p->tot_len);

    pbuf_free(p);
    return ERR_OK;
}

static err_t tcp_server_accept(void *arg, struct tcp_pcb *newpcb, err_t err)
{
    if ((err != ERR_OK) || (newpcb == NULL)) {
        return ERR_VAL;
    }
    /* Save connected client PCB */
    c_pcb = newpcb;

    /* Save start time for final report */
    server.start_time = sys_now();
    server.end_time = 0; /* ms */
    /* Update connected client ID */
    server.client_id++;
    server.total_bytes = 0;

    /* Initialize Interim report parameters */
    server.i_report.report_interval_time =
        INTERIM_REPORT_INTERVAL * 1000; /* ms */
    server.i_report.last_report_time = 0;
    server.i_report.start_time = 0;
    server.i_report.total_bytes = 0;

    print_tcp_conn_stats();

    /* setup callbacks for tcp rx connection */
    tcp_arg(c_pcb, NULL);
    tcp_recv(c_pcb, tcp_recv_perf_traffic);
    tcp_err(c_pcb, tcp_server_err);

    return ERR_OK;
}

void iperf_init(void)
{
    err_t err;
    struct tcp_pcb *pcb, *lpcb;

    /* Create Server PCB */
    pcb = tcp_new_ip_type(IPADDR_TYPE_ANY);
    if (!pcb) {
        printf("TCP server: Error creating PCB. Out of Memory\r\n");
        return;
    }

    err = tcp_bind(pcb, IP_ADDR_ANY, TCP_CONN_PORT);
    if (err != ERR_OK) {
        printf("TCP server: Unable to bind to port %d: "
                "err = %d\r\n" , TCP_CONN_PORT, err);
        tcp_close(pcb);
        return;
    }

    /* Set connection queue limit to 1 to serve
     * one client at a time
     */
    lpcb = tcp_listen_with_backlog(pcb, 1);
    if (!lpcb) {
        printf("TCP server: Out of memory while tcp_listen\r\n");
        tcp_close(pcb);
        return;
    }

    /* we do not need any arguments to callback functions */
    tcp_arg(lpcb, NULL);

    /* specify callback to use for incoming connections */
    tcp_accept(lpcb, tcp_server_accept);

    return;
}