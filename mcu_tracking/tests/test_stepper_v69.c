#include "../stepper_app/stepper_control.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static uint32_t regs[8],time_ms;
static int p[2],fraction[2];
static FILE *trace;
static uint32_t rd(void *ctx,unsigned off)
{(void)ctx;assert(off>=0x180 && off<0x1a0);return regs[(off-0x180)/4];}
static void wr(void *ctx,unsigned off,uint32_t value)
{
    (void)ctx;assert(off>=0x180 && off<0x1a0);
    if(trace)fprintf(trace,"%u %x %08x\n",time_ms,off-0x180,value);
    regs[(off-0x180)/4]=value;
    if(off==0x190){
        if(!value)regs[1]=0;
        if(value==0x5a45524fu){regs[1]=2;p[0]=p[1]=fraction[0]=fraction[1]=0;}
        if(value==0x41524d32u)regs[1]=3;
        if(value==0x434d5432u){regs[6]=regs[2];regs[7]=regs[3];}
    }
}
static void clock10(StepperControl *s)
{
    unsigned i;time_ms+=10;
    for(i=0;i<2;i++){
        int goal=(int16_t)(regs[6]>>(16*i)),v=(int16_t)(regs[7]>>(16*i));
        if(!(regs[1]&1u))continue;
        fraction[i]+=v*10;
        while(fraction[i]>=1000){if(p[i]<goal)p[i]++;fraction[i]-=1000;}
        while(fraction[i]<=-1000){if(p[i]>goal)p[i]--;fraction[i]+=1000;}
        assert(p[i]>=-640 && p[i]<=640);
    }
    regs[5]=(uint16_t)p[0]|((uint32_t)(uint16_t)p[1]<<16);
    st_service(s,time_ms);
    assert(s->velocity[0]>=-200 && s->velocity[0]<=200);
    assert(s->velocity[1]>=-200 && s->velocity[1]<=200);
}
int main(int argc,char **argv)
{
    StepperControl s;
    int32_t map[2][3]={{4096,0,-160*4096},{0,4096,-90*4096}};
    int32_t bad[2][3]={{3000000,0,0},{0,4096,0}};
    unsigned n;int previous[2];
    if(argc>1){trace=fopen(argv[1],"w");assert(trace);}
    regs[0]=0x53545032;
    st_init(&s,rd,wr,0);assert(s.available && s.mode==ST_OFF && regs[1]==0);
    assert(!st_start(&s,ST_SCAN,0));assert(st_zero(&s));
    assert(!st_start(&s,ST_TRACK,0)); // never assume demo calibration
    assert(!st_set_map(&s,bad));assert(st_set_map(&s,map));
    assert(st_start(&s,ST_SCAN,0));
    for(n=0;n<1600 && s.mode;n++){
        previous[0]=s.velocity[0];previous[1]=s.velocity[1];clock10(&s);
        if(s.mode){assert(s.velocity[0]-previous[0]<=10 && previous[0]-s.velocity[0]<=10);
                   assert(s.velocity[1]-previous[1]<=10 && previous[1]-s.velocity[1]<=10);}
    }
    assert(s.mode==ST_OFF && s.scan_phase==5 && p[0]==0 && p[1]==0);
    assert(st_zero(&s));assert(st_start(&s,ST_TRACK,time_ms));
    for(n=0;n<500;n++){
        st_target(&s,240,130,1,time_ms);clock10(&s);
    }
    assert(p[0]==80 && p[1]==40);
    for(n=0;n<500;n++){
        st_target(&s,80,50,1,time_ms);clock10(&s);
    }
    assert(p[0]==-80 && p[1]==-40); // camera-fixed absolute mapping, not integrating drift
    st_target(&s,319,179,1,time_ms);
    for(n=0;n<8;n++)clock10(&s);
    st_target(&s,0,0,0,time_ms);
    for(n=0;n<100;n++)clock10(&s);
    assert(s.velocity[0]==0 && s.velocity[1]==0);
    // Foreground ArUco stall must disarm, never silently extend authorization.
    time_ms+=101;st_service(&s,time_ms);assert(s.mode==ST_OFF && regs[1]==0);
    if(trace)fclose(trace);
    puts("STEPPER_MCU_V69_PASS scan track reverse loss stall calibration");return 0;
}
