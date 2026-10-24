#ifndef UA_ARUCO_DECODE_H
#define UA_ARUCO_DECODE_H
#include <stdint.h>
typedef struct {
    uint8_t valid, id, clockwise_to_canonical, hamming;
} ua_aruco_id;
/* Canonical 6x6 cell mask, bit0=top-left, white=1. Only 0/1 errors allowed.
 * Invalid, border-failing and ambiguous inputs explicitly clear valid. */
ua_aruco_id ua_aruco_decode(uint64_t cells, unsigned max_errors);
uint16_t ua_aruco_rotate_clockwise(uint16_t bits);
#endif
