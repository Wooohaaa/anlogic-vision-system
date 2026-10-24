#include <assert.h>
#include <stdio.h>
#include "aruco_decode.h"
#include "aruco_dictionary.h"
static uint64_t marker(uint16_t bits)
{
    uint64_t out=0;unsigned x,y;
    for(y=0;y<4;y++)for(x=0;x<4;x++)
        out|=(uint64_t)((bits>>(y*4+x))&1u)<<((y+1)*6+x+1);
    return out;
}
int main(void)
{
    unsigned id,r,k,count=0;
    for(id=0;id<50;id++) {
        uint16_t bits=ua_aruco_codes[id];
        for(r=0;r<4;r++) {
            ua_aruco_id result=ua_aruco_decode(marker(bits),0);
            assert(result.valid && result.id==id && result.hamming==0);
            assert(result.clockwise_to_canonical==((4-r)%4));
            for(k=0;k<16;k++) {
                result=ua_aruco_decode(marker((uint16_t)(bits^(1u<<k))),1);
                assert(result.valid && result.id==id && result.hamming==1);
                result=ua_aruco_decode(marker((uint16_t)(bits^(1u<<k))),0);
                assert(!result.valid);count++;
            }
            for(k=0;k<36;k++)if(k<6 || k>=30 || k%6==0 || k%6==5)
                assert(!ua_aruco_decode(marker(bits)|((uint64_t)1u<<k),1).valid);
            bits=ua_aruco_rotate_clockwise(bits);
        }
    }
    assert(!ua_aruco_decode(0,1).valid);
    assert(!ua_aruco_decode(UINT64_MAX,1).valid);
    assert(!ua_aruco_decode(marker(ua_aruco_codes[0]),2).valid);
    printf("ARUCO_DECODE_PASS ids=50 rotations=4 one_bit_errors=%u border_rejection\n",count);
    return 0;
}
