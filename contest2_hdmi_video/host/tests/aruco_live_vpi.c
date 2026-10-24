/* Windows/Icarus live co-simulation. Win32 fibers let synchronous production
 * C MMIO callbacks suspend until actual RTL AHB completion, on ONE OS thread.
 * Host C, not a RISC-V instruction/cycle model. No physical hardware access. */
#include <windows.h>
#include <vpi_user.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <inttypes.h>
#include "aruco_log.h"
static uint32_t ua_cosim_read32(uint32_t offset);
static void ua_cosim_write32(uint32_t offset,uint32_t value);
static uint64_t simulation_ps(void);
static uint64_t SysTimer_GetLoadValue(void){return simulation_ps()/20000u;}
static void AlIntr_SetLocalInterrupt(unsigned value){(void)value;}
static void cosim_log(const char *format,...);
#define AL_LOG_LEVEL_NOTICE 0
#define AL_LOG(level,...) ((void)(level),cosim_log(__VA_ARGS__))
#define ARUCO_RUNTIME_HOST_TEST 1
// Generated from the authoritative runtime: only the two raw MMIO accessors
// are instrumented. Production MCU source/ELF remain unchanged.
#include UA_RUNTIME_SOURCE

static void *sim_fiber,*firmware_fiber;
static int finished;
static vpiHandle bus_addr_handle,h_trans,h_write,h_data,h_out,h_ready,h_err,h_scene;
static vpiHandle h_source_pass;
static uint64_t bus_period_ps,transactions,pixel_reads,wait_edges;
static uint64_t frozen_reads;
static uint8_t expected[32][14400];
static unsigned scenes,current_scene;
static FILE *results,*uart_file;
static char workdir[1024];
static int wanted[32],calibrated[32];
static uint32_t case_mask=0xffffffffu;
static unsigned pixel_seen[14400],unique_pixels;

static uint64_t simulation_ps(void)
{s_vpi_time time;memset(&time,0,sizeof(time));time.type=vpiSimTime;vpi_get_time(0,&time);return ((uint64_t)time.high<<32)|time.low;}
static unsigned get(vpiHandle handle)
{
    s_vpi_value value;value.format=vpiVectorVal;vpi_get_value(handle,&value);
    if(value.value.vector[0].bval){vpi_printf("LIVE_COSIM_FAIL X/Z on bus\n");finished=-1;SwitchToFiber(sim_fiber);}
    return (unsigned)value.value.vector[0].aval;
}
static void put(vpiHandle handle,unsigned number)
{s_vpi_value value;value.format=vpiIntVal;value.value.integer=(PLI_INT32)number;vpi_put_value(handle,&value,0,vpiNoDelay);}
static void fail(const char *message)
{vpi_printf("LIVE_COSIM_FAIL scene=%u time_ps=%"PRIu64" %s\n",current_scene,simulation_ps(),message);if(results)fflush(results);finished=-1;SwitchToFiber(sim_fiber);abort();}
static PLI_INT32 resume_firmware(p_cb_data callback);
static void suspend_for(uint64_t ps)
{
    s_vpi_time time; s_cb_data callback;
    memset(&time,0,sizeof(time));time.type=vpiSimTime;time.high=(PLI_UINT32)(ps>>32);time.low=(PLI_UINT32)ps;
    memset(&callback,0,sizeof(callback));callback.reason=cbAfterDelay;callback.cb_rtn=resume_firmware;callback.time=&time;
    vpi_register_cb(&callback);SwitchToFiber(sim_fiber);
}
static void next_edge(int rising)
{
    uint64_t now=simulation_ps(),offset=(rising?bus_period_ps/2:bus_period_ps)+1000;
    uint64_t target=(now/bus_period_ps)*bus_period_ps+offset;
    if(target<=now)target+=bus_period_ps;
    suspend_for(target-now);
}
static uint32_t transaction(unsigned write_word,uint32_t offset,uint32_t value)
{
    unsigned guard=0;uint32_t result;
    next_edge(0);while(!get(h_ready)){if(++guard>50)fail("idle HREADY timeout");next_edge(0);}
    // CPU 0x80000000 window is exported by the hard MCU as HADDR[30:0].
    put(bus_addr_handle,(0x80000000u+offset)&0x7fffffffu);put(h_write,write_word);put(h_trans,2);
    next_edge(0);put(h_trans,0);put(h_data,value);
    next_edge(1);guard=0;
    while(!get(h_ready)){if(++guard>50)fail("data HREADY timeout");wait_edges++;next_edge(1);}
    if(get(h_err))fail("actual RTL returned HRESP error");
    result=get(h_out);transactions++;
    next_edge(0);put(h_data,0);return result;
}
static uint32_t ua_cosim_read32(uint32_t offset)
{
    uint32_t value=transaction(0,offset,0);
    if(offset>=0x1000 && offset<0x1000+14400*4){
        unsigned index=(offset-0x1000)/4;pixel_reads++;
        if(get(h_source_pass)==1)frozen_reads++;
        if(value!=expected[current_scene][index])fail("RGB grayscale/packing/frozen snapshot mismatch");
        if(!pixel_seen[index]){pixel_seen[index]=1;unique_pixels++;}
    }
    return value;
}
static void ua_cosim_write32(uint32_t offset,uint32_t value)
{if(offset==0x100 && value!=1)fail("runtime attempted non-OFF PWM control");(void)transaction(1,offset,value);}
static void log_byte(void *context,char byte)
{(void)context;if(uart_file)fputc(byte,uart_file);}
static void cosim_log(const char *format,...)
{va_list args;va_start(args,format);if(ua_log_vformat(log_byte,0,format,args)<0)fail("integer UART format unsupported");va_end(args);}
static void load_inputs(void)
{
    char path[1200];FILE *file;unsigned i,j,value;
    snprintf(path,sizeof(path),"%s/scenes.txt",workdir);file=fopen(path,"r");if(!file)fail("cannot open scene list");
    if(fscanf(file,"%u",&scenes)!=1 || !scenes || scenes>32)fail("scene count");
    for(i=0;i<scenes;i++)if(fscanf(file,"%d %d",&wanted[i],&calibrated[i])!=2)fail("scene expectations");
    fclose(file);
    snprintf(path,sizeof(path),"%s/expected_gray.hex",workdir);file=fopen(path,"r");if(!file)fail("cannot open expected gray");
    for(i=0;i<scenes;i++)for(j=0;j<14400;j++){if(fscanf(file,"%x",&value)!=1)fail("gray fixture length");expected[i][j]=(uint8_t)value;}
    fclose(file);
    snprintf(path,sizeof(path),"%s/results_%u.jsonl",workdir,(unsigned)(1000000u/bus_period_ps));results=fopen(path,"w");if(!results)fail("results path");
    snprintf(path,sizeof(path),"%s/uart_%u.txt",workdir,(unsigned)(1000000u/bus_period_ps));uart_file=fopen(path,"w");if(!uart_file)fail("UART path");
}
static void WINAPI firmware_main(void *unused)
{
    volatile unsigned armed=0,dry=0,remaining=0;unsigned i;
    ua_aruco_camera camera={1,1280,720,900,900,640,360,0,0,0,0,0,.08f,4};
    (void)unused;load_inputs();ua_aruco_runtime_init();if(!enabled)fail("MCU runtime signature failed");
    for(i=0;i<scenes;i++){
        if(!(case_mask&(1u<<i)))continue;
        unsigned old_frames=ua_aruco_frames,old_failures=ua_aruco_failures,j;
        uint64_t first=simulation_ps(),old_transactions=transactions,old_pixels=pixel_reads;
        uint64_t old_frozen=frozen_reads;
        current_scene=i;put(h_scene,i);memset(pixel_seen,0,sizeof(pixel_seen));unique_pixels=0;
        if(calibrated[i]){if(!ua_aruco_runtime_set_camera(&camera))fail("synthetic calibration rejected");}
        else (void)ua_aruco_runtime_set_camera(0);
        while(ua_aruco_frames==old_frames && ua_aruco_failures==old_failures){
            uint64_t now=SysTimer_GetLoadValue();
            ua_aruco_runtime_step(now,50,&armed,&dry,&remaining,1500,1500);
            if(simulation_ps()-first>UINT64_C(1000000000000))fail("MCU frame deadline");
            if(!active && next_capture>now && ua_aruco_frames==old_frames)suspend_for((next_capture-now)*20000);
            else suspend_for(job.state==1?UINT64_C(20000000):UINT64_C(2000000));
        }
        if(ua_aruco_failures!=old_failures)fail("actual MCU capture state machine failed");
        if(job.frame_sequence!=ua_aruco_frames)fail("stale/torn capture sequence");
        if((wanted[i]<0 && ua_aruco_valid) || (wanted[i]>=0 && (!ua_aruco_valid || ua_aruco_marker_id!=(unsigned)wanted[i])))fail("MCU detection result mismatch");
        if((!calibrated[i]||wanted[i]<0) && pose_result.valid)fail("uncalibrated/removed pose not cleared");
        if(wanted[i]<0 && (ua_aruco_pose_status!=UA_POSE_NO_MARKER ||
           pose_result.translation[0]!=0 || pose_result.translation[1]!=0 ||
           pose_result.translation[2]!=0 || pose_result.rms_px!=0))fail("removed marker retained stale pose/status");
        if(armed||remaining||(transaction(0,0x100,0)&3u)!=1)fail("PWM OFF safety");
        if(unique_pixels!=14400)fail("MCU did not read every frozen snapshot pixel");
        if(frozen_reads==old_frozen)fail("frozen frame not exercised by live background writes");
        ua_aruco_runtime_status();
        fprintf(results,"{\"scene\":%u,\"expected\":%d,\"id\":%d,\"calibrated\":%d,\"valid\":%u,\"pose_valid\":%u,\"pose_status\":%d,\"rms_px\":%.8g,\"xyz_m\":[%.8g,%.8g,%.8g],\"corners720\":[",i,wanted[i],ua_aruco_valid?(int)ua_aruco_marker_id:-1,calibrated[i],ua_aruco_valid,pose_result.valid,ua_aruco_pose_status,pose_result.rms_px,pose_result.translation[0],pose_result.translation[1],pose_result.translation[2]);
        for(j=0;j<4;j++)fprintf(results,"%s[%u,%u]",j?",":"",ua_aruco_x[j],ua_aruco_y[j]);
        fprintf(results,"],\"rotation\":[");for(j=0;j<9;j++)fprintf(results,"%s%.8g",j?",":"",pose_result.rotation[j]);
        fprintf(results,"],\"quaternion\":[");for(j=0;j<4;j++)fprintf(results,"%s%.8g",j?",":"",pose_result.quaternion[j]);
        fprintf(results,"],\"ahb_transactions\":%"PRIu64",\"pixel_reads\":%"PRIu64",\"unique_pixels\":%u,\"frozen_reads_during_distractor\":%"PRIu64",\"snapshot_sequence\":%u,\"simulation_elapsed_ms\":%.6f,\"cpu_timing_modeled\":false,\"pwm_off\":true}\n",transactions-old_transactions,pixel_reads-old_pixels,unique_pixels,frozen_reads-old_frozen,job.frame_sequence,(double)(simulation_ps()-first)/1e9);
        fflush(results);fflush(uart_file);
        vpi_printf("LIVE_SCENE_PASS bus=%u scene=%u id=%d pose=%u transactions=%"PRIu64"\n",(unsigned)(1000000u/bus_period_ps),i,ua_aruco_valid?(int)ua_aruco_marker_id:-1,pose_result.valid,transactions-old_transactions);
    }
    fclose(results);results=0;fclose(uart_file);uart_file=0;
    vpi_printf("ARUCO_LIVE_C_RTL_COSIM_PASS scenes=%u transactions=%"PRIu64" pixel_reads=%"PRIu64" wait_edges=%"PRIu64" host_C_not_hard_MCU\n",ua_aruco_frames,transactions,pixel_reads,wait_edges);
    finished=1;SwitchToFiber(sim_fiber);
}
static PLI_INT32 resume_firmware(p_cb_data callback)
{(void)callback;SwitchToFiber(firmware_fiber);if(finished)vpi_control(vpiFinish,finished<0?1:0);return 0;}
static vpiHandle find(const char *name)
{char path[128];vpiHandle handle;snprintf(path,sizeof(path),"tb_aruco_live.%s",name);handle=vpi_handle_by_name(path,0);if(!handle){vpi_printf("Missing %s\n",path);exit(2);}return handle;}
static PLI_INT32 start(p_cb_data callback)
{
    s_vpi_vlog_info info;unsigned i;const char *directory=0;
    s_vpi_time time; s_cb_data cb;(void)callback;
    vpi_get_vlog_info(&info);for(i=0;i<(unsigned)info.argc;i++){
        if(!strncmp(info.argv[i],"+WORK=",6))directory=info.argv[i]+6;
        if(!strncmp(info.argv[i],"+CASEMASK=",10))case_mask=(uint32_t)strtoul(info.argv[i]+10,0,0);
    }
    if(!directory||strlen(directory)>=sizeof(workdir)){vpi_printf("+WORK path required\n");vpi_control(vpiFinish,1);return 0;}
    strcpy(workdir,directory);if(vpi_get(vpiTimePrecision,0)!=-12){vpi_printf("1ps precision required\n");vpi_control(vpiFinish,1);return 0;}
    bus_addr_handle=find("addr");h_trans=find("trans");h_write=find("write");h_data=find("data");h_out=find("out");h_ready=find("ready");h_err=find("err");h_scene=find("scene");
    h_source_pass=find("pass");
    bus_period_ps=(uint64_t)get(find("BUS_HALF_NS"))*2000u;
    sim_fiber=IsThreadAFiber()?GetCurrentFiber():ConvertThreadToFiber(0);
    firmware_fiber=CreateFiber(128*1024,firmware_main,0);
    if(!sim_fiber||!firmware_fiber){vpi_printf("Fiber setup failed\n");vpi_control(vpiFinish,1);return 0;}
    memset(&time,0,sizeof(time));time.type=vpiSimTime;time.low=1000000;
    memset(&cb,0,sizeof(cb));cb.reason=cbAfterDelay;cb.cb_rtn=resume_firmware;cb.time=&time;vpi_register_cb(&cb);return 0;
}
static void register_cosim(void)
{s_cb_data callback;memset(&callback,0,sizeof(callback));callback.reason=cbStartOfSimulation;callback.cb_rtn=start;vpi_register_cb(&callback);}
DLLEXPORT void (*vlog_startup_routines[])(void)={register_cosim,0};
