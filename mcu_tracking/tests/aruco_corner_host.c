#include "aruco_pose.h"
typedef struct {const unsigned char *data;} corner_image;
static uint8_t corner_pixel(void *context,unsigned x,unsigned y)
{return ((corner_image *)context)->data[y*160+x];}
int ua_test_corner_candidates(const unsigned char *data,const ua_aruco_camera *camera,
                               float *corners,ua_aruco_pose *poses,unsigned *refined)
{
    static ua_aruco_detector d;static ua_aruco_pose_workspace ws;
    corner_image im={data};unsigned i,n=0;ua_aruco_point p[4];
    if(!ua_aruco_begin(&d,160,90,corner_pixel,&im))return -2;
    while(!ua_aruco_step(&d,64)){if(++n>100000)return -3;}
    *refined=d.result.refined_valid;
    if(!d.result.code.valid)return -1;
    for(i=0;i<4;i++){
        corners[2*i]=p[i].x=d.result.corner[i].x*8;
        corners[2*i+1]=p[i].y=d.result.corner[i].y*8;
    }
    (void)ua_aruco_pose_solve(camera,p,&ws,&poses[0]);
    for(i=0;i<4;i++){
        corners[8+2*i]=p[i].x=d.result.refined_corner[i].x*8;
        corners[9+2*i]=p[i].y=d.result.refined_corner[i].y*8;
    }
    (void)ua_aruco_pose_solve(camera,p,&ws,&poses[1]);
    return d.result.code.id;
}
