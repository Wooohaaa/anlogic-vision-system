#include "aruco_capture.h"
#include <string.h>
static uint8_t pixel(void *context,unsigned x,unsigned y)
{
    ua_aruco_capture *job=(ua_aruco_capture *)context;
    unsigned index=y*job->width+x;
    unsigned packed=job->gray4[index>>1];
    unsigned value=(index&1u)?(packed>>4):(packed&15u);
    return (uint8_t)(value*17u);
}
int ua_aruco_capture_begin(ua_aruco_capture *job,ua_aruco_read32 rd,ua_aruco_write32 wr,void *ctx,uint32_t now)
{
    uint32_t dimensions;
    if(!job)return 0;
    job->state=4;job->capture_index=0;job->read=0;job->write=0;job->bus_context=0;
    job->width=0;job->height=0;job->deadline=0;job->frame_sequence=0;
    memset(&job->result,0,sizeof(job->result));job->result.code.id=255;
    if(!rd || !wr || rd(ctx,0)!=0x41525531u || (rd(ctx,4)&1u))return 0;
    dimensions=rd(ctx,16);job->width=dimensions&0xffffu;job->height=dimensions>>16;
    if(job->width<18 || job->width>160 || job->height<18 || job->height>90)return 0;
    job->read=rd;job->write=wr;job->bus_context=ctx;job->deadline=now+2000u;
    wr(ctx,8,2);wr(ctx,8,1);job->state=1;return 1;
}
int ua_aruco_capture_step(ua_aruco_capture *job,uint32_t now,unsigned budget)
{
    if(!job || job->state==4)return -1;
    if(job->state==3)return 1;
    if((int32_t)(now-job->deadline)>=0){job->write(job->bus_context,8,2);job->state=4;return -1;}
    if(job->state==1) {
        uint32_t status=job->read(job->bus_context,4);
        if(status&4u){job->state=4;return -1;}
        if(!(status&2u))return 0;
        job->frame_sequence=job->read(job->bus_context,12);
        job->capture_index=0;
        job->state=5;
    }
    if(job->state==5) {
        unsigned total=job->width*job->height;
        while(budget-- && job->capture_index<total) {
            unsigned index=job->capture_index++;
            unsigned value=(job->read(job->bus_context,0x1000u+4u*index)>>4)&15u;
            if(index&1u)job->gray4[index>>1]=(uint8_t)((job->gray4[index>>1]&15u)|(value<<4));
            else job->gray4[index>>1]=(uint8_t)((job->gray4[index>>1]&0xf0u)|value);
        }
        if(job->capture_index<total)return 0;
        if(job->read(job->bus_context,12)!=job->frame_sequence || !(job->read(job->bus_context,4)&2u)){
            job->write(job->bus_context,8,2);job->state=4;return -1;
        }
        if(!ua_aruco_begin(&job->detector,job->width,job->height,pixel,job)){job->state=4;return -1;}
        job->state=2;
        return 0;
    }
    if(ua_aruco_step(&job->detector,budget)) {
        if(job->read(job->bus_context,12)!=job->frame_sequence || !(job->read(job->bus_context,4)&2u)){
            job->write(job->bus_context,8,2);job->state=4;return -1;
        }
        job->result=job->detector.result;job->write(job->bus_context,8,2);job->state=3;return 1;
    }
    return 0;
}
