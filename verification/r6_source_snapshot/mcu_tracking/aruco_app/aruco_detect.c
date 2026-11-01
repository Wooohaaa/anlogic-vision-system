#if defined(__GNUC__) && !defined(__clang__)
/* Keep the bounded detector within TCM without reducing the 2 KiB stack.
 * No fast-math: projection, threshold and strict dictionary rules are unchanged. */
#pragma GCC optimize ("Os")
#endif
#include "aruco_detect.h"
#include "aruco_refine.h"
#include <string.h>
#include <limits.h>
#include <math.h>
static const int8_t direction[16][2]={
 {2,0},{2,1},{1,1},{1,2},{0,2},{-1,2},{-1,1},{-2,1},
 {-2,0},{-2,-1},{-1,-1},{-1,-2},{0,-2},{1,-2},{1,-1},{2,-1}};
static float cross(ua_aruco_point a,ua_aruco_point b,ua_aruco_point c)
{return (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x);}
static unsigned otsu(const uint16_t *hist,unsigned total)
{
    unsigned i,weight=0,threshold=0; float sum=0,partial=0,best=-1;
    for(i=0;i<16;i++)sum+=(float)i*hist[i];
    for(i=0;i<15;i++) {
        float delta,value;weight+=hist[i];partial+=(float)i*hist[i];
        if(!weight || weight==total)continue;
        delta=partial/weight-(sum-partial)/(total-weight);
        value=(float)weight*(total-weight)*delta*delta;
        if(value>best){best=value;threshold=i;}
    }
    return threshold;
}
int ua_aruco_begin(ua_aruco_detector *d,unsigned w,unsigned h,ua_aruco_pixel pixel,void *ctx)
{
    if(!d)return 0;
    memset(d,0,sizeof(*d));d->result.code.id=255;
    if(!pixel || w<18 || h<18 || w>160 || h>90){d->phase=4;return 0;}
    d->width=w;d->height=h;d->pixel=pixel;d->context=ctx;return 1;
}
static int take(ua_aruco_detector *d,unsigned n)
{
    unsigned mask=1u<<(n&7u);
    if(d->visited[n>>3]&mask)return 0;
    if((d->pixel(d->context,n%d->width,n/d->width)>>4)>d->threshold)return 0;
    d->visited[n>>3]|=(uint8_t)mask;
    if(d->queued==UA_ARUCO_QUEUE){d->overflow=1;return 0;}
    d->scratch.queue[d->tail]=(uint16_t)n;d->tail=(d->tail+1u)%UA_ARUCO_QUEUE;d->queued++;
    return 1;
}
static void component_start(ua_aruco_detector *d,unsigned n)
{
    unsigned k;d->head=d->tail=d->queued=d->area=d->overflow=0;
    for(k=0;k<16;k++)d->score[k]=INT_MIN;
    (void)take(d,n);
}
/* Unit-square -> arbitrary convex quadrilateral (not an affine shortcut). */
static int transform(const ua_aruco_point *q,float *m)
{
    float dx=q[0].x-q[1].x+q[2].x-q[3].x;
    float dy=q[0].y-q[1].y+q[2].y-q[3].y;
    float ax=q[1].x-q[2].x,bx=q[3].x-q[2].x;
    float ay=q[1].y-q[2].y,by=q[3].y-q[2].y;
    float det=ax*by-bx*ay,g=0,h=0;
    if(fabsf(det)<0.001f)return 0;
    g=(dx*by-bx*dy)/det;h=(ax*dy-dx*ay)/det;
    m[0]=q[1].x-q[0].x+g*q[1].x;m[1]=q[3].x-q[0].x+h*q[3].x;m[2]=q[0].x;
    m[3]=q[1].y-q[0].y+g*q[1].y;m[4]=q[3].y-q[0].y+h*q[3].y;m[5]=q[0].y;
    m[6]=g;m[7]=h;return 1;
}
static int fit_quad(const ua_aruco_point *p,unsigned n,ua_aruco_point q[4])
{
    /* Extend the strongest aligned raster edges to their intersections rather
     * than clipping a rounded corner by deleting one of its adjacent vertices. */
    float line[4][3];ua_aruco_point out[4];unsigned i,j;
    for(i=0;i<4;i++) {
        float dx=q[(i+1)%4].x-q[i].x,dy=q[(i+1)%4].y-q[i].y;
        float qlen=dx*dx+dy*dy,best=0;unsigned edge=n;
        for(j=0;j<n;j++) {
            float ex=p[(j+1)%n].x-p[j].x,ey=p[(j+1)%n].y-p[j].y;
            float dot=dx*ex+dy*ey,elen=ex*ex+ey*ey;
            if(dot>0 && dot*dot>.80f*qlen*elen && dot*dot>best){best=dot*dot;edge=j;}
        }
        if(edge==n)return 0;
        {ua_aruco_point a=p[edge],b=p[(edge+1)%n];
         line[i][0]=b.y-a.y;line[i][1]=a.x-b.x;line[i][2]=line[i][0]*a.x+line[i][1]*a.y;}
    }
    for(i=0;i<4;i++) {
        unsigned b=(i+3)%4;float det=line[b][0]*line[i][1]-line[i][0]*line[b][1],dx,dy;
        if(fabsf(det)<1)return 0;
        out[i].x=(line[b][2]*line[i][1]-line[i][2]*line[b][1])/det;
        out[i].y=(line[b][0]*line[i][2]-line[i][0]*line[b][2])/det;
        dx=out[i].x-q[i].x;dy=out[i].y-q[i].y;
        if(!isfinite(out[i].x)||!isfinite(out[i].y)||dx*dx+dy*dy>100)return 0;
    }
    for(i=0;i<4;i++)q[i]=out[i];
    return 1;
}
static void verify_quad(ua_aruco_detector *d,ua_aruco_point q[4],unsigned mode)
{
    unsigned i,attempt,edge_quiet=0;int bottom_phase=0,phase_quiet=0;float m[8];uint64_t cells=0,edge_support=0;uint8_t gray[36];ua_aruco_id code;ua_aruco_point v;
    for(i=0;i<4;i++) {
        float dx,dy;v=q[(i+1)%4];dx=v.x-q[i].x;dy=v.y-q[i].y;
        if(q[i].x<0 || q[i].y<0 || q[i].x>=d->width || q[i].y>=d->height || dx*dx+dy*dy<(mode?49:64))return;
        if(cross(q[i],q[(i+1)%4],q[(i+2)%4])<8)return;
        if(q[i].x<1 || q[i].y<1 || q[i].x>=d->width-1 || q[i].y>=d->height-1)edge_quiet=1;
        if(q[i].y>=d->height-4)bottom_phase=1;
    }
    if((!mode && ++d->candidates>32) || (mode && ++d->rescues>32) || !transform(q,m))return;
    /* Preserve both existing decodes first. Only after both fail, try measured
     * subpixel edges. Every path needs an intact border and zero bit errors. */
    code.valid=0;
    for(attempt=0;attempt<3 && !code.valid;attempt++) {
        unsigned low=15,high=0;
        if(attempt==2) {
            if(bottom_phase)phase_quiet=1;
            else {
                if(!ua_aruco_refine(d->pixel,d->context,d->width,d->height,q))break;
                if(!transform(q,m))break;
            }
        } else if(attempt) {
            float x=0,y=0,side=10000;
            for(i=0;i<4;i++) {
                float dx=q[i].x-q[(i+1)%4].x,dy=q[i].y-q[(i+1)%4].y;
                float length2=dx*dx+dy*dy;
                x+=q[i].x*.25f;y+=q[i].y*.25f;
                if(length2<side)side=length2;
            }
            side=(edge_quiet || mode==2)?0.0f:1.0f/sqrtf(side);
            for(i=0;i<4;i++) {
                q[i].x+=(q[i].x-x)*side;q[i].y+=(q[i].y-y)*side;
                if(q[i].x<0 || q[i].y<0 || q[i].x>=d->width || q[i].y>=d->height)return;
            }
            if(!transform(q,m))return;
        }
        cells=0;edge_support=0;
        for(i=0;i<36;i++) {
            unsigned sum=0,a,b;
            for(a=0;a<3;a++)for(b=0;b<3;b++) {
                float u=((float)(i%6)+0.3f+0.2f*b)/6.0f;
                float v0=((float)(i/6)+0.3f+0.2f*a)/6.0f;
                float denom=m[6]*u+m[7]*v0+1.0f;
                int x,y;unsigned value;if(denom<=0.01f)return;
                x=(int)((m[0]*u+m[1]*v0+m[2])/denom+((phase_quiet || (mode==2 && attempt==1))?-0.25f:0.0f)+0.5f);
                y=(int)((m[3]*u+m[4]*v0+m[5])/denom+((phase_quiet || (mode==2 && attempt==1))?-0.5f:0.0f)+0.5f);
                if(x<0 || y<0 || (unsigned)x>=d->width || (unsigned)y>=d->height)return;
                value=d->pixel(d->context,(unsigned)x,(unsigned)y)>>4;
                sum+=(attempt && !(mode==2 && attempt==1))?value:(value>d->threshold);
            }
            if(attempt && !(mode==2 && attempt==1)) {
                unsigned mean=(sum+4)/9;gray[i]=(uint8_t)mean;
                if(mean<low)low=mean;
                if(mean>high)high=mean;
            } else if(sum>=5)cells|=(uint64_t)1u<<i;
        }
        if(attempt && !(mode==2 && attempt==1)) {
            if(high-low<2)return;
            for(i=0;i<36;i++) {
                uint64_t bit=(uint64_t)1u<<i;
                if(2u*gray[i]>low+high)cells|=bit;
                if((((uint64_t)0x0fe186187fULL)&bit) && gray[i]<high)edge_support|=bit;
            }
        }
        code=ua_aruco_decode_with_border(cells,0,
            (mode && attempt==1)?0u:
            (((mode || d->index>=3) && attempt)?(bottom_phase?3u:2u):0u),23u,edge_support);

    }
    if(code.valid && (mode || edge_quiet || d->index>=3 || phase_quiet)) {
        unsigned quiet_sides=0;
        /* Require the projected quiet zone inside the image, with >=7/9 light
         * samples on at least three sides. One side may be shadowed/occluded.
         * Strict payload alone can match a patch of textured clothing. */
        for(i=0;i<4;i++) {
            unsigned light=0,j;
            for(j=0;j<9;j++) {
                float along=((float)j+.5f)/9.0f;
                float u=(i==0)?along:(i==1)?(edge_quiet?1.10f:1.06f):(i==2)?along:(edge_quiet?-.10f:-.06f);
                float v0=(i==0)?(edge_quiet?-.10f:-.06f):(i==1)?along:(i==2)?(edge_quiet?1.10f:1.06f):along;
                float den=m[6]*u+m[7]*v0+1.0f;
                if(den<=.01f)return;
                int x=(int)((m[0]*u+m[1]*v0+m[2])/den+.5f);
                int y=(int)((m[3]*u+m[4]*v0+m[5])/den+.5f);
                if(x<0 || y<0 || (unsigned)x>=d->width || (unsigned)y>=d->height){light=0;break;}
                if((d->pixel(d->context,(unsigned)x,(unsigned)y)>>4)>d->threshold)light++;
            }
            if(light>=7)quiet_sides++;
        }
        if(quiet_sides<3)return;
    }
    if(code.valid && !d->found) {
        d->result.code=code;d->found=1;
        for(i=0;i<4;i++)d->result.corner[i]=q[(i+4-code.clockwise_to_canonical)%4];
        d->result.refined_valid=ua_aruco_refine(d->pixel,d->context,d->width,d->height,q);
        for(i=0;i<4;i++)d->result.refined_corner[i]=q[(i+4-code.clockwise_to_canonical)%4];
    }
}static void verify_component(ua_aruco_detector *d)
{
    ua_aruco_point p[16],hull[32],q[4],v;
    unsigned i,j,n=0,k=0,lower;
    if(d->overflow || d->area<24 || d->area>d->width*d->height/2)return;
    for(i=0;i<16;i++) {
        v=d->extreme[i];
        for(j=0;j<n && (p[j].x!=v.x || p[j].y!=v.y);j++){}
        if(j==n)p[n++]=v;
    }
    for(i=1;i<n;i++){v=p[i];j=i;while(j && (p[j-1].x>v.x || (p[j-1].x==v.x && p[j-1].y>v.y))){p[j]=p[j-1];j--;}p[j]=v;}
    for(i=0;i<n;i++){while(k>=2 && cross(hull[k-2],hull[k-1],p[i])<=0)k--;hull[k++]=p[i];}
    lower=k+1;
    for(i=n-1;i>0;i--){while(k>=lower && cross(hull[k-2],hull[k-1],p[i-1])<=0)k--;hull[k++]=p[i-1];}
    if(k<5)return;
    k--;
    /* p's sorted extrema are dead now: retain the full convex hull there.
     * Mode0 is unchanged, mode1 preserves strong turns, mode2 fits edge lines. */
    n=k;for(i=0;i<n;i++)p[i]=hull[i];
    for(unsigned mode=0;mode<3 && !d->found;mode++) {
      if(mode && d->rescues>=32)break;
      k=n;for(i=0;i<n;i++)hull[i]=p[i];
      while(k>4) {
        float best=1e30f;unsigned remove=0;
        for(i=0;i<k;i++) {
          ua_aruco_point a0=hull[(i+k-1)%k],a1=hull[i],a2=hull[(i+1)%k];
          float ax=a1.x-a0.x,ay=a1.y-a0.y,bx=a2.x-a1.x,by=a2.y-a1.y;
          float cr=ax*by-ay*bx,dot=ax*bx+ay*by,a=fabsf(cr);
          if(mode==1)a=dot>0?cr*cr/((ax*ax+ay*ay)*(bx*bx+by*by)):2.0f;
          if(a<best){best=a;remove=i;}
        }
        for(i=remove;i+1<k;i++)hull[i]=hull[i+1];
        k--;
      }
      for(i=0;i<4;i++)q[i]=hull[i];
      if(mode==2 && !fit_quad(p,n,q))continue;
      verify_quad(d,q,mode);
    }
}

int ua_aruco_step(ua_aruco_detector *d,unsigned budget)
{
    unsigned total=d->width*d->height;
    while(budget-- && d->phase<4) {
        if(d->phase==0) {
            d->scratch.hist[d->pixel(d->context,d->index%d->width,d->index/d->width)>>4]++;
            if(++d->index==total){d->threshold=otsu(d->scratch.hist,total);d->initial_threshold=d->threshold;d->index=0;d->phase=2;}
        } else if(d->phase==2) {
            if(d->scan==total || d->found || d->candidates>32){
                /* Otsu can connect a shadowed marker to dark surroundings.
                 * Darker passes separate shadows; brighter passes fill glare.
                 * phase0's index is dead here; reuse it as the retry counter.
                 * Overflow goes directly to phase4 below, never to this retry. */
                if(!d->found && d->index<UA_ARUCO_SEGMENT_PASSES-1u){
                    d->index++;
                    {int threshold=(int)d->initial_threshold+(d->index<=3?-(int)d->index:(int)d->index-3);
                     d->threshold=(unsigned)(threshold<0?0:threshold>14?14:threshold);}d->scan=0;d->candidates=0;d->rescues=0;
                    memset(d->visited,0,sizeof(d->visited));
                } else d->phase=4;
                continue;
            }
            if(!(d->visited[d->scan>>3]&(1u<<(d->scan&7))) &&
               (d->pixel(d->context,d->scan%d->width,d->scan/d->width)>>4)<=d->threshold){
                component_start(d,d->scan);d->phase=3;
            }
            d->scan++;
        } else {
            unsigned n,x,y,k;
            if(!d->queued){verify_component(d);d->phase=2;continue;}
            n=d->scratch.queue[d->head];d->head=(d->head+1u)%UA_ARUCO_QUEUE;d->queued--;d->area++;
            x=n%d->width;y=n/d->width;
            for(k=0;k<16;k++){int score=(int)x*direction[k][0]+(int)y*direction[k][1];if(score>d->score[k]){d->score[k]=score;d->extreme[k].x=(float)x;d->extreme[k].y=(float)y;}}
            if(x)(void)take(d,n-1);
            if(x+1<d->width)(void)take(d,n+1);
            if(y)(void)take(d,n-d->width);
            if(y+1<d->height)(void)take(d,n+d->width);
            // Never reinterpret fragments of an overflowing component as a
            // new marker. Reject this frame; bounded memory is deliberate.
            if(d->overflow){d->result.code.valid=0;d->result.code.id=255;d->phase=4;}
        }
    }
    return d->phase==4;
}
