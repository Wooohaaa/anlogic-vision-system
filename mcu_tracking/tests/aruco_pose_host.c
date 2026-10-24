#include "aruco_pose.h"
typedef struct {const unsigned char *pixels;} pose_image;
static uint8_t pose_read(void *ctx,unsigned x,unsigned y)
{return ((pose_image *)ctx)->pixels[y*160+x];}
int ua_test_image_pose(const unsigned char *pixels,const ua_aruco_camera *camera,
                       ua_aruco_pose *out,float *corners,int *status)
{
    static ua_aruco_detector detector;static ua_aruco_pose_workspace workspace;
    pose_image im={pixels};unsigned count=0,i;
    if(!ua_aruco_begin(&detector,160,90,pose_read,&im))return -2;
    while(!ua_aruco_step(&detector,64)){if(++count>100000)return -3;}
    *status=ua_aruco_pose_detection(camera,&detector.result,&workspace,out);
    if(!detector.result.code.valid)return -1;
    for(i=0;i<4;i++){corners[2*i]=detector.result.corner[i].x*8;corners[2*i+1]=detector.result.corner[i].y*8;}
    return detector.result.code.id;
}
