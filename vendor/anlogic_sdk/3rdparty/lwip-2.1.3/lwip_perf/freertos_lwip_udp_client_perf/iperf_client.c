/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <sys/types.h>
#include <sys/socket.h>

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

/* Report Type */
enum report_type {
    /* The Intermediate report */
    INTER_REPORT,
    /* The client side test is done */
    UDP_DONE_CLIENT,
    /* Remote side aborted the test */
    UDP_ABORTED_REMOTE
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
    u64_t cnt_datagrams;
    struct interim_report i_report;
};

/* iperf UDP header carried in the payload of every datagram. The server reads
 * the first 4 bytes (seqno_lower) as the datagram id to detect loss. */
struct perf_udp_header {
    u32_t seqno_lower;
    u32_t tv_sec;
    u32_t tv_usec;
    u32_t seqno_upper;

    u32_t flags;
    u32_t num_of_threads;
    u32_t port;
    u32_t buffer_len;
    u32_t win_band;
    u32_t amount;

    u32_t type;
    u32_t length;
    u32_t up_low_low_flags;

    u32_t major_version;
    u32_t minor_version;
    u32_t reserved_and_tos;
    u32_t rate;
    u32_t rate_unitls;
    u32_t realtime;
};

#define PERF2_UDP_HEADER                sizeof(struct perf_udp_header)
#define CLIENT_HEADER_FLAGS             0x480100a0
#define CLIENT_HEADER_NUM_OF_THREADS    0x00000001
#define CLIENT_HEADER_PORT              5001
#define CLIENT_HEADER_AMOUNT            0xfffff448

#define CLIENT_HEADER_MAJOR_VERSION     0x00020002
#define CLIENT_HEADER_MINOR_VERSION     0x00010003

/* seconds between periodic bandwidth reports */
#define INTERIM_REPORT_INTERVAL 5

/* Server port to connect to */
#define UDP_CONN_PORT 5001

/* Server to connect with */
#define UDP_SERVER_IP_ADDRESS "192.168.31.148"

/* time in seconds to transmit packets */
#define UDP_TIME_INTERVAL 30

/* UDP payload length in bytes */
#define UDP_SEND_BUFSIZE 1470

/* Target application send rate in Mbit/s. The client is paced to this rate so
 * it does not hand data to lwip faster than the ~1Gbps wire can carry it.
 * Sending faster only overflows the TX path and inflates the local counter
 * (e.g. bogus 1.37 Gbps) without improving goodput. The practical GbE payload
 * ceiling for 1470-byte datagrams is ~957 Mbit/s; keep this at or below it. */
#define TARGET_BW_MBITS   950

#define FINISH    1

/* iperf2's real UDP client polls every 10ms for the peer's end-of-test
 * ack, resending the FIN on each timeout, for up to ~2 seconds total
 * (see Client::AwaitServerFinPacket in iperf-2.2.1). Closing the socket
 * without this wait makes the peer's write_UDP_AckFIN() retry loop see
 * no silence and log "ack of last datagram failed". */
#define FIN_ACK_POLL_MS    10
#define FIN_ACK_RETRIES    200

/* Report interval time in ms */
#define REPORT_INTERVAL_TIME (INTERIM_REPORT_INTERVAL * 1000)
/* End time in ms */
#define END_TIME (UDP_TIME_INTERVAL * 1000)

static char send_buf[UDP_SEND_BUFSIZE] __attribute__((__aligned__(4))) = {0};
static struct perf_stats client;
/* Must be a real 64-bit counter: a 32-bit id wraps well before very long
 * or high-rate tests finish, which the server would misread as end-of-test. */
static s64_t packet_id;

extern struct netif gnetif;

void show_app_info(void)
{
    printf("\r\n");
    printf("UDP client connecting to %s on port %d\r\n",
            UDP_SERVER_IP_ADDRESS, UDP_CONN_PORT);
    printf("On Host: Run $iperf -s -i %d -u\r\n",
            INTERIM_REPORT_INTERVAL);
}

static void print_udp_conn_stats(int sock)
{
    printf("[%3d] local %s port %d connected with ",
            client.client_id, inet_ntoa(gnetif.ip_addr),
            UDP_CONN_PORT);
    printf("%s port %d\r\n", UDP_SERVER_IP_ADDRESS,
            UDP_CONN_PORT);
    printf("[ ID] Interval\t\tTransfer   Bandwidth\r\n");
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

/* The report function of a UDP client session */
static void udp_conn_report(u64_t diff, enum report_type report_type)
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
    else
        printf("[%3d] sent %llu datagrams\r\n",
                client.client_id, client.cnt_datagrams);
}

/* Fill the payload the same way iperf does, and set the fixed header fields */
static void udp_send_buf_init(void)
{
    struct perf_udp_header *udp_hdr = (struct perf_udp_header *)send_buf;
    u32_t i;

    for (i = PERF2_UDP_HEADER; i < UDP_SEND_BUFSIZE - PERF2_UDP_HEADER; i++)
        send_buf[i] = (i % 10) + '0';

    udp_hdr->flags = htonl(CLIENT_HEADER_FLAGS);
    udp_hdr->num_of_threads = htonl(CLIENT_HEADER_NUM_OF_THREADS);
    udp_hdr->port = htonl(CLIENT_HEADER_PORT);
    udp_hdr->amount = htonl(CLIENT_HEADER_AMOUNT);
    udp_hdr->major_version = htonl(CLIENT_HEADER_MAJOR_VERSION);
    udp_hdr->minor_version = htonl(CLIENT_HEADER_MINOR_VERSION);
}

/* Send one datagram. On the last packet (finished == FINISH) the sequence id
 * is made negative, which the iperf server uses to detect end-of-test. */
static int udp_packet_send(int sock, u8_t finished)
{
    struct perf_udp_header *udp_hdr = (struct perf_udp_header *)send_buf;
    s64_t id = (finished == FINISH) ? -packet_id : packet_id;
    int bytes_send;

    udp_hdr->seqno_lower = htonl((u32_t)(id & 0xFFFFFFFF));
    udp_hdr->seqno_upper = htonl((u32_t)((id >> 32) & 0xFFFFFFFF));

    bytes_send = lwip_send(sock, send_buf, UDP_SEND_BUFSIZE, 0);
    if (bytes_send > 0) {
        client.total_bytes += bytes_send;
        client.cnt_datagrams++;
        client.i_report.total_bytes += bytes_send;
        if (finished != FINISH)
            packet_id++;
        return 0;
    }

    return -1;
}

/* Layout mirrors iperf2's struct server_hdr (iperf-2.2.1/include/payloads.h),
 * sent by the peer piggy-backed right after the UDP_datagram header once it
 * detects our FIN. transit_stats holds the (unused here) min/max/mean/etc
 * one-way-transit-time fields so error_cnt2/outorder_cnt2/datagrams2 land
 * at the right offset. */
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

#define IPERF_HEADER_SEQNO64B 0x08000000

/* Print the peer's final loss/jitter report piggy-backed on its FIN ack,
 * matching iperf2's InitServerRelayUDPReport()/"Server Report" output. */
static void udp_print_server_report(const char *buf, int len)
{
    const struct iperf_server_hdr *hdr;
    u64_t total_bytes, total_datagrams, total_packets;
    s64_t total_err, total_out;
    double duration, bandwidth, jitter_ms, loss_pct;
    u32_t flags;

    if (len < (int)(4 * sizeof(u32_t) + sizeof(struct iperf_server_hdr)))
        return;

    hdr = (const struct iperf_server_hdr *)(buf + 4 * sizeof(u32_t));
    flags = ntohl(hdr->flags);

    total_bytes = ((u64_t)ntohl(hdr->total_len1) << 32) | ntohl(hdr->total_len2);
    duration = ntohl(hdr->stop_sec) + ntohl(hdr->stop_usec) / 1e6;
    if (flags & IPERF_HEADER_SEQNO64B) {
        total_err = ((s64_t)ntohl(hdr->error_cnt2) << 32) | ntohl(hdr->error_cnt);
        total_out = ((s64_t)ntohl(hdr->outorder_cnt2) << 32) | ntohl(hdr->outorder_cnt);
        total_datagrams = ((u64_t)ntohl(hdr->datagrams2) << 32) | ntohl(hdr->datagrams);
    } else {
        total_err = ntohl(hdr->error_cnt);
        total_out = ntohl(hdr->outorder_cnt);
        total_datagrams = ntohl(hdr->datagrams);
    }
    total_packets = total_datagrams + total_err;
    bandwidth = duration ? ((double)total_bytes * 8.0 / duration) : 0.0;
    jitter_ms = (ntohl(hdr->jitter1) + ntohl(hdr->jitter2) / 1e6) * 1000.0;
    loss_pct = total_packets ? (100.0 * total_err / total_packets) : 0.0;

    printf("[%3d] Server Report:\r\n", client.client_id);
    printf("[%3d]  0.0-%4.1f sec  %llu Bytes  %.0f bits/sec  %lld/%llu (%.2g%%)  %.3f ms jitter  %lld out-of-order\r\n",
            client.client_id, duration, total_bytes, bandwidth,
            total_err, total_packets, loss_pct, jitter_ms, total_out);
}

/* Wait for the peer's end-of-test ack, resending the FIN on each
 * timeout, matching real iperf2's AwaitServerFinPacket(). */
static void udp_await_server_fin(int sock)
{
    struct timeval tv = {0, FIN_ACK_POLL_MS * 1000};
    char ack_buf[128];
    int retry;
    int rc;

    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    for (retry = 0; retry < FIN_ACK_RETRIES; retry++) {
        rc = recv(sock, ack_buf, sizeof(ack_buf), 0);
        if (rc > 0) {
            udp_print_server_report(ack_buf, rc);
            return;
        }
        /* real iperf2 negates a freshly incremented id on each retry */
        packet_id++;
        udp_packet_send(sock, FINISH);
    }
}

/* Transmit data on a udp session */
static void udp_send_perf_traffic(int sock)
{
    client.start_time = sys_now();
    client.client_id++;
    client.total_bytes = 0;
    client.cnt_datagrams = 0;
    client.i_report.last_report_time = 0;
    client.i_report.start_time = 0;
    client.i_report.total_bytes = 0;
    packet_id = 0;

    print_udp_conn_stats(sock);

    while (1) {
        /* Rate pacing (token bucket): if we have already sent as many bits as
         * the target rate allows for the elapsed time, back off one tick.
         * This keeps the app send rate at ~TARGET_BW_MBITS and prevents the
         * TX ring from overflowing (which would drop packets locally and
         * inflate the reported bandwidth). */
        u64_t elapsed_ms = sys_now() - client.start_time;
        if (elapsed_ms > 0 &&
            (client.total_bytes * 8) >= ((u64_t)TARGET_BW_MBITS * 1000 * elapsed_ms)) {
            vTaskDelay(1);
            continue;
        }

        if (udp_packet_send(sock, !FINISH) < 0) {
            /* No TX buffer available, back off briefly and retry */
            vTaskDelay(1);
            continue;
        }

        if (END_TIME || REPORT_INTERVAL_TIME) {
            u64_t now = sys_now();

            if (REPORT_INTERVAL_TIME) {
                if (client.i_report.start_time) {
                    u64_t diff_ms = now - client.i_report.start_time;
                    if (diff_ms >= REPORT_INTERVAL_TIME) {
                        udp_conn_report(diff_ms, INTER_REPORT);
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
                    /* time specified is over, notify the server and stop */
                    udp_packet_send(sock, FINISH);
                    udp_await_server_fin(sock);
                    udp_conn_report(diff_ms, UDP_DONE_CLIENT);
                    printf("UDP test passed Successfully\r\n");
                    break;
                }
            }
        }
    }

    close(sock);
}

void udp_client_iperf(void)
{
    int sock;
    struct sockaddr_in address;

    show_app_info();

    memset(&address, 0, sizeof(address));

    while (1) {
        if ((sock = socket(AF_INET, SOCK_DGRAM, 0)) < 0) {
            printf("UDP Client: Error in creating Socket\r\n");
            vTaskDelay(1000);
            continue;
        }

        address.sin_family = AF_INET;
        address.sin_port = htons(UDP_CONN_PORT);
        address.sin_addr.s_addr = inet_addr(UDP_SERVER_IP_ADDRESS);

        /* Set the default peer so lwip_send() targets the server */
        if (connect(sock, (struct sockaddr *)&address, sizeof(address)) < 0) {
            printf("UDP Client: Error on udp connect\r\n");
            close(sock);
            vTaskDelay(1000);
        } else {
            break;
        }
    }

    udp_send_buf_init();

    udp_send_perf_traffic(sock);

    vTaskDelete(NULL);
}
