#ifndef UA_ARUCO_REFINE_H
#define UA_ARUCO_REFINE_H
#include "aruco_detect.h"
/* Only after a valid ID: bounded 4 edges x 8 samples x 9 bilinear samples
 * (four gray reads each).
 * Fits outer black-to-white transitions, intersects adjacent straight lines.
 * Failure leaves the original corners unchanged. No heap or extra frame RAM. */
int ua_aruco_refine(ua_aruco_pixel pixel,void *context,unsigned width,unsigned height,
                    ua_aruco_point corner[4]);
#endif
