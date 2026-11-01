#ifndef UA_ARUCO_RUNTIME_H
#define UA_ARUCO_RUNTIME_H
#include <stdint.h>
#include "aruco_pose.h"
/* Foreground-only; real 1280x720 calibration required, never a guessed default. */
int ua_aruco_runtime_set_camera(const ua_aruco_camera *camera);
void ua_aruco_runtime_init(void);
void ua_aruco_runtime_step(uint64_t now,uint64_t ticks_us,const volatile unsigned *armed,
                           const volatile unsigned *dry,const volatile unsigned *remaining,
                           unsigned pulse_a,unsigned pulse_b);
void ua_aruco_runtime_status(void);
void ua_aruco_hw_off(void);
#endif
