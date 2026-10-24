#include <assert.h>
#include <stdio.h>
#define TRACKING_HOST_TEST
#define main firmware_main
#include "../camera_app/main.c"
#undef main
static void feed(unsigned px,unsigned py,unsigned ok,unsigned seq) {
 unsigned char p[]={0x2c,9,px&255,px>>8,py&255,py>>8,ok,seq,0x5b};
 for(unsigned i=0;i<9;i++){mock_now++;receive(p[i],0);}
}
int main(void) {
 gpio=&mock_gpio;ticks=1;command('d');
 feed(160,90,1,0);control();assert(valid&&pulse_a==1500&&pulse_b==1500&&remaining==0);
 feed(319,0,1,1);control();assert(pulse_a==1464&&pulse_b==1536);
 unsigned bad=rejected;feed(10,10,1,1);assert(rejected==bad+1&&x==319);
 bad=rejected;feed(320,180,1,2);assert(rejected==bad+1&&x==319);
 feed(0,0,1,3);control();assert(valid); // (0,0) is a legal new-protocol target.
 feed(0,0,0,4);assert(!valid&&!remaining&&!controller.ready);
 command('t');feed(319,0,1,5);control();assert(remaining==7);
 deadline=mock_now;timer_irq(NULL);assert(phase==1&&(mock_output&6)==6);
 mock_now=deadline;timer_irq(NULL);
 while(phase){mock_now=deadline;timer_irq(NULL);}
 assert((mock_output&6)==0&&faults==0);
 command('s');assert(!armed&&!tracking&&!valid&&!remaining&&(mock_output&6)==0);
 command('d');feed(200,90,1,6);control();assert(pulse_a==1500&&pulse_b==1536);
 command('d');feed(160,50,1,7);control();assert(pulse_a==1464&&pulse_b==1500);
 // Reject malformed footer without publishing a target.
 command('d');receive(0x2c,0);receive(9,0);
 for(unsigned i=0;i<7;i++)receive(0,0);
 assert(!valid);
 puts("CAMERA_FIRMWARE_PASS parser duplicate bounds loss absolute_position dual_PWM stop");
 return 0;
}
