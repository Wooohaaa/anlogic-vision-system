#include <assert.h>
#include <stdio.h>
#include "aruco_capture.h"
#include "aruco_dictionary.h"
typedef struct {unsigned busy,ready,sequence,bad_signature,stuck,change_sequence;} device;
static uint32_t read32(void *ctx,uint32_t offset)
{
    device *dev=ctx;
    if(!offset)return dev->bad_signature?0:0x41525531u;
    if(offset==4){if(dev->busy && !dev->stuck){dev->busy--;if(!dev->busy){dev->ready=1;dev->sequence++;}}return dev->busy?1:dev->ready?2:0;}
    if(offset==12){unsigned s=dev->sequence;if(dev->change_sequence)dev->sequence++;return s;}
    if(offset==16)return (90u<<16)|160u;
    assert(offset>=0x1000 && offset<0x1000+14400*4 && !(offset&3));
    {unsigned n=(offset-0x1000)/4,x=n%160,y=n/160,cx,cy;
     assert(dev->ready);
     if(x<45 || x>=99 || y<16 || y>=70)return 235;
     cx=(x-45)/9;cy=(y-16)/9;
     if(!cx || cx==5 || !cy || cy==5)return 18;
     return (ua_aruco_codes[23]>>((cy-1)*4+cx-1)&1u)?235:18;}
}
static void write32(void *ctx,uint32_t offset,uint32_t value)
{
    device *dev=ctx;assert(offset==8);
    if(value==2)dev->ready=0;
    else {assert(value==1 && !dev->ready && !dev->busy);dev->busy=3;}
}
int main(void)
{
    static ua_aruco_capture job;device dev={0};unsigned i;int result=0;
    assert(ua_aruco_capture_begin(&job,read32,write32,&dev,0));
    for(i=0;i<1500 && !result;i++)result=ua_aruco_capture_step(&job,i,64);
    assert(result==1 && job.result.code.valid && job.result.code.id==23 && !dev.ready);
    dev.bad_signature=1;assert(!ua_aruco_capture_begin(&job,read32,write32,&dev,0));dev.bad_signature=0;
    dev.stuck=1;assert(ua_aruco_capture_begin(&job,read32,write32,&dev,0xfffffff0u));
    assert(ua_aruco_capture_step(&job,0xfffffff5u,64)==0);
    assert(ua_aruco_capture_step(&job,2000,64)==-1);
    dev.busy=0;dev.stuck=0;dev.change_sequence=1;result=0;
    assert(ua_aruco_capture_begin(&job,read32,write32,&dev,0));
    for(i=0;i<1500 && !result;i++)result=ua_aruco_capture_step(&job,i,64);
    assert(result==-1 && !job.result.code.valid && !dev.ready);
    printf("ARUCO_CAPTURE_C_PASS id23_release_signature_timeout_wrap_torn_rejection workspace=%u\n",(unsigned)sizeof(job));
    return 0;
}
