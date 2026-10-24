#include "../stepper_app/stepper_control.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static uint32_t regs[8],ms;
static int p[2],fraction[2];
static uint32_t rd(void *ctx,unsigned off)
{(void)ctx;assert(off>=0x180 && off<0x1a0);return regs[(off-0x180)/4];}
static void wr(void *ctx,unsigned off,uint32_t value)
{
    (void)ctx;assert(off>=0x180 && off<0x1a0);regs[(off-0x180)/4]=value;
    if(off==0x190){
        if(!value)regs[1]=0;
        if(value==0x5a45524fu){regs[1]=2;p[0]=p[1]=fraction[0]=fraction[1]=0;}
        if(value==0x41524d32u)regs[1]=3;
        if(value==0x434d5432u){regs[6]=regs[2];regs[7]=regs[3];}
    }
}
static void init(StepperControl *s)
{
    memset(regs,0,sizeof(regs));memset(p,0,sizeof(p));memset(fraction,0,sizeof(fraction));
    ms=0;regs[0]=0x53545032;st_init(s,rd,wr,0);assert(s->available && s->mode==ST_OFF);
}
static void clock10(StepperControl *s)
{
    unsigned i;int previous[2]={s->velocity[0],s->velocity[1]};unsigned mode=s->mode;
    ms+=10;
    for(i=0;i<2;i++){
        int goal=(int16_t)(regs[6]>>(16*i)),v=(int16_t)(regs[7]>>(16*i));
        if(!(regs[1]&1u))continue;
        fraction[i]+=v*10;
        while(fraction[i]>=1000){if(p[i]<goal)p[i]++;fraction[i]-=1000;}
        while(fraction[i]<=-1000){if(p[i]>goal)p[i]--;fraction[i]+=1000;}
        assert(p[i]>=-640 && p[i]<=640);
    }
    regs[5]=(uint16_t)p[0]|((uint32_t)(uint16_t)p[1]<<16);st_service(s,ms);
    for(i=0;i<2;i++){
        assert(s->velocity[i]>=-200 && s->velocity[i]<=200);
        if(mode==ST_TRACK && s->mode==ST_TRACK){
            assert(p[i]>=-160 && p[i]<=160);
            assert(s->goal[i]>=-160 && s->goal[i]<=160);
            assert(s->velocity[i]>=-120 && s->velocity[i]<=120);
            if(p[i]>-160 && p[i]<160){
                assert(s->velocity[i]-previous[i]<=8 && previous[i]-s->velocity[i]<=8);
            }
        }
    }
}
static void target3(StepperControl *s,unsigned x,unsigned y)
{unsigned i;for(i=0;i<3;i++){st_target(s,x,y,1,ms);clock10(s);}}
static void scan_tests(void)
{
    StepperControl s;unsigned mode,n,seen_pos,seen_neg,i;
    for(mode=ST_SCAN;mode<=ST_AXIS1;mode++){
        if(mode==ST_TRACK)continue;
        init(&s);assert(!st_start(&s,mode,ms));assert(st_zero(&s));
        assert(!st_start(&s,99,ms));assert(st_start(&s,mode,ms));seen_pos=seen_neg=0;
        for(n=0;n<1600 && s.mode;n++){
            clock10(&s);
            if(mode!=ST_SCAN){
                i=mode==ST_AXIS0?0:1;
                assert(p[1-i]==0 && s.velocity[1-i]==0);
                assert(s.velocity[i]>=-80 && s.velocity[i]<=80);
                if(p[i]==80)seen_pos=1;
                if(p[i]==-80)seen_neg=1;
            }
        }
        assert(s.mode==ST_OFF && p[0]==0 && p[1]==0 && regs[1]==0);
        assert(s.scan_phase==(mode==ST_SCAN?5u:3u));
        if(mode!=ST_SCAN)assert(seen_pos && seen_neg);
    }
}
static void safety_tests(void)
{
    StepperControl s;unsigned i;int held[2];
    init(&s);assert(!st_start(&s,ST_TRACK,ms));
    assert(st_zero(&s));assert(st_start(&s,ST_TRACK,ms));
    // No target is armed WAIT, never blind movement.
    for(i=0;i<100;i++){clock10(&s);assert(s.mode==ST_TRACK && p[0]==0 && p[1]==0);}
    assert((regs[1]&3)==3);
    st_target(&s,200,60,1,ms);clock10(&s);assert(s.velocity[0]==0 && s.velocity[1]==0);
    st_target(&s,200,60,1,ms);clock10(&s);assert(s.velocity[0]==0 && s.velocity[1]==0);
    st_target(&s,200,60,1,ms);clock10(&s);
    assert(s.velocity[0]>0 && s.velocity[1]<0);
    for(i=0;i<15;i++){st_target(&s,200,60,1,ms);clock10(&s);}
    st_target(&s,0,0,0,ms);
    for(i=0;i<100;i++)clock10(&s);
    assert(s.mode==ST_TRACK && s.velocity[0]==0 && s.velocity[1]==0);
    held[0]=p[0];held[1]=p[1];
    // One minute of invalid detections stays ON, at rest; no 15s scan timeout.
    for(i=0;i<6000;i++){
        st_target(&s,0,0,0,ms);clock10(&s);
        assert(s.mode==ST_TRACK && p[0]==held[0] && p[1]==held[1]);
    }
    st_target(&s,100,140,1,ms);clock10(&s);assert(s.velocity[0]==0 && s.velocity[1]==0);
    st_target(&s,100,140,1,ms);clock10(&s);assert(s.velocity[0]==0 && s.velocity[1]==0);
    st_target(&s,100,140,1,ms);clock10(&s);
    assert(s.velocity[0]<0 && s.velocity[1]>0); // automatic resume, no ZERO/ARM
    for(i=0;i<100;i++)clock10(&s); // lost UART stream, not just invalid packets
    assert(s.mode==ST_TRACK && !s.valid && s.stable==0);
    assert(s.velocity[0]==0 && s.velocity[1]==0);
    held[0]=p[0];held[1]=p[1];
    for(i=0;i<6000;i++){clock10(&s);assert(p[0]==held[0] && p[1]==held[1]);}
    assert(s.mode==ST_TRACK);
    // A stopped controller never re-arms merely because a target reappears.
    st_stop(&s);target3(&s,160,90);assert(!st_start(&s,ST_TRACK,ms));
    assert(st_zero(&s));assert(st_start(&s,ST_TRACK,ms));
    ms+=101;st_service(&s,ms);assert(s.mode==ST_OFF && regs[1]==0);
    assert(st_zero(&s));target3(&s,160,90);assert(st_start(&s,ST_TRACK,ms));
    regs[1]|=4;clock10(&s);assert(s.mode==ST_OFF && regs[1]==0);
    st_target(&s,320,90,1,ms);assert(!s.valid && s.stable==0);
    st_target(&s,160,180,1,ms);assert(!s.valid);
    st_target(&s,160,90,2,ms);assert(!s.valid);
    init(&s);assert(st_zero(&s));target3(&s,160,90);assert(st_start(&s,ST_TRACK,ms));
    for(i=0;i<500;i++){
        if(i%2==0)st_target(&s,158+(i%5),88+(i%5),1,ms);
        clock10(&s);assert(p[0]==0 && p[1]==0);
    }
    st_stop(&s);assert(!st_start(&s,ST_TRACK,ms));
    init(&s);ms=0xfffffff0u;target3(&s,160,90);assert(st_zero(&s));
    assert(st_start(&s,ST_TRACK,ms));
    for(i=0;i<30;i++){st_target(&s,160,90,1,ms);clock10(&s);}
    assert(s.mode==ST_TRACK && p[0]==0 && p[1]==0);st_stop(&s);
    init(&s);assert(st_zero(&s));target3(&s,250,30);assert(st_start(&s,ST_TRACK,ms));
    clock10(&s);assert(s.velocity[0]==8 && s.velocity[1]==-8);
    ms+=30;st_target(&s,250,30,1,ms);st_service(&s,ms);
    assert(s.velocity[0]==32 && s.velocity[1]==-32);st_stop(&s);
}
static void limit_tests(void)
{
    StepperControl s;unsigned i;
    init(&s);assert(st_zero(&s));target3(&s,0,0);assert(st_start(&s,ST_TRACK,ms));
    for(i=0;i<800;i++){st_target(&s,0,0,1,ms);clock10(&s);}
    assert(p[0]==160 && p[1]==160 && s.velocity[0]==0 && s.velocity[1]==0);
    for(i=0;i<800;i++){st_target(&s,319,179,1,ms);clock10(&s);}
    assert(p[0]==-160 && p[1]==-160 && s.velocity[0]==0 && s.velocity[1]==0);
    st_stop(&s);
}
static void plant_tests(void)
{
    static const double gains[]={0.25,0.5,1.0,2.0};
    StepperControl s;int history[64][2];unsigned k,delay,n,slot,index;int x=0,y=0;
    for(k=0;k<4;k++)for(delay=0;delay<=15;delay+=5){
        init(&s);memset(history,0,sizeof(history));assert(st_zero(&s));
        target3(&s,184,74);assert(st_start(&s,ST_TRACK,ms));
        for(n=0;n<1500;n++){
            slot=n%64;history[slot][0]=p[0];history[slot][1]=p[1];
            index=(n+64-delay)%64;
            if(n%2==0){
                int jitter=(int)(n%3)-1;
                x=(int)(184+gains[k]*history[index][1])+jitter;
                y=(int)(74+gains[k]*history[index][0])-jitter;
                assert(x>=0 && x<320 && y>=0 && y<180);
                st_target(&s,(unsigned)x,(unsigned)y,1,ms);
            }
            clock10(&s);assert(s.mode==ST_TRACK);
        }
        printf("PLANT gain=%.2f delay_ms=%u final=(%d,%d) p=(%d,%d)\n",gains[k],delay*10,x,y,p[0],p[1]);
        assert(x>=147 && x<=173 && y>=77 && y<=103);
        st_stop(&s);
    }
}
int main(void)
{
    scan_tests();safety_tests();limit_tests();plant_tests();
    puts("STEPPER_V80_PERSISTENT_TRACK_PASS signs deadband freshness loss limits wrap scan plant16");return 0;
}

