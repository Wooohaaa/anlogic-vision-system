#include "../stepper_app/stepper_key.h"
#include <assert.h>
#include <stdio.h>
static uint32_t status;static unsigned arms,zeros,stops;
static uint32_t rd(void *c,unsigned off){(void)c;return off==0x180?0x53545032u:status;}
static void wr(void *c,unsigned off,uint32_t v){
 (void)c;if(off!=0x190)return;
 if(!v){status=0;stops++;}
 if(v==0x5a45524fu){status=2;zeros++;}
 if(v==0x41524d32u){status=3;arms++;}
}
int main(void){
 StepperControl s;StepperKey k={0};st_init(&s,rd,wr,0);
 st_key_poll(&k,&s,1,1);assert(!st_key_poll(&k,&s,1,100));assert(!arms);
 st_key_poll(&k,&s,0,101);st_key_poll(&k,&s,0,125);
 st_key_poll(&k,&s,1,126);st_key_poll(&k,&s,0,130);st_key_poll(&k,&s,1,135);
 assert(!st_key_poll(&k,&s,1,150));assert(!arms);
 assert(st_key_poll(&k,&s,1,156)==1);assert(arms==1 && zeros==1 && s.mode==ST_TRACK);
 assert(!st_key_poll(&k,&s,1,1000));assert(arms==1);
 st_key_poll(&k,&s,0,1001);st_key_poll(&k,&s,0,1025);
 st_key_poll(&k,&s,1,1026);assert(st_key_poll(&k,&s,1,1050)==-1);assert(s.mode==ST_OFF);
 st_key_poll(&k,&s,0,1051);st_key_poll(&k,&s,0,1075);
 status=4;st_key_poll(&k,&s,1,1076);assert(st_key_poll(&k,&s,1,1100)==-2);assert(arms==1);
 assert(!st_key_poll(&k,&s,1,2000));assert(arms==1);
 /* wrapping millisecond clock and a new explicit press */
 status=0;st_key_poll(&k,&s,0,0xfffffff0u);st_key_poll(&k,&s,0,10);
 st_key_poll(&k,&s,1,11);assert(st_key_poll(&k,&s,1,35)==1);assert(arms==2);
 assert(s.valid==0 && s.stable==0 && stops>=2);
 puts("STEPPER_KEY_V83_PASS");return 0;
}
