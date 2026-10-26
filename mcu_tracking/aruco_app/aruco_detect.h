#ifndef UA_ARUCO_DETECT_H
#define UA_ARUCO_DETECT_H
#include <stdint.h>
#include "aruco_decode.h"
#define UA_ARUCO_PIXELS 14400u
#define UA_ARUCO_QUEUE 1024u
typedef struct { float x,y; } ua_aruco_point;
typedef uint8_t (*ua_aruco_pixel)(void *context,unsigned x,unsigned y);
typedef struct {
    ua_aruco_id code;
    ua_aruco_point corner[4]; /* Clockwise, canonical marker corner first. */
    ua_aruco_point refined_corner[4];
    unsigned refined_valid;
} ua_aruco_detection;
/* Caller-owned workspace. No malloc, recursion, SDK dependency or motor commands.
 * step() visits at most budget pixels/nodes; one candidate verification is a
 * bounded extra operation (at most 648 cached decode reads plus two strict dictionary comparisons,
 * then at most 1152 cached edge-refinement reads after a successful ID).
 * Input must remain immutable from begin until done. */
typedef struct {
    uint8_t visited[(UA_ARUCO_PIXELS+7u)/8u];
    union {
        uint16_t queue[UA_ARUCO_QUEUE];
        uint16_t hist[16];
    } scratch; /* Histogram is dead after phase0; phase3 queue keeps all 1024 slots. */
    ua_aruco_point extreme[16];
    int score[16];
    ua_aruco_pixel pixel;
    void *context;
    unsigned width,height,index,scan,head,tail,queued,area,phase;
    unsigned threshold,candidates,overflow,found;
    ua_aruco_detection result;
} ua_aruco_detector;
int ua_aruco_begin(ua_aruco_detector *d,unsigned width,unsigned height,
                   ua_aruco_pixel pixel,void *context);
/* 0=more work, 1=finished. Result.valid is cleared at every begin. */
int ua_aruco_step(ua_aruco_detector *d,unsigned budget);
#endif
