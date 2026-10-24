#include "aruco_pose.h"
#include <math.h>
#include <string.h>
static const float pose_xy[4][2]={{-.5f,.5f},{.5f,.5f},{.5f,-.5f},{-.5f,-.5f}};
int ua_aruco_camera_valid(const ua_aruco_camera *c)
{
    if(!c || !c->calibrated || !c->width || !c->height || c->width>16384 || c->height>16384)return 0;
    return isfinite(c->fx)&&isfinite(c->fy)&&c->fx>1&&c->fy>1&&c->fx<1e6f&&c->fy<1e6f&&
        isfinite(c->cx)&&isfinite(c->cy)&&c->cx>=0&&c->cx<c->width&&c->cy>=0&&c->cy<c->height&&
        isfinite(c->side_m)&&c->side_m>0&&c->side_m<=10&&
        isfinite(c->max_rms_px)&&c->max_rms_px>0&&
        isfinite(c->k1)&&isfinite(c->k2)&&isfinite(c->k3)&&
        isfinite(c->p1)&&isfinite(c->p2);
}
/* Gaussian elimination with partial pivoting; caller owns fixed-size storage. */
static int pose_linear(float *a,unsigned n,unsigned stride)
{
    unsigned i,j,k,p;
    for(i=0;i<n;i++){
        float v;
        p=i;for(j=i+1;j<n;j++)if(fabsf(a[j*stride+i])>fabsf(a[p*stride+i]))p=j;
        if(!isfinite(a[p*stride+i])||fabsf(a[p*stride+i])<1e-9f)return 0;
        for(k=i;k<=n;k++){v=a[i*stride+k];a[i*stride+k]=a[p*stride+k];a[p*stride+k]=v;}
        v=a[i*stride+i];for(k=i;k<=n;k++)a[i*stride+k]/=v;
        for(j=0;j<n;j++)if(j!=i){v=a[j*stride+i];for(k=i;k<=n;k++)a[j*stride+k]-=v*a[i*stride+k];}
    }
    return 1;
}
static void pose_distort(const ua_aruco_camera *c,float x,float y,float *u,float *v)
{
    float r=x*x+y*y,rad=1+r*(c->k1+r*(c->k2+r*c->k3));
    *u=x*rad+2*c->p1*x*y+c->p2*(r+2*x*x);
    *v=y*rad+c->p1*(r+2*y*y)+2*c->p2*x*y;
}
static int pose_project(const ua_aruco_camera *c,const float *r,const float *t,float *out)
{
    unsigned i;
    for(i=0;i<4;i++){
        float x=pose_xy[i][0],y=pose_xy[i][1],z=r[6]*x+r[7]*y+t[2],u,v;
        if(!isfinite(z)||z<=1e-4f)return 0;
        pose_distort(c,(r[0]*x+r[1]*y+t[0])/z,(r[3]*x+r[4]*y+t[1])/z,&u,&v);
        out[2*i]=c->fx*u+c->cx;out[2*i+1]=c->fy*v+c->cy;
        if(!isfinite(out[2*i])||!isfinite(out[2*i+1]))return 0;
    }
    return 1;
}
static float pose_cost(const float *a,const float *b)
{unsigned i;float s=0;for(i=0;i<8;i++){float d=a[i]-b[i];s+=d*d;}return s;}
int ua_aruco_pose_axes(const ua_aruco_camera *c,const ua_aruco_pose *p,
                       float length_m,ua_aruco_point out[4])
{
    ua_aruco_point projected[4];unsigned i,j;
    if(!out)return 0;
    memset(out,0,4*sizeof(*out));
    if(!ua_aruco_camera_valid(c)||!p||!p->valid||!isfinite(length_m)||length_m<=0||length_m>c->side_m)return 0;
    for(j=0;j<9;j++)if(!isfinite(p->rotation[j]))return 0;
    for(i=0;i<4;i++){
        float v[3],u,w;
        for(j=0;j<3;j++)v[j]=p->translation[j]+(i?p->rotation[3*j+i-1]*length_m:0);
        if(!isfinite(v[0])||!isfinite(v[1])||!isfinite(v[2])||v[2]<=1e-4f)return 0;
        pose_distort(c,v[0]/v[2],v[1]/v[2],&u,&w);
        projected[i].x=c->fx*u+c->cx;projected[i].y=c->fy*w+c->cy;
        /* Suppress an out-of-frame axis bank rather than wrapping 11-bit coordinates. */
        if(!isfinite(projected[i].x)||!isfinite(projected[i].y)||
           projected[i].x<0||projected[i].y<0||projected[i].x>c->width-1||projected[i].y>c->height-1)return 0;
    }
    memcpy(out,projected,sizeof(projected));return 1;
}
static float pose_norm(float *v)
{return sqrtf(v[0]*v[0]+v[1]*v[1]+v[2]*v[2]);}
static void pose_cross(const float *a,const float *b,float *o)
{o[0]=a[1]*b[2]-a[2]*b[1];o[1]=a[2]*b[0]-a[0]*b[2];o[2]=a[0]*b[1]-a[1]*b[0];}
static int pose_solve_bounded(const ua_aruco_camera *,const ua_aruco_point [4],
                             ua_aruco_pose_workspace *,ua_aruco_pose *,unsigned);
static int axes_geometry(const ua_aruco_point p[4],unsigned width,unsigned height,
                         float focal_px,ua_aruco_point out[4],float consistency[2])
{
    ua_aruco_point q[4];
    float dx1,dx2,dx3,dy1,dy2,dy3,det,g,h,a,b,c,d,e,f;
    float cx,cy,qa[3],qb[3],normal[3],t[3],na,nb,nn,scale,z,clip=1;
    float u[3]={.5f,1,.5f},v[3]={.5f,.5f,0};
    unsigned i;
    if(!out)return 0;
    memset(out,0,4*sizeof(*out));
    if(!p||width<2||height<2||width>16384||height>16384||
       !isfinite(focal_px)||focal_px<=1||focal_px>1e6f)return 0;
    for(i=0;i<4;i++){
        unsigned j=(i+1)&3u,k=(i+2)&3u;
        float dx=p[j].x-p[i].x,dy=p[j].y-p[i].y;
        float cross=dx*(p[k].y-p[j].y)-dy*(p[k].x-p[j].x);
        if(!isfinite(p[i].x)||!isfinite(p[i].y)||p[i].x<0||p[i].y<0||
           p[i].x>width-1||p[i].y>height-1||dx*dx+dy*dy<4||
           !isfinite(cross)||cross<=.01f)return 0;
    }
    dx1=p[1].x-p[2].x;dx2=p[3].x-p[2].x;
    dx3=p[0].x-p[1].x+p[2].x-p[3].x;
    dy1=p[1].y-p[2].y;dy2=p[3].y-p[2].y;
    dy3=p[0].y-p[1].y+p[2].y-p[3].y;
    if(dx3==0 && dy3==0)g=h=0;
    else {
        det=dx1*dy2-dx2*dy1;
        if(!isfinite(det)||fabsf(det)<.25f)return 0;
        g=(dx3*dy2-dx2*dy3)/det;h=(dx1*dy3-dx3*dy1)/det;
    }
    a=p[1].x-p[0].x+g*p[1].x;b=p[3].x-p[0].x+h*p[3].x;c=p[0].x;
    d=p[1].y-p[0].y+g*p[1].y;e=p[3].y-p[0].y+h*p[3].y;f=p[0].y;
    for(i=0;i<3;i++){
        z=g*u[i]+h*v[i]+1;
        if(!isfinite(z)||z<.0001f)return 0;
        q[i].x=(a*u[i]+b*v[i]+c)/z;q[i].y=(d*u[i]+e*v[i]+f)/z;
        if(!isfinite(q[i].x)||!isfinite(q[i].y)||q[i].x<0||q[i].y<0||
           q[i].x>width-1||q[i].y>height-1)return 0;
    }
    cx=(width-1)*.5f;cy=(height-1)*.5f;
    /* H maps u=X+.5, v=.5-Y. Remove assumed K, then take r1 cross r2.
     * Translation and the normal displacement share H's scale; no iterative
     * PnP/LM or additional persistent workspace is needed for this preview. */
    qa[0]=(a-cx*g)/focal_px;qa[1]=(d-cy*g)/focal_px;qa[2]=g;
    qb[0]=(-b+cx*h)/focal_px;qb[1]=(-e+cy*h)/focal_px;qb[2]=-h;
    t[2]=1+.5f*(g+h);
    t[0]=(c+.5f*(a+b)-cx*t[2])/focal_px;
    t[1]=(f+.5f*(d+e)-cy*t[2])/focal_px;
    na=pose_norm(qa);nb=pose_norm(qb);pose_cross(qa,qb,normal);nn=pose_norm(normal);
    if(!isfinite(na)||!isfinite(nb)||!isfinite(nn)||na<1e-6f||nb<1e-6f||nn<1e-8f)return 0;
    if(consistency){
        consistency[0]=fabsf(qa[0]*qb[0]+qa[1]*qb[1]+qa[2]*qb[2])/(na*nb);
        consistency[1]=na/nb;
    }
    scale=.25f*(na+nb)/nn; /* half side * mean homography-column norm */
    for(i=0;i<3;i++)t[i]+=normal[i]*scale;
    if(!isfinite(t[2])||t[2]<=.0001f)return 0;
    q[3].x=focal_px*t[0]/t[2]+cx;q[3].y=focal_px*t[1]/t[2]+cy;
    if(!isfinite(q[3].x)||!isfinite(q[3].y))return 0;
    /* Clip along the projected segment, preserving direction at screen edges. */
    dx1=q[3].x-q[0].x;dy1=q[3].y-q[0].y;
    if(q[3].x<0)clip=fminf(clip,-q[0].x/dx1);
    if(q[3].x>width-1)clip=fminf(clip,(width-1-q[0].x)/dx1);
    if(q[3].y<0)clip=fminf(clip,-q[0].y/dy1);
    if(q[3].y>height-1)clip=fminf(clip,(height-1-q[0].y)/dy1);
    q[3].x=fminf(width-1,fmaxf(0,q[0].x+clip*dx1));
    q[3].y=fminf(height-1,fmaxf(0,q[0].y+clip*dy1));
    memcpy(out,q,sizeof(q));return 1;
}
int ua_aruco_axes_estimated(const ua_aruco_point p[4],unsigned width,unsigned height,
                            float focal_px,ua_aruco_point out[4])
{return axes_geometry(p,width,height,focal_px,out,0);}

int ua_aruco_axes_preview(const ua_aruco_point p[4],unsigned width,unsigned height,
                         float focal_px,ua_aruco_pose_workspace *ws,
                         ua_aruco_point out[4],unsigned *normal_valid)
{
    ua_aruco_camera model;
    ua_aruco_pose fit;
    float quality[2],side=0,length,step_x,step_y,clip=1;
    float x,y,z;
    unsigned i;
    if(normal_valid)*normal_valid=0;
    if(!axes_geometry(p,width,height,focal_px,out,quality))return 0;
    /* Planar axes remain useful even when 3-D is not identifiable. Zero-length
     * Z preserves the existing FPGA mailbox ABI and draws no misleading ray. */
    out[3]=out[0];
    if(!ws || !normal_valid)return 1;
    for(i=0;i<4;i++){
        unsigned j=(i+1)&3u;
        float dx=p[j].x-p[i].x,dy=p[j].y-p[i].y;
        side+=sqrtf(dx*dx+dy*dy)*.25f;
    }
    /* Exact square homography under a correct K has orthogonal equal-length
     * columns. Large inconsistencies indicate wrong K/shape or bad corners. */
    if(side<40 || quality[0]>.12f || quality[1]<.85f || quality[1]>1.18f)return 1;
    memset(&model,0,sizeof(model));
    /* Internal assumed display model ONLY. Never stored in pose_camera and
     * never publishes a calibrated flag, metric translation or pose_result. */
    model.calibrated=1;model.width=width;model.height=height;
    model.fx=model.fy=focal_px;model.cx=(width-1)*.5f;model.cy=(height-1)*.5f;
    model.side_m=1;model.max_rms_px=fmaxf(2.0f,side*.01f);
    if(pose_solve_bounded(&model,p,ws,&fit,6)!=UA_POSE_OK)return 1;
    x=fit.translation[0]+fit.rotation[2]*.5f;
    y=fit.translation[1]+fit.rotation[5]*.5f;
    z=fit.translation[2]+fit.rotation[8]*.5f;
    if(!isfinite(z)||z<=.0001f)return 1;
    step_x=focal_px*x/z+model.cx-out[0].x;
    step_y=focal_px*y/z+model.cy-out[0].y;
    length=step_x*step_x+step_y*step_y;
    if(!isfinite(length)||length<64)return 1; /* near-frontal sub-8px cue */
    if(out[0].x+step_x<0)clip=fminf(clip,-out[0].x/step_x);
    if(out[0].x+step_x>width-1)clip=fminf(clip,(width-1-out[0].x)/step_x);
    if(out[0].y+step_y<0)clip=fminf(clip,-out[0].y/step_y);
    if(out[0].y+step_y>height-1)clip=fminf(clip,(height-1-out[0].y)/step_y);
    out[3].x=fminf(width-1,fmaxf(0,out[0].x+clip*step_x));
    out[3].y=fminf(height-1,fmaxf(0,out[0].y+clip*step_y));
    *normal_valid=1;return 1;
}
/* Quaternion left increment avoids trigonometric library cost; normalized
 * (1, delta/2) is a valid rotation and agrees with the local derivative. */
static void pose_increment(const float *r,const float *d,float *o)
{
    float s=1/(1+.25f*(d[0]*d[0]+d[1]*d[1]+d[2]*d[2]));
    float w=sqrtf(s),x=d[0]*.5f*w,y=d[1]*.5f*w,z=d[2]*.5f*w;
    float m[9]={1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w),
                2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w),
                2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)};
    unsigned i,j,k;for(i=0;i<3;i++)for(j=0;j<3;j++){
        o[3*i+j]=0;for(k=0;k<3;k++)o[3*i+j]+=m[3*i+k]*r[3*k+j];
    }
}
static void pose_quaternion(const float *r,float *q)
{
    unsigned i,k=0;float s;
    if(r[0]+r[4]+r[8]>0){
        s=2*sqrtf(1+r[0]+r[4]+r[8]);q[0]=s*.25f;
        q[1]=(r[7]-r[5])/s;q[2]=(r[2]-r[6])/s;q[3]=(r[3]-r[1])/s;
    }else{
        unsigned j,l;
        for(i=1;i<3;i++)if(r[4*i]>r[4*k])k=i;
        j=(k+1)%3;l=(k+2)%3;s=2*sqrtf(fmaxf(0,1+r[4*k]-r[4*j]-r[4*l]));
        q[k+1]=s*.25f;q[0]=(r[3*l+j]-r[3*j+l])/s;
        q[j+1]=(r[3*j+k]+r[3*k+j])/s;q[l+1]=(r[3*l+k]+r[3*k+l])/s;
    }
    s=sqrtf(q[0]*q[0]+q[1]*q[1]+q[2]*q[2]+q[3]*q[3]);
    if(q[0]<0)s=-s;
    for(i=0;i<4;i++)q[i]/=s;
}
static int pose_solve_bounded(const ua_aruco_camera *c,const ua_aruco_point p[4],
                      ua_aruco_pose_workspace *ws,ua_aruco_pose *out,unsigned max_iterations)
{
    float observed[8],projected[8],trial[8],r[9],t[3],rr[9],tt[3];
    float a[3],b[3],z[3],na,nb,dot,scale,cost,lambda=.001f,area=0;
    unsigned i,j,k,it;float winding=0;
    if(!out)return UA_POSE_BAD_INPUT;
    memset(out,0,sizeof(*out));
    if(!ua_aruco_camera_valid(c))return UA_POSE_UNCALIBRATED;
    if(!p||!ws)return UA_POSE_BAD_INPUT;
    for(i=0;i<4;i++){
        unsigned n=(i+1)%4,m=(i+2)%4;float dx,dy,cross;
        if(!isfinite(p[i].x)||!isfinite(p[i].y)||p[i].x<0||p[i].y<0||
           p[i].x>=c->width||p[i].y>=c->height)return UA_POSE_BAD_INPUT;
        dx=p[n].x-p[i].x;dy=p[n].y-p[i].y;
        if(dx*dx+dy*dy<4)return UA_POSE_DEGENERATE;
        cross=dx*(p[m].y-p[n].y)-dy*(p[m].x-p[n].x);
        if(!isfinite(cross)||fabsf(cross)<.01f)return UA_POSE_DEGENERATE;
        if(i && cross*winding<=0)return UA_POSE_DEGENERATE;
        winding=cross;area+=p[i].x*p[n].y-p[n].x*p[i].y;
    }
    if(area<8)return UA_POSE_DEGENERATE; /* decoded front face is clockwise in image */
    memset(ws->phase.homography,0,sizeof(ws->phase.homography));
    for(i=0;i<4;i++){
        float u=(p[i].x-c->cx)/c->fx,v=(p[i].y-c->cy)/c->fy,x=u,y=v;
        float X=pose_xy[i][0],Y=pose_xy[i][1];
        for(j=0;j<12;j++){
            float du,dv;pose_distort(c,x,y,&du,&dv);x+=u-du;y+=v-dv;
            if(!isfinite(x)||!isfinite(y)||fabsf(x)>4||fabsf(y)>4)return UA_POSE_BAD_INPUT;
        }
        observed[2*i]=p[i].x;observed[2*i+1]=p[i].y;
        ws->phase.homography[2*i][0]=X;ws->phase.homography[2*i][1]=Y;ws->phase.homography[2*i][2]=1;
        ws->phase.homography[2*i][6]=-x*X;ws->phase.homography[2*i][7]=-x*Y;ws->phase.homography[2*i][8]=x;
        ws->phase.homography[2*i+1][3]=X;ws->phase.homography[2*i+1][4]=Y;ws->phase.homography[2*i+1][5]=1;
        ws->phase.homography[2*i+1][6]=-y*X;ws->phase.homography[2*i+1][7]=-y*Y;ws->phase.homography[2*i+1][8]=y;
    }
    if(!pose_linear(&ws->phase.homography[0][0],8,9))return UA_POSE_DEGENERATE;
    for(i=0;i<3;i++){a[i]=ws->phase.homography[3*i][8];b[i]=ws->phase.homography[3*i+1][8];}
    /* h33 is fixed to one, not stored as a ninth unknown. */
    a[2]=ws->phase.homography[6][8];b[2]=ws->phase.homography[7][8];
    na=pose_norm(a);nb=pose_norm(b);
    if(na<1e-6f||nb<1e-6f)return UA_POSE_DEGENERATE;
    scale=2/(na+nb);for(i=0;i<3;i++)a[i]/=na;
    dot=a[0]*b[0]+a[1]*b[1]+a[2]*b[2];for(i=0;i<3;i++)b[i]-=a[i]*dot;
    nb=pose_norm(b);if(nb<1e-6f)return UA_POSE_DEGENERATE;
    for(i=0;i<3;i++)b[i]/=nb;
    pose_cross(a,b,z);for(i=0;i<3;i++){r[3*i]=a[i];r[3*i+1]=b[i];r[3*i+2]=z[i];}
    t[0]=ws->phase.homography[2][8]*scale;t[1]=ws->phase.homography[5][8]*scale;t[2]=scale;
    if(!pose_project(c,r,t,projected))return UA_POSE_DEGENERATE;
    cost=pose_cost(projected,observed);
    for(it=0;it<max_iterations && cost>1e-7f;it++){
        for(j=0;j<6;j++){
            float d[3]={0,0,0};memcpy(tt,t,sizeof(t));
            if(j<3){d[j]=.0001f;pose_increment(r,d,rr);}else{memcpy(rr,r,sizeof(r));tt[j-3]+=.0001f;}
            if(!pose_project(c,rr,tt,trial))return UA_POSE_DEGENERATE;
            for(i=0;i<8;i++)ws->phase.lm.jacobian[i][j]=(trial[i]-projected[i])*10000;
        }
        for(j=0;j<6;j++){
            for(k=0;k<6;k++){
                float v=0;for(i=0;i<8;i++)v+=ws->phase.lm.jacobian[i][j]*ws->phase.lm.jacobian[i][k];
                ws->phase.lm.normal[j][k]=v;
            }
            ws->phase.lm.normal[j][j]+=lambda*(ws->phase.lm.normal[j][j]+1);
            ws->phase.lm.normal[j][6]=0;for(i=0;i<8;i++)ws->phase.lm.normal[j][6]+=ws->phase.lm.jacobian[i][j]*(observed[i]-projected[i]);
        }
        if(!pose_linear(&ws->phase.lm.normal[0][0],6,7))break;
        for(j=0;j<3;j++){a[j]=ws->phase.lm.normal[j][6];tt[j]=t[j]+ws->phase.lm.normal[j+3][6];}
        pose_increment(r,a,rr);
        if(pose_project(c,rr,tt,trial)&&pose_cost(trial,observed)<cost){
            cost=pose_cost(trial,observed);memcpy(r,rr,sizeof(r));memcpy(t,tt,sizeof(t));
            memcpy(projected,trial,sizeof(trial));lambda=fmaxf(1e-7f,lambda*.25f);
        }else lambda=fminf(1e6f,lambda*10);
    }
    out->rms_px=sqrtf(cost*.25f);out->iterations=it;
    if(!isfinite(out->rms_px)||out->rms_px>c->max_rms_px)return UA_POSE_REPROJECTION;
    memcpy(out->rotation,r,sizeof(r));for(i=0;i<3;i++){
        out->translation[i]=t[i]*c->side_m;
        if(!isfinite(out->translation[i])||fabsf(out->translation[i])>1000)return UA_POSE_BAD_INPUT;
    }
    pose_quaternion(r,out->quaternion);out->valid=1;return UA_POSE_OK;
}
int ua_aruco_pose_solve(const ua_aruco_camera *c,const ua_aruco_point p[4],
                      ua_aruco_pose_workspace *ws,ua_aruco_pose *out)
{return pose_solve_bounded(c,p,ws,out,16);}
int ua_aruco_pose_detection(const ua_aruco_camera *c,const ua_aruco_detection *d,
                          ua_aruco_pose_workspace *ws,ua_aruco_pose *out)
{
    ua_aruco_point p[4];ua_aruco_pose candidate;unsigned i;int code,alternate;
    if(!out)return UA_POSE_BAD_INPUT;
    if(!d||!d->code.valid){memset(out,0,sizeof(*out));return UA_POSE_BAD_INPUT;}
    if(!c||c->width!=1280||c->height!=720){memset(out,0,sizeof(*out));return UA_POSE_UNCALIBRATED;}
    for(i=0;i<4;i++){p[i].x=d->corner[i].x*8;p[i].y=d->corner[i].y*8;}
    code=ua_aruco_pose_solve(c,p,ws,out);
    if(ua_aruco_camera_valid(c)&&d->refined_valid){
        for(i=0;i<4;i++){p[i].x=d->refined_corner[i].x*8;p[i].y=d->refined_corner[i].y*8;}
        alternate=ua_aruco_pose_solve(c,p,ws,&candidate);
        /* Extrema are centers of dark raster pixels, not the optical boundary.
         * A uniformly shrunken square can have exactly zero reprojection error
         * but a biased depth. Below 0.25 full-resolution pixels both residuals
         * are indistinguishable for this 8-pixel sampling grid: prefer the
         * measured black/white boundary, not the quantized interior centers.
         * Larger residuals still require strict improvement. No scale fudge. */
        if(alternate==UA_POSE_OK&&(!out->valid||candidate.rms_px<fmaxf(out->rms_px,.25f))){
            *out=candidate;code=alternate;
        }
    }
    return code;
}
