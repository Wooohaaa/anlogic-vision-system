#ifndef UA_ARUCO_DECODE_H
#define UA_ARUCO_DECODE_H
#include <stdint.h>
typedef struct {
    uint8_t valid, id, clockwise_to_canonical, hamming;
} ua_aruco_id;
/* Canonical 6x6 cell mask, bit0=top-left, white=1. */
ua_aruco_id ua_aruco_decode(uint64_t cells, unsigned max_errors);
ua_aruco_id ua_aruco_decode_with_border(uint64_t cells, unsigned max_errors, unsigned max_border_errors, uint8_t border_tolerant_id, uint64_t edge_support);
uint16_t ua_aruco_rotate_clockwise(uint16_t bits);
#endif
