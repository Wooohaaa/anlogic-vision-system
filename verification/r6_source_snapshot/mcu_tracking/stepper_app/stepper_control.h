#ifndef UA_STEPPER_CONTROL_V2_H
#define UA_STEPPER_CONTROL_V2_H
#include <stdint.h>
/* 100Hz velocity visual servo. Confirmed axes: 0 positive UP, 1 positive LEFT.
 * No GPIO PWM or per-pulse interrupts. Default OFF, manual origin required. */
typedef uint32_t (*st_read)(void *,unsigned);
typedef void (*st_write)(void *,unsigned,uint32_t);
typedef struct {
    st_read read;st_write write;void *context;
    int goal[2],velocity[2];
    int error[2]; /* filtered image error: axis0=90-y, axis1=160-x */
    unsigned pixel[2]; /* last valid x/y for diagnostics */
    uint32_t next_ms,last_ms,last_target_ms,scan_deadline_ms;
    unsigned available,mode,valid,stable,service_max_ms,scan_phase;
} StepperControl;
enum { ST_OFF=0,ST_SCAN=1,ST_TRACK=2,ST_AXIS0=3,ST_AXIS1=4 };
void st_init(StepperControl *,st_read,st_write,void *);
void st_stop(StepperControl *);
int st_zero(StepperControl *);
int st_start(StepperControl *,unsigned,uint32_t);
void st_target(StepperControl *,unsigned,unsigned,unsigned,uint32_t);
void st_service(StepperControl *,uint32_t);
#endif
