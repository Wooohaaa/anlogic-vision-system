#include "stepper_control.h"
#include <string.h>
#define CMD 0x190u
#define STATUS 0x184u
#define POS 0x194u
#define TRACK_LIMIT 640 /* Existing FPGA hard range; mechanical room confirmed. */
// Axis0 vertical gets extra speed/acceleration; axis1 horizontal is faster too.
// Near center use conservative P gains, add stronger gain for large errors.
static uint32_t pack(int a,int b){return (uint32_t)(uint16_t)a|((uint32_t)(uint16_t)b<<16);}
static int absolute(int n){return n<0?-n:n;}
static int clamp(int n,int lo,int hi){return n<lo?lo:(n>hi?hi:n);}
void st_stop(StepperControl *s)
{
    if(s->available)s->write(s->context,CMD,0);
    s->mode=ST_OFF;s->valid=s->stable=0;s->velocity[0]=s->velocity[1]=0;
}
void st_init(StepperControl *s,st_read rd,st_write wr,void *ctx)
{
    memset(s,0,sizeof(*s));s->read=rd;s->write=wr;s->context=ctx;
    s->available=rd(ctx,0x180)==0x53545032u;st_stop(s);
}
int st_zero(StepperControl *s)
{
    if(!s->available || s->mode!=ST_OFF || (s->read(s->context,STATUS)&9u))return 0;
    s->write(s->context,CMD,0x5a45524fu);
    return (s->read(s->context,STATUS)&7u)==2u;
}
int st_start(StepperControl *s,unsigned mode,uint32_t now)
{
    if(!s->available || s->mode!=ST_OFF ||
       (mode!=ST_SCAN && mode!=ST_TRACK && mode!=ST_AXIS0 && mode!=ST_AXIS1) ||
       (s->read(s->context,STATUS)&7u)!=2u)return 0;
    // Tracking may be armed into WAIT with no target. Motion still requires
    // three fresh frames in st_service; never drive from stale coordinates.
    s->write(s->context,CMD,0x41524d32u);
    if(!(s->read(s->context,STATUS)&1u))return 0;
    s->mode=mode;s->next_ms=s->last_ms=now;
    s->scan_deadline_ms=now+15000u;s->scan_phase=0;
    if(mode!=ST_TRACK)s->valid=s->stable=0;
    s->goal[0]=s->goal[1]=0;s->velocity[0]=s->velocity[1]=0;return 1;
}
void st_target(StepperControl *s,unsigned x,unsigned y,unsigned valid,uint32_t now)
{
    unsigned i;
    if(valid!=1 || x>=320 || y>=180){s->valid=s->stable=0;return;}
    // Invalid frames never refresh the last valid age.
    if(!s->valid || now-s->last_target_ms>100)s->stable=0;
    s->pixel[0]=x;s->pixel[1]=y;
    for(i=0;i<2;i++){
        int e=i?160-(int)x:90-(int)y;
        if(!s->stable)s->error[i]=e;
        else s->error[i]+=(e-s->error[i])/2;
    }
    if(s->stable<3)s->stable++;
    s->valid=1;s->last_target_ms=now;
}
static unsigned scan_goal(StepperControl *s)
{
    static const int points[5][2]={{80,40},{-80,-40},{80,40},{-80,-40},{0,0}};
    unsigned count=s->mode==ST_SCAN?5u:3u;
    if(s->scan_phase>=count)return 0;
    if(s->mode==ST_SCAN){s->goal[0]=points[s->scan_phase][0];s->goal[1]=points[s->scan_phase][1];}
    else {
        int offset=s->scan_phase==0?80:(s->scan_phase==1?-80:0);
        s->goal[0]=s->mode==ST_AXIS0?offset:0;s->goal[1]=s->mode==ST_AXIS1?offset:0;
    }
    return 1;
}
void st_service(StepperControl *s,uint32_t now)
{
    int p[2],v[2],g[2];uint32_t raw,gap;unsigned i;
    if(s->mode==ST_OFF)return;
    gap=now-s->last_ms;if(gap>s->service_max_ms)s->service_max_ms=gap;
    if(gap>100 || (s->read(s->context,STATUS)&7u)!=3u){st_stop(s);return;}
    if((int32_t)(now-s->next_ms)<0)return;
    s->next_ms=now+10;s->last_ms=now;
    raw=s->read(s->context,POS);p[0]=(int16_t)raw;p[1]=(int16_t)(raw>>16);
    if(s->mode==ST_TRACK){
        // Stay armed on loss, decelerate to zero, and wait for reacquisition.
        // Clearing valid prevents ancient data becoming fresh after time wrap.
        if(now-s->last_target_ms>100)s->valid=s->stable=0;
        for(i=0;i<2;i++){
            int desired=0,e=s->error[i],speed,brake;
            int acceleration=i?30:42; // 3000 / 4200 pps/s
            int increment=clamp((int)(gap*(unsigned)acceleration/10u),1,acceleration*10);
            int twice_acceleration=acceleration*200;
            int live=s->valid && s->stable>=3 && now-s->last_target_ms<=100;
            // P velocity control, no integral or accumulated pixel goal.
            // Camera UP/LEFT shifts a stationary target DOWN/RIGHT.
            if(live && absolute(e)>6){
                int excess=absolute(e)-6;
                desired=excess*3;
                if(excess>18)desired+=(excess-18)*(i?1:3);
                desired=clamp(desired,0,i?650:750);
                if(e<0)desired=-desired;
            }
            v[i]=s->velocity[i]+clamp(desired-s->velocity[i],-increment,increment);
            if((p[i]>=TRACK_LIMIT && v[i]>0) || (p[i]<=-TRACK_LIMIT && v[i]<0))v[i]=0;
            speed=absolute(v[i]);brake=(speed*speed+twice_acceleration-1)/twice_acceleration+2;
            // Only a bounded braking horizon, never an absolute image map.
            g[i]=clamp(p[i]+(v[i]>0?brake:(v[i]<0?-brake:0)),-TRACK_LIMIT,TRACK_LIMIT);
            s->velocity[i]=v[i];s->goal[i]=g[i];
        }
    }else{
        if((int32_t)(now-s->scan_deadline_ms)>=0 || !scan_goal(s)){st_stop(s);return;}
        if(p[0]==s->goal[0] && p[1]==s->goal[1]){
            s->scan_phase++;
            if(!scan_goal(s)){st_stop(s);return;}
        }
        for(i=0;i<2;i++){
            int distance=s->goal[i]-p[i],speed=absolute(s->velocity[i]);
            int target=distance>0?200:(distance<0?-200:0);
            int brake=(speed*speed+1999)/2000+1;
            if(s->mode==ST_AXIS0 || s->mode==ST_AXIS1)target=clamp(target,-80,80);
            if(absolute(distance)<=brake && speed>20)target=0;
            else if(absolute(distance)<=brake && distance)target=distance>0?20:-20;
            v[i]=s->velocity[i]+clamp(target-s->velocity[i],-10,10);
            s->velocity[i]=v[i];g[i]=s->goal[i];
        }
    }
    s->write(s->context,0x188,pack(g[0],g[1]));
    s->write(s->context,0x18c,pack(v[0],v[1]));
    s->write(s->context,CMD,0x434d5432u);
}
