#ifndef STEPPER_KEY_H
#define STEPPER_KEY_H
#include "stepper_control.h"
typedef struct {uint32_t since;unsigned candidate,stable,released;} StepperKey;
/* Cold boot/held key cannot arm. A debounced release must precede a press.
 * OFF->ON is an explicit operator reference assertion, like on -ConfirmZero.
 * Failed zero/arm is never retried by holding the key. */
static inline int st_key_poll(StepperKey *k,StepperControl *s,unsigned pressed,uint32_t now)
{
    if(pressed!=k->candidate){k->candidate=pressed;k->since=now;return 0;}
    if(now-k->since<20u)return 0;
    if(!pressed){k->stable=0;k->released=1;return 0;}
    if(k->stable)return 0;
    k->stable=1;
    if(!k->released)return 0;
    k->released=0;
    if(s->mode!=ST_OFF){st_stop(s);return -1;}
    if(!s->available || (s->read(s->context,0x184)&13u))return -2;
    s->valid=s->stable=0; /* require three NEW frames after operator arm */
    if(!st_zero(s) || !st_start(s,ST_TRACK,now)){st_stop(s);return -2;}
    return 1;
}
#endif
