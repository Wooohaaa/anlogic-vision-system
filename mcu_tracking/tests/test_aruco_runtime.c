#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include "aruco_dictionary.h"
static uint32_t registers[0x10000/4];
static uint64_t now_ticks;
static uint64_t SysTimer_GetLoadValue(void){return now_ticks;}
static void AlIntr_SetLocalInterrupt(unsigned value){(void)value;}
#define AL_LOG(...) ((void)0)
#define ARUCO_RUNTIME_HOST_TEST 1
#define UA_ARUCO_BASE ((uintptr_t)registers)
#include "../aruco_app/aruco_runtime.c"
static void hardware(void)
{
    if(registers[8/4]==1){registers[4/4]=2;registers[12/4]++;}
    else if(registers[8/4]==2)registers[4/4]=0;
    registers[8/4]=0;
}
int main(void)
{
    unsigned x,y,i;
    volatile unsigned armed=0,dry=0,remaining=0;
    registers[0]=0x41525531;registers[16/4]=(90u<<16)|160u;
    for(y=0;y<90;y++)for(x=0;x<160;x++){
        unsigned value=235;
        if(x>=75 && x<129 && y>=28 && y<82){
            unsigned cx=(x-75)/9,cy=(y-28)/9;
            value=!cx || cx==5 || !cy || cy==5?18:
                (ua_aruco_codes[23]>>((cy-1)*4+cx-1)&1u)?235:18;
        }
        registers[0x1000/4+y*160+x]=value;
    }
#ifdef CAMERA_STEPPER_BUILD
    registers[0x100/4]=0xa55a;registers[0x104/4]=0xa55a;registers[0x108/4]=0xa55a;
    ua_aruco_runtime_init();assert(registers[0x100/4]==0xa55a);
#else
    ua_aruco_runtime_init();assert(registers[0x100/4]==1);
#endif
    now_ticks+=100;ua_aruco_runtime_step(now_ticks,1,&armed,&dry,&remaining,1500,1500);
    assert(!active && !ua_aruco_valid && ua_aruco_pose_status==UA_POSE_DISABLED);
    registers[0x10c/4]=1;
    for(i=0;i<10000 && !ua_aruco_frames;i++){
        now_ticks+=100;ua_aruco_runtime_step(now_ticks,1,&armed,&dry,&remaining,1500,1500);hardware();
    }
    assert(ua_aruco_frames==1 && ua_aruco_valid && ua_aruco_marker_id==23);
    /* Do not append the old 100ms idle after a completed recognition. */
    assert(next_capture<=now_ticks+UA_ARUCO_CAPTURE_PERIOD_US);
    assert(registers[0x110/4]==0xc0000023u); /* valid + screen axes + decimal BCD ID 023 */
    for(i=0;i<4;i++){
        uint32_t corner=registers[(0x114+4*i)/4];
        assert((corner&2047u)==ua_aruco_x[i] && (corner>>11)==ua_aruco_y[i]);
        assert((corner&2047u)<=1279u && (corner>>11)<=719u);
        assert(registers[(0x124+4*i)/4]==edge_equation(i));
    }
    assert(!pose_result.valid && ua_aruco_pose_status==UA_POSE_UNCALIBRATED);
    assert(ua_aruco_axes_mode==2);
    for(i=0;i<4;i++){
        uint32_t point=registers[(0x134+4*i)/4];
        unsigned px=point&2047u,py=point>>11;
        assert(px<=1279u && py<=719u);
    }
    assert((registers[0x138/4]&2047u)>(registers[0x134/4]&2047u));
    assert((registers[0x13c/4]>>11)<(registers[0x134/4]>>11));
    assert((registers[0x140/4]&2047u)>=(registers[0x134/4]&2047u));
    /* Front-facing marker is below/right of the principal point. Its outward
     * normal projects farther down/right, not to a fixed screen-up diagonal. */
    assert((registers[0x140/4]>>11)>(registers[0x134/4]>>11));
    {
        int xerr=(int)(registers[0x138/4]&2047u)-
                 (int)((ua_aruco_x[1]+ua_aruco_x[2])/2u);
        int yerr=(int)(registers[0x13c/4]>>11)-
                 (int)((ua_aruco_y[0]+ua_aruco_y[1])/2u);
        if(xerr<0)xerr=-xerr;
        if(yerr<0)yerr=-yerr;
        /* In this front-facing fixture, half the 120 mm border lands at its edge midpoint. */
        assert(xerr<=3 && yerr<=3);
    }
    {
#ifdef CAMERA_STEPPER_BUILD
        const char *paths[1]={"tmp/v69_stepper/aruco_axes.hex"};
#else
        const char *paths[3]={"tmp/aruco/v39_axes_runtime.hex","tmp/aruco/v38_axes_runtime.hex","tmp/aruco/v37_axes_runtime.hex"};
#endif
        unsigned path;
        for(path=0;path<sizeof(paths)/sizeof(paths[0]);path++){
            FILE *trace=fopen(paths[path],"w");
            assert(trace);
            for(x=0x114;x<=0x14c;x+=4)fprintf(trace,"%08x\n",(unsigned)registers[x/4]);
            fprintf(trace,"%08x\n",(unsigned)registers[0x110/4]);fclose(trace);
        }
    }
    {
        ua_aruco_camera synthetic={1,1280,720,900,900,640,360,0,0,0,0,0,.08f,2};
        assert(ua_aruco_runtime_set_camera(&synthetic));
        /* A second complete recognition must flow into the actual C solver. */
        for(i=0;i<10000 && ua_aruco_frames<2;i++){
            now_ticks+=100;ua_aruco_runtime_step(now_ticks,1,&armed,&dry,&remaining,1500,1500);hardware();
        }
        assert(ua_aruco_frames==2 && pose_result.valid && ua_aruco_pose_status==UA_POSE_OK);
        assert(ua_aruco_axes_mode==1);
        {
            ua_aruco_point expected[4];
            assert(ua_aruco_pose_axes(&synthetic,&pose_result,.04f,expected));
            for(x=0;x<4;x++)assert(registers[(0x134+4*x)/4]==
                (((unsigned)(expected[x].y+.5f)<<11)|(unsigned)(expected[x].x+.5f)));
        }
        assert(registers[0x110/4]==0xc0000023u);
        assert(registers[0x134/4]!=0 && registers[0x138/4]!=0 && registers[0x144/4]!=0);
        assert(pose_result.translation[2]>.15f && pose_result.translation[2]<.19f);
        for(y=0;y<90;y++)for(x=0;x<160;x++)registers[0x1000/4+y*160+x]=70;
        for(i=0;i<10000 && ua_aruco_frames<3;i++){
            now_ticks+=100;ua_aruco_runtime_step(now_ticks,1,&armed,&dry,&remaining,1500,1500);hardware();
        }
        assert(ua_aruco_frames==3 && !ua_aruco_valid && !pose_result.valid);
        assert(ua_aruco_axes_mode==0);
        assert(registers[0x110/4]==0 && registers[0x114/4]==0 &&
               registers[0x118/4]==0 && registers[0x11c/4]==0 && registers[0x120/4]==0);
        for(x=0x134;x<=0x14c;x+=4)assert(registers[x/4]==0);
        assert(ua_aruco_pose_status==UA_POSE_NO_MARKER && pose_result.translation[2]==0 && pose_result.rms_px==0);
        synthetic.width=640;
        assert(!ua_aruco_runtime_set_camera(&synthetic) && !pose_result.valid);
    }
#ifndef CAMERA_STEPPER_BUILD
    assert(registers[0x100/4]==1); // Seeing a marker MUST NOT arm motors.
    armed=1;remaining=7;
    now_ticks+=20000;ua_aruco_runtime_step(now_ticks,1,&armed,&dry,&remaining,1400,1600);
    assert(registers[0x100/4]==7 && registers[0x104/4]==1400 && registers[0x108/4]==1600);
    ua_aruco_hw_off();assert(registers[0x100/4]==1);
    dry=1;
    now_ticks+=20000;ua_aruco_runtime_step(now_ticks,1,&armed,&dry,&remaining,1400,1600);
    assert(registers[0x100/4]==1); // Dry-run cannot pulse motors.
#else
    armed=1;remaining=7;
    now_ticks+=20000;ua_aruco_runtime_step(now_ticks,1,&armed,&dry,&remaining,1400,1600);
    ua_aruco_hw_off();
    assert(registers[0x100/4]==0xa55a && registers[0x104/4]==0xa55a && registers[0x108/4]==0xa55a);
#endif
    armed=0;dry=0;remaining=0;
    now_ticks+=600000;ua_aruco_runtime_step(now_ticks,1,&armed,&dry,&remaining,1500,1500);
    assert(!ua_aruco_valid && ua_aruco_marker_id==255 && !pose_result.valid);
    assert(ua_aruco_pose_status==UA_POSE_STALE && pose_result.translation[2]==0);
    /* A real capture error must not masquerade as missing calibration. */
    registers[4/4]=4;
    now_ticks+=100;ua_aruco_runtime_step(now_ticks,1,&armed,&dry,&remaining,1500,1500);
    assert(ua_aruco_pose_status==UA_POSE_CAPTURE_ERROR && !pose_result.valid && pose_result.translation[2]==0);
    /* Toggle OFF during an active scan, clear every old output, then restart. */
    active=1;ua_aruco_valid=1;ua_aruco_marker_id=23;ua_aruco_x[0]=123;
    pose_result.valid=1;pose_result.translation[2]=.18f;
    registers[0x10c/4]=0;
    now_ticks+=100;ua_aruco_runtime_step(now_ticks,1,&armed,&dry,&remaining,1500,1500);
    assert(!active && registers[8/4]==2 && !ua_aruco_valid && ua_aruco_marker_id==255);
    assert(registers[0x110/4]==0 && registers[0x114/4]==0 &&
           registers[0x118/4]==0 && registers[0x11c/4]==0 && registers[0x120/4]==0);
    assert(!pose_result.valid && pose_result.translation[2]==0 && ua_aruco_x[0]==0);
    assert(ua_aruco_pose_status==UA_POSE_DISABLED);hardware();
    for(i=0;i<20;i++){now_ticks+=100;ua_aruco_runtime_step(now_ticks,1,&armed,&dry,&remaining,1500,1500);hardware();}
    assert(!active && !registers[8/4]);
    registers[0x10c/4]=1;
    now_ticks+=100;ua_aruco_runtime_step(now_ticks,1,&armed,&dry,&remaining,1500,1500);
    assert(active && registers[8/4]==1);
    puts("ARUCO_RUNTIME_PASS estimated_normal_axes calibrated_axes bounded_start_period_no_post_completion_idle capture_error shared_control_off_dry_stop_no_auto_arm_stale switch_off_clear_restart");
    return 0;
}
