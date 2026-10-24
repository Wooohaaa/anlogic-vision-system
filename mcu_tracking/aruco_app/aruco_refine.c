#include "aruco_refine.h"
#include <math.h>
int ua_aruco_refine(ua_aruco_pixel pixel,void *context,unsigned width,unsigned height,
                    ua_aruco_point q[4])
{
    float line[4][3];ua_aruco_point refined[4];unsigned i,j,k;
    if(!pixel||!q||width<2||height<2)return 0;
    for(i=0;i<4;i++){
        unsigned n=(i+1)%4,count=0;float dx=q[n].x-q[i].x,dy=q[n].y-q[i].y;
        float length=sqrtf(dx*dx+dy*dy),nx,ny,st=0,so=0,stt=0,sto=0,soo=0,a,b,det;
        if(length<12)return 0;
        nx=dy/length;ny=-dx/length;
        for(j=0;j<8;j++){
            float t=(j+2)/11.0f,x=q[i].x+dx*t,y=q[i].y+dy*t;
            float values[9],low=255,high=0,best=0,offset=0,mid;
            int valid=1;
            for(k=0;k<9;k++){
                float sx=x+nx*((float)k-4),sy=y+ny*((float)k-4),ax,ay;
                int px=(int)floorf(sx),py=(int)floorf(sy);
                if(px<0||py<0||(unsigned)px+1>=width||(unsigned)py+1>=height){valid=0;break;}
                ax=sx-px;ay=sy-py;
                values[k]=(1-ay)*((1-ax)*pixel(context,px,py)+ax*pixel(context,px+1,py))+
                    ay*((1-ax)*pixel(context,px,py+1)+ax*pixel(context,px+1,py+1));
                if(values[k]<low)low=values[k];
                if(values[k]>high)high=values[k];
            }
            if(!valid||high-low<12)continue;
            mid=(low+high)*.5f;
            for(k=0;k<8;k++){
                float rise=values[k+1]-values[k];
                if(values[k]<=mid&&values[k+1]>mid&&rise>8){
                    best=rise;offset=(float)k-4+(mid-values[k])/rise;
                }
            }
            if(best<8)continue;
            st+=t;so+=offset;stt+=t*t;sto+=t*offset;soo+=offset*offset;count++;
        }
        det=count*stt-st*st;if(count<5||det<.01f)return 0;
        b=(count*sto-st*so)/det;a=(so-b*st)/count;
        if(soo-a*so-b*sto>.20f*count)return 0;
        /* Refined edge from q[i]+normal*a to q[next]+normal*(a+b). */
        {float ex=dx+nx*b,ey=dy+ny*b;
         line[i][0]=ey;line[i][1]=-ex;
         line[i][2]=ey*(q[i].x+nx*a)-ex*(q[i].y+ny*a);}
    }
    for(i=0;i<4;i++){
        unsigned p=(i+3)%4;float det=line[p][0]*line[i][1]-line[i][0]*line[p][1],dx,dy;
        if(fabsf(det)<1)return 0;
        refined[i].x=(line[p][2]*line[i][1]-line[i][2]*line[p][1])/det;
        refined[i].y=(line[p][0]*line[i][2]-line[i][0]*line[p][2])/det;
        dx=refined[i].x-q[i].x;dy=refined[i].y-q[i].y;
        if(!isfinite(refined[i].x)||!isfinite(refined[i].y)||dx*dx+dy*dy>36||
           refined[i].x<1||refined[i].y<1||refined[i].x>=width-1||refined[i].y>=height-1)return 0;
    }
    for(i=0;i<4;i++)q[i]=refined[i];
    return 1;
}
