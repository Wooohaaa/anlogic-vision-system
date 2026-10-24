#include <assert.h>
#include "tracking_control.h"
int main(void) {
 TrackingControl s={1500,1500,0,0,0};
 for(int i=0;i<100;i++)track_update(&s,162,89);
 assert(s.pan==1500&&s.tilt==1500);
 track_update(&s,319,0);
 assert(s.pan==1536&&s.tilt==1464);
 for(int i=0;i<1000;i++)track_update(&s,319,0);
 assert(s.pan>=1697&&s.pan<=1700&&s.tilt>=1300&&s.tilt<=1303);
 float fixed_pan=s.pan,fixed_tilt=s.tilt;
 for(int i=0;i<1000;i++)track_update(&s,240,60);
 assert(s.pan>=1697&&s.pan<=1700&&s.tilt>=1364&&s.tilt<=1370);
 fixed_pan=s.pan;fixed_tilt=s.tilt;
 for(int i=0;i<1000;i++)track_update(&s,240,60);
 assert(s.pan==fixed_pan&&s.tilt==fixed_tilt); // stationary target cannot drift.
 track_reset(&s);
 track_update(&s,0,179);
 assert(s.pan>=fixed_pan-36&&s.pan<fixed_pan&&s.tilt<=fixed_tilt+36&&s.tilt>fixed_tilt);
 s=(TrackingControl){1500,1500,0,0,0};
 track_update(&s,200,90);assert(s.pan==1536&&s.tilt==1500);
 s=(TrackingControl){1500,1500,0,0,0};
 track_update(&s,160,50);assert(s.pan==1500&&s.tilt==1464);
 return 0;
}
