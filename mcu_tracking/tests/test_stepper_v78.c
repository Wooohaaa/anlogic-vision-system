/* Reuse the previous controller model and regression, then test isolated axes.
 * Modelled positions are not encoder feedback or a physical motor simulation. */
#define main legacy_main
#include "test_stepper_v69.c"
#undef main

static void reset_model(StepperControl *s)
{
    memset(regs,0,sizeof(regs));memset(p,0,sizeof(p));
    memset(fraction,0,sizeof(fraction));time_ms=0;trace=NULL;
    regs[0]=0x53545032;st_init(s,rd,wr,0);
}
int main(int argc,char **argv)
{
    StepperControl s;unsigned axis,n,seen_pos,seen_neg;
    (void)argc;assert(legacy_main(1,argv)==0);
    for(axis=0;axis<2;axis++){
        unsigned mode=axis?ST_AXIS1:ST_AXIS0;
        reset_model(&s);assert(!st_start(&s,mode,time_ms));
        assert(st_zero(&s));assert(!st_start(&s,99,time_ms));
        assert(st_start(&s,mode,time_ms));
        assert(!st_start(&s,axis?ST_AXIS0:ST_AXIS1,time_ms));
        seen_pos=seen_neg=0;
        for(n=0;n<1600 && s.mode;n++){
            clock10(&s);
            assert(p[1-axis]==0 && s.velocity[1-axis]==0);
            assert(p[axis]>=-80 && p[axis]<=80);
            assert(s.velocity[axis]>=-80 && s.velocity[axis]<=80);
            if(p[axis]==80)seen_pos=1;
            if(p[axis]==-80)seen_neg=1;
            if(s.mode){
                assert((int16_t)(regs[6]>>(16*(1-axis)))==0);
                assert((int16_t)(regs[7]>>(16*(1-axis)))==0);
            }
        }
        assert(seen_pos && seen_neg && s.scan_phase==3);
        assert(s.mode==ST_OFF && regs[1]==0 && p[0]==0 && p[1]==0);
        assert(st_zero(&s));assert(st_start(&s,mode,time_ms));
        for(n=0;n<20;n++)clock10(&s);
        time_ms+=101;st_service(&s,time_ms);
        assert(s.mode==ST_OFF && regs[1]==0); // foreground stall
        assert(st_zero(&s));assert(st_start(&s,mode,time_ms));
        s.scan_deadline_ms=time_ms;st_service(&s,time_ms);
        assert(s.mode==ST_OFF && regs[1]==0); // finite deadline
        assert(st_zero(&s));assert(st_start(&s,mode,time_ms));
        st_stop(&s);assert(s.mode==ST_OFF && regs[1]==0);
        assert(!st_start(&s,mode,time_ms)); // stop revokes origin
    }
    puts("STEPPER_V78_AXIS_ISOLATION_PASS bounded80 speed80 return0 off stall deadline");
    return 0;
}
