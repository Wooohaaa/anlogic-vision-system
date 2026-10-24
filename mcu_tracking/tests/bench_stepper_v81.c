#define main full_controller_suite
#include "test_stepper_v81.c"
#undef main

int main(void)
{
    static const double gains[]={0.5,1,2};
    StepperControl s;int history[64][2];unsigned k,delay,n,index,consecutive,settled,total=0;
    for(k=0;k<3;k++)for(delay=0;delay<=15;delay+=5){
        init(&s);memset(history,0,sizeof(history));assert(st_zero(&s));
        target3(&s,232,42);assert(st_start(&s,ST_TRACK,ms));
        consecutive=settled=0;
        for(n=0;n<1500;n++){
            int x,y;history[n%64][0]=p[0];history[n%64][1]=p[1];
            index=(n+64-delay)%64;
            x=(int)(232+gains[k]*history[index][1]);
            y=(int)(42+gains[k]*history[index][0]);
            assert(x>=0 && x<320 && y>=0 && y<180); // no model loss from overshoot
            if(n%2==0)st_target(&s,(unsigned)x,(unsigned)y,1,ms);
            clock10(&s);assert(s.mode==ST_TRACK);
            if(x>=150 && x<=170 && y>=80 && y<=100)consecutive++;
            else consecutive=0;
            if(consecutive>=30 && !settled)settled=(n+1)*10;
        }
        assert(settled>0);total+=settled;
        printf("SETTLE gain=%.1f delay_ms=%u settle_ms=%u final_steps=(%d,%d)\n",
            gains[k],delay*10,settled,p[0],p[1]);fflush(stdout);st_stop(&s);
    }
    printf("STEP_RESPONSE_SUM_MS=%u\n",total);
    puts("STEP_RESPONSE_LARGE_ERROR_12_PASS_NOT_BOARD");return 0;
}
