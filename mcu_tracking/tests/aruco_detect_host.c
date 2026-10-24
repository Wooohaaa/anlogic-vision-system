#include "aruco_detect.h"
typedef struct {const unsigned char *data;unsigned width;} image;
static uint8_t pixel(void *ctx,unsigned x,unsigned y)
{image *im=(image *)ctx;return im->data[y*im->width+x];}
int ua_test_detect(const unsigned char *data,unsigned w,unsigned h,float *corners,unsigned *steps)
{
    static ua_aruco_detector d;image im={data,w};unsigned count=0,i;
    if(!ua_aruco_begin(&d,w,h,pixel,&im))return -2;
    while(!ua_aruco_step(&d,64)){if(++count>100000)return -3;}
    *steps=count;
    if(!d.result.code.valid)return -1;
    for(i=0;i<4;i++){corners[2*i]=d.result.corner[i].x;corners[2*i+1]=d.result.corner[i].y;}
    return d.result.code.id;
}
unsigned ua_test_workspace_size(void){return sizeof(ua_aruco_detector);}
