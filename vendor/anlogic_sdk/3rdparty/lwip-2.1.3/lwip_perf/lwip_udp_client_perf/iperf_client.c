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
#include "lwip/udp.h"
#include "lwip/inet.h"

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

    u32_t reserved1;
    u32_t reserved2;
    u32_t reserved3;
    u32_t reserved4;
    u32_t reserved5;
    u32_t reserved6;
    u32_t reserved7;
    u32_t reserved8;
    u32_t reserved9;
    u32_t reserved10;
    u32_t reserved11;
    u32_t reserved12;
    u32_t reserved13;
    u32_t reserved14;
    u32_t reserved15;
    u32_t reserved16;
    u32_t reserved17;
    u32_t reserved18;
    u32_t reserved19;
    u32_t reserved20;
    u32_t reserved21;
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

/* Client port to connect */
#define UDP_CONN_PORT 5001

/* time in seconds to transmit packets */
#define UDP_TIME_INTERVAL 30

/* Server to connect with */
#define UDP_SERVER_IP_ADDRESS "192.168.31.148"

/* UDP buffer length in bytes */
#define UDP_SEND_BUFSIZE 1470

/* MAX UDP send retries */
#define MAX_SEND_RETRY 10

/* Number of parallel UDP clients */
#define NUM_OF_PARALLEL_CLIENTS 1

#define FINISH    1

/* This client is polled from the bare-metal main loop (transfer_data()
 * runs every iteration), so the end-of-test ack wait is a small state
 * machine rather than a blocking select()/recv(), matching iperf2's
 * AwaitServerFinPacket() timing: poll every 10ms, resend FIN on
 * timeout, for up to ~2 seconds total. */
#define FIN_ACK_POLL_MS    10
#define FIN_ACK_RETRIES    200

/* Report interval time in ms */
#define REPORT_INTERVAL_TIME (INTERIM_REPORT_INTERVAL * 1000)

/* End time in ms */
#define END_TIME (UDP_TIME_INTERVAL * 1000)

static struct udp_pcb *pcb[NUM_OF_PARALLEL_CLIENTS];
static struct perf_stats client = {0};
static char send_buf[UDP_SEND_BUFSIZE] __attribute__((__aligned__(4))) = {0};
/* Must be a real 64-bit counter: a 32-bit id wraps well before very
 * long or high-rate tests finish, which the server would misread as
 * end-of-test. */
static s64_t packet_id = 1;

enum client_state {
    CLIENT_XFER,
    CLIENT_AWAIT_FIN,
    CLIENT_DONE
};
static enum client_state client_state = CLIENT_XFER;
static u64_t fin_deadline_ms;
static int fin_retries_left;
static volatile u8_t fin_ack_received;
static char fin_ack_buf[128];
static u16_t fin_ack_len;

struct perf_udp_header *udp_hdr;

extern struct netif gnetif;

extern AL_VOID AlSys_DelayTicks(AL_U64 TickCount);

void print_iperf_info(void)
{
    printf("UDP client connecting to %s on port %d\r\n",
            UDP_SERVER_IP_ADDRESS, UDP_CONN_PORT);
    printf("On Host: Run $iperf -s -i %d -u\r\r\n\n",
            INTERIM_REPORT_INTERVAL);
}

static void print_udp_conn_stats(void)
{
    printf("[%3d] local %s port %d connected with ",
            client.client_id, inet_ntoa(gnetif.ip_addr),
            pcb[0]->local_port);
    printf("%s port %d\r\n",inet_ntoa(pcb[0]->remote_ip),
            pcb[0]->remote_port);
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

/* The report function of a UDP client session */
static void udp_conn_report(u64_t diff,
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
    else
        printf("[%3d] sent %llu datagrams\r\n",
                client.client_id, client.cnt_datagrams);
}

static void reset_stats(void)
{
    client.client_id++;
    /* Print connection statistics */
    print_udp_conn_stats();
    /* Save start time for final report */
    client.start_time = sys_now();
    client.total_bytes = 0;
    client.cnt_datagrams = 0;

    /* Initialize Interim report parameters */
    client.i_report.start_time = 0;
    client.i_report.total_bytes = 0;
    client.i_report.last_report_time = 0;
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

/* udp_recv callback: stashes the peer's FIN ack for transfer_data() to
 * pick up, since raw-API pcbs only deliver received data this way. */
static void udp_client_recv_ack(void *arg, struct udp_pcb *tpcb, struct pbuf *p,
        const ip_addr_t *addr, u16_t port)
{
    LWIP_UNUSED_ARG(arg);
    LWIP_UNUSED_ARG(tpcb);
    LWIP_UNUSED_ARG(addr);
    LWIP_UNUSED_ARG(port);

    fin_ack_len = (p->tot_len < sizeof(fin_ack_buf)) ? p->tot_len : sizeof(fin_ack_buf);
    pbuf_copy_partial(p, fin_ack_buf, fin_ack_len, 0);
    fin_ack_received = 1;
    pbuf_free(p);
}

static void udp_packet_send(u8_t finished)
{
    s64_t id = (finished == FINISH) ? -packet_id : packet_id;
    u8_t i;
    u8_t retries = MAX_SEND_RETRY;
    struct pbuf *packet;
    err_t err;

    for (i = 0; i < NUM_OF_PARALLEL_CLIENTS; i++) {

        packet = pbuf_alloc(PBUF_TRANSPORT, UDP_SEND_BUFSIZE, PBUF_POOL);
        if (!packet) {
            printf("error allocating pbuf to send\r\n");
            return;
        } else {

            udp_hdr->seqno_lower = htonl(id & 0xFFFFFFFFLL);
            udp_hdr->seqno_upper =htonl( (id  & 0xFFFFFFFF00000000LL) >> 32);

            pbuf_take(packet, send_buf, UDP_SEND_BUFSIZE);
        }

        while (retries) {
            err = udp_send(pcb[i], packet);
            //AlSys_UDelay(3);
            AlSys_DelayTicks(160);

            if (err != ERR_OK) {
                printf("Error on udp_send: %d\r\n", err);
                retries--;
                AlSys_UDelay(100);
            } else {
                client.total_bytes += UDP_SEND_BUFSIZE;
                client.cnt_datagrams++;
                client.i_report.total_bytes += UDP_SEND_BUFSIZE;
                break;
            }
        }
        if (!retries) {
            /* Terminate this app */
            u64_t now = sys_now();
            u64_t diff_ms = now - client.start_time;
            printf("Too many udp_send() retries, ");
            printf("Terminating application\r\n");
            udp_conn_report(diff_ms, UDP_DONE_CLIENT);
            printf("UDP test failed\r\n");
            udp_remove(pcb[i]);
            pcb[i] = NULL;
        }

        pbuf_free(packet);

        //AlSys_UDelay(1);
    }
    /* pcb lifecycle (including after FINISH) is owned by the caller's
     * await-ack state machine, not this function. Retries of the FIN
     * increment packet_id themselves (see transfer_data()); a normal
     * data packet advances it here. */
    if (finished != FINISH)
        packet_id++;
}

/** Transmit data on a udp session */
void transfer_data(void)
{
    int i = 0;
    u64_t now = sys_now();

    if (client_state == CLIENT_DONE)
        return;

    for (i = 0; i < NUM_OF_PARALLEL_CLIENTS; i++) {
        if (pcb[i] == NULL)
            return;
    }

    if (client_state == CLIENT_AWAIT_FIN) {
        u8_t done = 0;

        if (fin_ack_received) {
            udp_print_server_report(fin_ack_buf, fin_ack_len);
            done = 1;
        } else if (now >= fin_deadline_ms) {
            if (fin_retries_left <= 0) {
                done = 1;
            } else {
                fin_retries_left--;
                packet_id++;
                udp_packet_send(FINISH);
                fin_deadline_ms = now + FIN_ACK_POLL_MS;
            }
        }
        if (done) {
            for (i = 0; i < NUM_OF_PARALLEL_CLIENTS; i++) {
                if (pcb[i]) {
                    udp_remove(pcb[i]);
                    pcb[i] = NULL;
                }
            }
            client_state = CLIENT_DONE;
        }
        return;
    }

    if (END_TIME || REPORT_INTERVAL_TIME) {
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
                /* time specified is over, notify the server and
                 * wait for its ack before tearing down the pcb
                 */
                udp_packet_send(FINISH);
                udp_conn_report(diff_ms, UDP_DONE_CLIENT);
                printf("UDP test passed Successfully\r\n");
                fin_ack_received = 0;
                fin_retries_left = FIN_ACK_RETRIES;
                fin_deadline_ms = now + FIN_ACK_POLL_MS;
                client_state = CLIENT_AWAIT_FIN;
                return;
            }
        }
    }

    udp_packet_send(!FINISH);
}

void iperf_init(void)
{
    err_t err;
    ip_addr_t remote_addr;
    u32_t i;

    err = inet_aton(UDP_SERVER_IP_ADDRESS, &remote_addr);
    if (!err) {
        printf("Invalid Server IP address: %d\r\n", err);
        return;
    }

    for (i = 0; i < NUM_OF_PARALLEL_CLIENTS; i++) {
        /* Create Client PCB */
        pcb[i] = udp_new();
        if (!pcb[i]) {
            printf("Error in PCB creation. out of memory\r\n");
            return;
        }

        err = udp_connect(pcb[i], &remote_addr, UDP_CONN_PORT);
        if (err != ERR_OK) {
            printf("udp_client: Error on udp_connect: %d\r\n", err);
            udp_remove(pcb[i]);
            return;
        }
        /* Needed to receive the peer's end-of-test ack */
        udp_recv(pcb[i], udp_client_recv_ack, NULL);
    }
    /* Wait for successful connection */
    AlSys_UDelay(10);
    reset_stats();

    /* initialize data buffer being sent with same as used in iperf */
    for (i = PERF2_UDP_HEADER; i < UDP_SEND_BUFSIZE-PERF2_UDP_HEADER; i++)
        send_buf[i] = (i % 10) + '0';


    udp_hdr = (struct perf_udp_header *)send_buf;

    udp_hdr->flags = htonl(CLIENT_HEADER_FLAGS);
    udp_hdr->num_of_threads = htonl(CLIENT_HEADER_NUM_OF_THREADS);
    udp_hdr->port = htonl(CLIENT_HEADER_PORT);
    udp_hdr->amount = htonl(CLIENT_HEADER_AMOUNT);
    udp_hdr->major_version = htonl(CLIENT_HEADER_MAJOR_VERSION);
    udp_hdr->minor_version = htonl(CLIENT_HEADER_MINOR_VERSION);
}