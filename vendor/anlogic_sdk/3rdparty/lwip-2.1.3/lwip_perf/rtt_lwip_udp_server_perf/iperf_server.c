/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "lwipopts.h"
#include "lwip/ip_addr.h"
#include "lwip/inet.h"
#include "lwip/sockets.h"
#include "lwip/sys.h"

#include <stdio.h>
#include <string.h>

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

/* Report type */
enum report_type {
    /* The Intermediate report */
    INTER_REPORT,
    /* The server side test is done */
    UDP_DONE_SERVER,
    /* Remote side aborted the test */
    UDP_ABORTED_REMOTE
};

struct interim_report {
    u64_t start_time;
    u64_t last_report_time;
    u32_t total_bytes;
    u32_t cnt_datagrams;
    u32_t cnt_dropped_datagrams;
};

struct perf_stats {
    u8_t client_id;
    u64_t start_time;
    u64_t end_time;
    u64_t total_bytes;
    u64_t cnt_datagrams;
    u64_t cnt_dropped_datagrams;
    u32_t cnt_out_of_order_datagrams;
    s64_t expected_datagram_id;
    struct interim_report i_report;
};

/* Size of the receive buffer */
#define RECV_BUF_SIZE 1500

/* seconds between periodic bandwidth reports */
#define INTERIM_REPORT_INTERVAL 5

/* server port to listen on/connect to */
#define UDP_CONN_PORT 5001

/* Report interval in ms */
#define REPORT_INTERVAL_TIME (INTERIM_REPORT_INTERVAL * 1000)

extern struct netif gnetif;
static struct perf_stats server;

void print_iperf_info(void)
{
    printf("UDP server listening on port %d\r\n",
            UDP_CONN_PORT);
    printf("On Host: Run $iperf -c %s -i %d -t 300 -u -b <bandwidth>\r\n",
            inet_ntoa(gnetif.ip_addr),
            INTERIM_REPORT_INTERVAL);
}

static void print_udp_conn_stats(struct sockaddr_in *remote)
{
    printf("[%3d] local %s port %d connected with ",
            server.client_id, inet_ntoa(gnetif.ip_addr),
            UDP_CONN_PORT);
    printf("%s port %d\r\n", inet_ntoa(remote->sin_addr),
            ntohs(remote->sin_port));
    printf("[ ID] Interval\t     Transfer     Bandwidth\t");
    printf("    Lost/Total Datagrams\r\n");
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

/** The report function of a UDP server session */
static void udp_conn_report(u64_t diff,
        enum report_type report_type)
{
    u64_t total_len, cnt_datagrams, cnt_dropped_datagrams, total_packets;
    u32_t cnt_out_of_order_datagrams;
    double duration, bandwidth = 0;
    char data[16], perf[16], time[64], drop[64];

    if (report_type == INTER_REPORT) {
        total_len = server.i_report.total_bytes;
        cnt_datagrams = server.i_report.cnt_datagrams;
        cnt_dropped_datagrams = server.i_report.cnt_dropped_datagrams;
    } else {
        server.i_report.last_report_time = 0;
        total_len = server.total_bytes;
        cnt_datagrams = server.cnt_datagrams;
        cnt_dropped_datagrams = server.cnt_dropped_datagrams;
        cnt_out_of_order_datagrams = server.cnt_out_of_order_datagrams;
    }

    total_packets = cnt_datagrams + cnt_dropped_datagrams;
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
            (double)server.i_report.last_report_time,
            (double)(server.i_report.last_report_time + duration));
    sprintf(drop, "%4llu/%5llu (%.2g%%)", cnt_dropped_datagrams,
            total_packets,
            (100.0 * cnt_dropped_datagrams)/total_packets);
    printf("[%3d] %s  %sBytes  %sbits/sec  %s\r\n", server.client_id,
            time, data, perf, drop);

    if (report_type == INTER_REPORT) {
        server.i_report.last_report_time += duration;
    } else if ((report_type != INTER_REPORT) && cnt_out_of_order_datagrams) {
        printf("[%3d] %s  %u datagrams received out-of-order\r\n",
                server.client_id, time,
                cnt_out_of_order_datagrams);
    }
}

static void reset_stats(void)
{
    server.client_id++;
    /* Save start time */
    server.start_time = sys_now();
    server.end_time = 0; /* ms */
    server.total_bytes = 0;
    server.cnt_datagrams = 0;
    server.cnt_dropped_datagrams = 0;
    server.cnt_out_of_order_datagrams = 0;
    server.expected_datagram_id = 0;

    /* Initialize Interim report parameters */
    server.i_report.start_time = 0;
    server.i_report.total_bytes = 0;
    server.i_report.cnt_datagrams = 0;
    server.i_report.cnt_dropped_datagrams = 0;
    server.i_report.last_report_time = 0;
}

/* Layout mirrors iperf2's struct server_hdr (iperf-2.2.1/include/payloads.h);
 * transit_stats is the (unused here) min/max/mean/etc one-way-transit-time
 * block, kept only so error_cnt2/outorder_cnt2/datagrams2 land at the right
 * offset. Sent right after a zeroed UDP_datagram header. */
struct iperf_server_hdr {
    u32_t flags;
    u32_t total_len1;
    u32_t total_len2;
    u32_t stop_sec;
    u32_t stop_usec;
    u32_t error_cnt;
    u32_t outorder_cnt;
    u32_t datagrams;
    u32_t jitter1;
    u32_t jitter2;
    u32_t transit_stats[15];
    u32_t error_cnt2;
    u32_t outorder_cnt2;
    u32_t datagrams2;
};

#define IPERF_HEADER_VERSION1 0x80000000
#define IPERF_HEADER_SEQNO64B 0x08000000

/* Build and send our final loss/byte-count report piggy-backed on the
 * FIN ack, matching iperf2's write_UDP_AckFIN()/"Server Report" so the
 * client can display the server's (authoritative) view of the test. */
static void udp_send_server_report(int sock, struct sockaddr_in *remote,
        socklen_t addr_len, u64_t diff_ms)
{
    char pkt[4 * sizeof(u32_t) + sizeof(struct iperf_server_hdr)];
    struct iperf_server_hdr *hdr =
        (struct iperf_server_hdr *)(pkt + 4 * sizeof(u32_t));

    memset(pkt, 0, sizeof(pkt));
    hdr->flags = htonl(IPERF_HEADER_VERSION1 | IPERF_HEADER_SEQNO64B);
    hdr->total_len1 = htonl((u32_t)(server.total_bytes >> 32));
    hdr->total_len2 = htonl((u32_t)(server.total_bytes & 0xFFFFFFFF));
    hdr->stop_sec = htonl((u32_t)(diff_ms / 1000));
    hdr->stop_usec = htonl((u32_t)((diff_ms % 1000) * 1000));
    hdr->error_cnt = htonl((u32_t)(server.cnt_dropped_datagrams & 0xFFFFFFFF));
    hdr->error_cnt2 = htonl((u32_t)(server.cnt_dropped_datagrams >> 32));
    hdr->outorder_cnt = htonl(server.cnt_out_of_order_datagrams);
    hdr->datagrams = htonl((u32_t)(server.cnt_datagrams & 0xFFFFFFFF));
    hdr->datagrams2 = htonl((u32_t)(server.cnt_datagrams >> 32));

    sendto(sock, pkt, sizeof(pkt), 0, (struct sockaddr *)remote, addr_len);
}

/** Receive data on a udp session */
void udp_recv_perf_traffic(int sock)
{
    char recv_buf[RECV_BUF_SIZE];
    struct sockaddr_in remote;
    socklen_t addr_len = sizeof(remote);
    int recv_bytes;
    u8_t first = 1;
    u64_t now = 0;
    u64_t drop_datagrams;
    s64_t recv_id;

    while (1) {
        recv_bytes = recvfrom(sock, recv_buf, RECV_BUF_SIZE, 0,
                (struct sockaddr *)&remote, &addr_len);
        /* Need the 4 leading 32-bit words (seqno_lower, tv_sec,
         * tv_usec, seqno_upper) to rebuild the 64-bit id.
         */
        if (recv_bytes < (int)(4 * sizeof(u32_t)))
            continue;

        /* iperf packs the id as two raw 32-bit halves (client sends them
         * network-order); reassemble the signed 64-bit sequence number
         * so a 32-bit wraparound on long/high-rate tests can't be
         * mistaken for the end-of-test marker.
         */
        drop_datagrams = 0;
        {
            u32_t id_lower = ntohl(((u32_t *)recv_buf)[0]);
            u32_t id_upper = ntohl(((u32_t *)recv_buf)[3]);

            recv_id = (s64_t)(((u64_t)id_upper << 32) | (u64_t)id_lower);
        }

        if (first) {
            if (recv_id < 0) {
                /* Stray/duplicate termination packet with no
                 * data received yet, ack it but don't start a
                 * bogus new session/report for it.
                 */
                sendto(sock, recv_buf, recv_bytes, 0,
                        (struct sockaddr *)&remote, addr_len);
                continue;
            }
            /* First packet should always start with recv id 0.
             * However, If Iperf client is running with parallel
             * thread, then this condition will also avoid
             * multiple print of connection header
             */
            reset_stats();
            /* Print connection statistics */
            print_udp_conn_stats(&remote);
            first = 0;
        }

        /* recv_id is now a reassembled 64-bit sequence number, so it
         * won't wrap during any realistic test. Still require it to
         * differ from the expected next id, as a safety net for peers
         * that don't send a real seqno_upper (upper word reads as 0).
         */
        if (recv_id < 0 && recv_id != server.expected_datagram_id) {
            u64_t diff_ms;

            /* Use a fresh timestamp; `now` may still hold a stale
             * value from a previous session if no data packet was
             * processed in this session yet, which would underflow
             * the unsigned subtraction below.
             */
            now = sys_now();
            diff_ms = now - server.start_time;
            /* Send our final stats report so the client can display
             * them, matching iperf2's write_UDP_AckFIN(); this also
             * serves as the ack of the client's FIN. */
            udp_send_server_report(sock, &remote, addr_len, diff_ms);
            udp_conn_report(diff_ms, UDP_DONE_SERVER);
            printf("UDP test passed Successfully\r\n");
            first = 1;
            continue;
        }

        /* Update dropped datagrams statistics */
        if (server.expected_datagram_id != recv_id) {
            if (server.expected_datagram_id < recv_id) {
                drop_datagrams =
                    recv_id - server.expected_datagram_id;
                server.cnt_dropped_datagrams += drop_datagrams;
                server.expected_datagram_id = recv_id + 1;
            } else if (server.expected_datagram_id > recv_id) {
                server.cnt_out_of_order_datagrams++;
            }
        } else {
            server.expected_datagram_id++;
        }

        server.cnt_datagrams++;

        /* Record total bytes for final report */
        server.total_bytes += recv_bytes;

        if (REPORT_INTERVAL_TIME) {
            now = sys_now();

            server.i_report.cnt_datagrams++;
            server.i_report.cnt_dropped_datagrams += drop_datagrams;

            /* Record total bytes for interim report */
            server.i_report.total_bytes += recv_bytes;
            if (server.i_report.start_time) {
                u64_t diff_ms = now - server.i_report.start_time;

                if (diff_ms >= REPORT_INTERVAL_TIME) {
                    udp_conn_report(diff_ms, INTER_REPORT);
                    /* Reset Interim report counters */
                    server.i_report.start_time = 0;
                    server.i_report.total_bytes = 0;
                    server.i_report.cnt_datagrams = 0;
                    server.i_report.cnt_dropped_datagrams = 0;
                }
            } else {
                /* Save start time for interim report */
                server.i_report.start_time = now;
            }
        }
    }
}

void udp_server_iperf(void)
{
    int sock;
    struct sockaddr_in address;

    print_iperf_info();

    memset(&address, 0, sizeof(address));
    if ((sock = socket(AF_INET, SOCK_DGRAM, 0)) < 0) {
        printf("UDP server: Error creating Socket\r\n");
        return;
    }

    address.sin_family = AF_INET;
    address.sin_port = htons(UDP_CONN_PORT);
    address.sin_addr.s_addr = INADDR_ANY;

    if (bind(sock, (struct sockaddr *)&address, sizeof(address)) < 0) {
        printf("UDP server: Unable to bind to port %d\r\n",
                UDP_CONN_PORT);
        close(sock);
        return;
    }

    udp_recv_perf_traffic(sock);

    close(sock);

    while (1);
}
