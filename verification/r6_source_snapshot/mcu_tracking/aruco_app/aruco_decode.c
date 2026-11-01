#if defined(__GNUC__) && !defined(__clang__)
#pragma GCC optimize ("Os")
#endif
#include "aruco_decode.h"
#include "aruco_dictionary.h"
uint16_t ua_aruco_rotate_clockwise(uint16_t bits)
{
    uint16_t result=0;unsigned x,y;
    for(y=0;y<4;y++)for(x=0;x<4;x++)
        result|=(uint16_t)(((bits>>(y*4+x))&1u)<<(x*4+(3-y)));
    return result;
}
static unsigned bit_count(uint16_t bits)
{
    unsigned n=0;
    while(bits){bits=(uint16_t)(bits&(uint16_t)(bits-1u));n++;}
    return n;
}
ua_aruco_id ua_aruco_decode_with_border(uint64_t cells, unsigned max_errors, unsigned max_border_errors, uint8_t border_tolerant_id, uint64_t edge_support)
{
    ua_aruco_id out={0,255,0,255};uint16_t bits=0;
    unsigned x,y,rotation,id,best=17,ties=0,border_errors=0,unsupported_border=0;
    if(max_errors>1 || (cells>>36)!=0)return out;
    for(y=0;y<6;y++)for(x=0;x<6;x++) {
        unsigned bit=(unsigned)((cells>>(y*6+x))&1u);
        if(x==0 || x==5 || y==0 || y==5) {
            if(bit) {
                if(++border_errors>max_border_errors)return out;
                if(!((edge_support>>(y*6+x))&1u))unsupported_border=1;
            }
        } else bits|=(uint16_t)(bit<<((y-1)*4+x-1));
    }
    for(rotation=0;rotation<4;rotation++) {
        for(id=0;id<50;id++) {
            unsigned distance=bit_count((uint16_t)(bits^ua_aruco_codes[id]));
            if(distance<best) {
                best=distance;ties=1;out.id=(uint8_t)id;
                out.clockwise_to_canonical=(uint8_t)rotation;
            } else if(distance==best)ties++;
        }
        bits=ua_aruco_rotate_clockwise(bits);
    }
    if(best<=max_errors && ties==1 && (!border_errors || (out.id==border_tolerant_id && !unsupported_border))) {out.valid=1;out.hamming=(uint8_t)best;}
    else {out.id=255;out.clockwise_to_canonical=0;}
    return out;
}

ua_aruco_id ua_aruco_decode(uint64_t cells, unsigned max_errors)
{
    return ua_aruco_decode_with_border(cells,max_errors,0,255u,~(uint64_t)0);
}
