#ifndef ARUCO_RUNTIME_HOST_TEST
#include "al_core.h"
#include "al_rv_systimer.h"
#include "al_intr.h"
#endif
#include "aruco_capture.h"
#include "aruco_runtime.h"
#include "aruco_camera_config.h"
#include <string.h>
#ifndef UA_ARUCO_BASE
#define UA_ARUCO_BASE ((uintptr_t)0x80000000u) /* FD SDK AHBDemo fabric window */
#endif
static ua_aruco_capture job;
static ua_aruco_camera pose_camera;
static ua_aruco_pose_workspace pose_workspace;
static ua_aruco_pose pose_result;
volatile int ua_aruco_pose_status=UA_POSE_UNCALIBRATED;
volatile unsigned ua_aruco_pose_max_us;
static void invalidate_pose(int reason)
{
    if(pose_result.valid || ua_aruco_pose_status!=reason)memset(&pose_result,0,sizeof(pose_result));
    ua_aruco_pose_status=reason;
}
int ua_aruco_runtime_set_camera(const ua_aruco_camera *camera)
{
    memset(&pose_result,0,sizeof(pose_result));ua_aruco_pose_status=UA_POSE_UNCALIBRATED;
    if(!ua_aruco_camera_valid(camera)||camera->width!=1280||camera->height!=720){
        pose_camera.calibrated=0;return 0;
    }
    pose_camera=*camera;ua_aruco_pose_status=UA_POSE_NO_MARKER;return 1;
}
static unsigned enabled,active,overlay_published_valid;
static uint64_t next_capture,next_pwm,last_result;
/* Rate limit starts, not idle after completion. If work already consumed the
 * period, the next call can request a fresh frame. Peripheral service remains
 * cooperative and the existing 64-node step budget is unchanged. */
#define UA_ARUCO_CAPTURE_PERIOD_US 40000u
volatile unsigned ua_aruco_frames,ua_aruco_failures,ua_aruco_valid,ua_aruco_marker_id=255;
volatile unsigned ua_aruco_x[4],ua_aruco_y[4],ua_aruco_step_max_us;
volatile unsigned ua_aruco_axes_mode; /* 0=absent, 1=calibrated, 2=estimated K */
static uint32_t rd(void *context,uint32_t offset)
{(void)context;return *(volatile uint32_t *)(UA_ARUCO_BASE+offset);}
static void wr(void *context,uint32_t offset,uint32_t value)
{(void)context;*(volatile uint32_t *)(UA_ARUCO_BASE+offset)=value;}
static int32_t round_div_s32(int32_t numerator,int32_t denominator)
{
    if(denominator<0){denominator=-denominator;numerator=-numerator;}
    if(numerator>=0)return (numerator+denominator/2)/denominator;
    return -((-numerator+denominator/2)/denominator);
}
static uint32_t line_equation(unsigned x0,unsigned y0,unsigned x1,unsigned y1)
{
    int32_t dx=(int32_t)x1-(int32_t)x0;
    int32_t dy=(int32_t)y1-(int32_t)y0;
    int32_t ax=dx<0?-dx:dx,ay=dy<0?-dy:dy;
    unsigned major_x=(ax>=ay);
    int32_t major=major_x?dx:dy,minor=major_x?dy:dx;
    int32_t major_origin=major_x?(int32_t)x0:(int32_t)y0;
    int32_t minor_origin=major_x?(int32_t)y0:(int32_t)x0;
    int32_t slope_q10=major?round_div_s32(minor*1024,major):0;
    int32_t intercept_q1=round_div_s32(minor_origin*2048-slope_q10*major_origin*2,1024);
    return ((uint32_t)major_x<<25)|(((uint32_t)intercept_q1&0x1fffu)<<12)|
           ((uint32_t)slope_q10&0xfffu);
}
static uint32_t edge_equation(unsigned edge)
{unsigned next=(edge+1u)&3u;return line_equation(ua_aruco_x[edge],ua_aruco_y[edge],ua_aruco_x[next],ua_aruco_y[next]);}
/* Keep measured calibration separate from the explicitly estimated display
 * camera. Never substitute a fixed screen direction for the plane normal. */
static int display_axes(unsigned valid,unsigned px[4],unsigned py[4])
{
    ua_aruco_point corners[4],points[4];
    unsigned i,normal_valid;
    ua_aruco_axes_mode=0;
    if(!valid)return 0;
    if(pose_camera.calibrated){
        if(!ua_aruco_pose_axes(&pose_camera,&pose_result,pose_camera.side_m*.5f,points))return 0;
        ua_aruco_axes_mode=1;
    } else {
        for(i=0;i<4;i++){corners[i].x=(float)ua_aruco_x[i];corners[i].y=(float)ua_aruco_y[i];}
        if(!ua_aruco_axes_preview(corners,1280,720,UA_ARUCO_AXES_NOMINAL_FOCAL_PX,
                                  &pose_workspace,points,&normal_valid))return 0;
        ua_aruco_axes_mode=normal_valid?2:3;
    }
    for(i=0;i<4;i++){px[i]=(unsigned)(points[i].x+.5f);py[i]=(unsigned)(points[i].y+.5f);}
    return 1;
}
/* Publish a coherent result bank to the FPGA OSD. The status register is
 * written last and toggles the hardware commit bit after corners/edge lines are stable. */
static void publish_overlay(void)
{
    unsigned valid=ua_aruco_valid && ua_aruco_marker_id<256u;
    unsigned id=0,i;
    unsigned px[4]={0},py[4]={0};
    unsigned axes_valid=display_axes(valid,px,py);
    for(i=0;i<4;i++){
        wr(0,0x134u+4u*i,(py[i]<<11)|px[i]);
    }
    for(i=0;i<3;i++)wr(0,0x144u+4u*i,axes_valid?line_equation(px[0],py[0],px[i+1],py[i+1]):0u);
    if(valid){
        id=ua_aruco_marker_id;
    }
    for(i=0;i<4;i++){
        uint32_t corner=valid?(((ua_aruco_y[i]&0x7ffu)<<11)|(ua_aruco_x[i]&0x7ffu)):0u;
        wr(0,0x114u+4u*i,corner);
        wr(0,0x124u+4u*i,valid?edge_equation(i):0u);
    }
    wr(0,0x110,(valid?0x80000000u:0u)|(axes_valid?0x40000000u:0u)|(((id/100u)%10u)<<8)|
                       (((id/10u)%10u)<<4)|(id%10u));
    overlay_published_valid=valid;
}
void ua_aruco_hw_off(void){
#ifndef CAMERA_STEPPER_BUILD
    if(enabled)wr(0,0x100,1);
#endif
}
void ua_aruco_runtime_init(void)
{
#ifndef ARUCO_RUNTIME_HOST_TEST
    // Match the FPGA 50MHz AHB clock and PWM timing. SDK platform startup
    // currently programs AHB_DIV=2 (25MHz); normalize before any Fabric access.
    // Register definition/encoding: PH1P35 SDK al_chip.S, DIV-1 at 0x18000104.
    *(volatile uint32_t *)(uintptr_t)0x18000104u=0;
    __asm__ volatile("fence iorw,iorw" ::: "memory");
#endif
    enabled=rd(0,0)==0x41525531u;active=0;overlay_published_valid=0;
    memset(&pose_result,0,sizeof(pose_result));ua_aruco_pose_status=UA_POSE_UNCALIBRATED;
#if UA_ARUCO_CAMERA_AVAILABLE
    {const ua_aruco_camera calibrated=UA_ARUCO_CAMERA_INITIALIZER;
     ua_aruco_runtime_set_camera(&calibrated);}
#endif
    if(enabled){
        ua_aruco_hw_off(); /* No servo-bank writes in stepper firmware. */
        ua_aruco_valid=0;ua_aruco_marker_id=255;
        publish_overlay();
    }
}
void ua_aruco_runtime_status(void)
{
    AL_LOG(AL_LOG_LEVEL_NOTICE,"ARUCO enabled=%u valid=%u id=%u frames=%u errors=%u step_max_us=%u hw=%u\r\n",
        enabled,ua_aruco_valid,ua_aruco_marker_id,ua_aruco_frames,ua_aruco_failures,ua_aruco_step_max_us,enabled?(unsigned)rd(0,0x100):0);
    if(ua_aruco_valid)AL_LOG(AL_LOG_LEVEL_NOTICE,"ARUCO corners720=(%u,%u),(%u,%u),(%u,%u),(%u,%u)\r\n",
        ua_aruco_x[0],ua_aruco_y[0],ua_aruco_x[1],ua_aruco_y[1],
        ua_aruco_x[2],ua_aruco_y[2],ua_aruco_x[3],ua_aruco_y[3]);
    AL_LOG(AL_LOG_LEVEL_NOTICE,"POSE calib=%u valid=%u status=%d max_us=%u\r\n",
        pose_camera.calibrated,pose_result.valid,ua_aruco_pose_status,ua_aruco_pose_max_us);
    AL_LOG(AL_LOG_LEVEL_NOTICE,"AXES mode=%u nominal_f_px=%u (0=none 1=calibrated 2=estimated 3=planar-only)\r\n",
        ua_aruco_axes_mode,(unsigned)UA_ARUCO_AXES_NOMINAL_FOCAL_PX);
    if(pose_result.valid)AL_LOG(AL_LOG_LEVEL_NOTICE,"POSE xyz_mm=(%d,%d,%d) rms_millipx=%u planar_single=1\r\n",
        (int)(pose_result.translation[0]*1000),(int)(pose_result.translation[1]*1000),
        (int)(pose_result.translation[2]*1000),(unsigned)(pose_result.rms_px*1000));
    if(pose_result.valid)AL_LOG(AL_LOG_LEVEL_NOTICE,"POSE quat_wxyz_x10000=(%d,%d,%d,%d)\r\n",
        (int)(pose_result.quaternion[0]*10000),(int)(pose_result.quaternion[1]*10000),
        (int)(pose_result.quaternion[2]*10000),(int)(pose_result.quaternion[3]*10000));
}
void ua_aruco_runtime_step(uint64_t now,uint64_t ticks_us,const volatile unsigned *armed,
                           const volatile unsigned *dry,const volatile unsigned *remaining,
                           unsigned pulse_a,unsigned pulse_b)
{
    uint32_t ms;int result;uint64_t start,elapsed;
    if(!enabled || !ticks_us)return;
#ifndef CAMERA_STEPPER_BUILD
    if(now>=next_pwm){
        next_pwm=now+ticks_us*20000u;
        // Re-read ISR-shared authorization inside a short critical section.
        // A stale by-value armed argument must not re-arm after a timer fault.
        AlIntr_SetLocalInterrupt(0);
        if(*armed && !*dry && *remaining){wr(0,0x104,pulse_a);wr(0,0x108,pulse_b);wr(0,0x100,7);}
        else wr(0,0x100,1);
        AlIntr_SetLocalInterrupt(1);
    }
#else
    (void)armed;(void)dry;(void)remaining;(void)pulse_a;(void)pulse_b;
#endif
    ms=(uint32_t)(now/(ticks_us*1000u));
    // KEY4 controls vision only. Continue servicing the independent safe PWM
    // authorization above; never arm/stop unrelated peripherals via this key.
    if(!(rd(0,0x10c)&1u)){
        unsigned i;
        if(active)wr(0,8,2); // Release an in-flight/frozen snapshot once.
        active=0;next_capture=now;
        if(overlay_published_valid || ua_aruco_valid){
            ua_aruco_valid=0;ua_aruco_marker_id=255;
            for(i=0;i<4;i++){ua_aruco_x[i]=0;ua_aruco_y[i]=0;}
            publish_overlay();
        }
        invalidate_pose(UA_POSE_DISABLED);return;
    }
    if(active){
        start=SysTimer_GetLoadValue();result=ua_aruco_capture_step(&job,ms,64);
        elapsed=(SysTimer_GetLoadValue()-start)/ticks_us;
        if(elapsed>ua_aruco_step_max_us)ua_aruco_step_max_us=(unsigned)elapsed;
        if(result){
            pose_result.valid=0;
            active=0;
            if(result<0){ua_aruco_failures++;ua_aruco_valid=0;ua_aruco_marker_id=255;invalidate_pose(UA_POSE_CAPTURE_ERROR);publish_overlay();}
            else {
                unsigned i;const ua_aruco_point *corners;
                ua_aruco_frames++;ua_aruco_valid=job.result.code.valid;
                ua_aruco_marker_id=ua_aruco_valid?job.result.code.id:255;
                corners=job.result.refined_valid?job.result.refined_corner:job.result.corner;
                for(i=0;i<4;i++){
                    ua_aruco_x[i]=ua_aruco_valid?(unsigned)(corners[i].x*8.0f+0.5f):0;
                    ua_aruco_y[i]=ua_aruco_valid?(unsigned)(corners[i].y*8.0f+0.5f):0;
                    if(ua_aruco_x[i]>1279u)ua_aruco_x[i]=1279u;
                    if(ua_aruco_y[i]>719u)ua_aruco_y[i]=719u;
                }
                if(ua_aruco_valid){
                    uint64_t pose_start=SysTimer_GetLoadValue();
                    ua_aruco_pose_status=ua_aruco_pose_detection(&pose_camera,&job.result,&pose_workspace,&pose_result);
                    elapsed=(SysTimer_GetLoadValue()-pose_start)/ticks_us;
                    if(elapsed>ua_aruco_pose_max_us)ua_aruco_pose_max_us=(unsigned)elapsed;
                } else invalidate_pose(UA_POSE_NO_MARKER);
                /* One commit carries matching corners, ID and projected axes. */
                publish_overlay();
            }
            last_result=now;
        }
        elapsed=(SysTimer_GetLoadValue()-start)/ticks_us;
        if(elapsed>ua_aruco_step_max_us)ua_aruco_step_max_us=(unsigned)elapsed;
    } else if(now>=next_capture){
        next_capture=now+ticks_us*UA_ARUCO_CAPTURE_PERIOD_US;
        active=ua_aruco_capture_begin(&job,rd,wr,0,ms);
        if(!active){ua_aruco_failures++;ua_aruco_valid=0;ua_aruco_marker_id=255;invalidate_pose(UA_POSE_CAPTURE_ERROR);publish_overlay();}
    }
    if(now-last_result>ticks_us*500000u){
        if(ua_aruco_valid || overlay_published_valid){
            ua_aruco_valid=0;ua_aruco_marker_id=255;
            ua_aruco_x[0]=ua_aruco_x[1]=ua_aruco_x[2]=ua_aruco_x[3]=0;
            ua_aruco_y[0]=ua_aruco_y[1]=ua_aruco_y[2]=ua_aruco_y[3]=0;
            publish_overlay();
        }
        invalidate_pose(UA_POSE_STALE);
    }
}
