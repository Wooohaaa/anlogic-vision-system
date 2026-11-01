#ifndef UA_ARUCO_CAPTURE_H
#define UA_ARUCO_CAPTURE_H
#include "aruco_detect.h"
/* Bus callbacks use BYTE OFFSETS, aligned word access. No absolute base address
 * is guessed here. Validate device signature before any capture request. */
typedef uint32_t (*ua_aruco_read32)(void *,uint32_t);
typedef void (*ua_aruco_write32)(void *,uint32_t,uint32_t);
typedef struct {
    ua_aruco_detector detector;
    /* Packed upper-nibble grayscale snapshot; avoids repeated Fabric reads. */
    uint8_t gray4[(UA_ARUCO_PIXELS+1u)/2u];
    ua_aruco_read32 read;
    ua_aruco_write32 write;
    void *bus_context;
    unsigned state,width,height,capture_index;
    uint32_t deadline,frame_sequence;
    ua_aruco_detection result;
} ua_aruco_capture;
int ua_aruco_capture_begin(ua_aruco_capture *,ua_aruco_read32,ua_aruco_write32,void *,uint32_t now_ms);
/* 0=pending, 1=done (possibly no marker), -1=bus/status/timeout failure.
 * Call from the foreground with bounded budget, never inside a PWM ISR. */
int ua_aruco_capture_step(ua_aruco_capture *,uint32_t now_ms,unsigned budget);
#endif
