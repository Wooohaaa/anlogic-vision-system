#ifndef __CALCULATION_PI_H_
#define __CALCULATION_PI_H_

#include <stdio.h>
#include "al_type.h"


#if (defined __riscv || defined __riscv__)


AL_VOID calculate_PI_f0_f4(AL_VOID);
AL_VOID calculate_PI_f5_f9(AL_VOID);
AL_VOID calculate_PI_f10_f14(AL_VOID);
AL_VOID calculate_PI_f15_f19(AL_VOID);
AL_FLOAT calculate_PI_f20_f24(AL_VOID);

AL_FLOAT calculate_PI(AL_VOID);

AL_VOID calculate_PI_f0_f4(AL_VOID) {
/*
 * f0: the result (pi) 
 * f1: the current term
 * f2: the denominator
 * f3: the sign (-1 or 1)
 * f4: the constant 2.0
 * 
*/
    const AL_CHAR *str_startasm = "Test f0 - f4 start !!!";
    // printf("%s\r\n",str_startasm);
    AL_FLOAT read_date = 256.46;
    
    // f0 = 0.0

    asm volatile ("li t0, 0x00000000");
    asm volatile ("fmv.w.x f0, t0");
    // asm volatile ("fmv.s %0, f0" : "=f"(read_date));
    // printf("f0 = %f\r\n", read_date);

    // f1 = 1.0
    asm volatile ("li t0, 0x3F800000");
    asm volatile ("fmv.w.x f1, t0");  
    // asm volatile ("fmv.s %0, f1" : "=f"(read_date));
    // printf("f1 = %f\r\n", read_date);  

    // f2 = 1.0
    asm volatile ("li t0, 0x3F800000");
    asm volatile ("fmv.w.x f2, t0");   
    // asm volatile ("fmv.s %0, f2" : "=f"(read_date));
    // printf("f2 = %f\r\n", read_date);

    // f3 = 1.0
    asm volatile ("li t0, 0x3F800000");
    asm volatile ("fmv.w.x f3, t0");  
    // asm volatile ("fmv.s %0, f3" : "=f"(read_date));
    // printf("f3 = %f\r\n", read_date);

    // f4 = 2.0
    asm volatile ("li t0, 0x40000000");
    asm volatile ("fmv.w.x f4, t0");  
    // asm volatile ("fmv.s %0, f4" : "=f"(read_date));
    // printf("f4 = %f\r\n", read_date);

    //counter

    AL_U32 count = 10000000;
    while(count > 0){
    asm volatile ("fadd.s f0, f0, f1");

    asm volatile ("fneg.s f3, f3");
    asm volatile ("fadd.s f2, f2, f4");
    asm volatile ("fdiv.s f1, f3, f2");
    count--;
    }

    AL_FLOAT res;
    asm volatile ("fmv.s %0, f0" : "=f"(res));
    // printf("f0_f4_PI = %f\r\n", res*4.0);
}

AL_VOID calculate_PI_f5_f9(AL_VOID) {
/*
 * f5: the result (pi) 
 * f6: the current term
 * f7: the denominator
 * f8: the sign (-1 or 1)
 * f9: the constant 2.0
 * 
*/
    const AL_CHAR *str_startasm = "Test f5 - f9 start !!!";
    // printf("%s\r\n",str_startasm);

    // f5 = 0.0
    // AL_FLOAT read_date = 256.46;

    asm volatile ("li t0, 0x00000000");
    asm volatile ("fmv.w.x f5, t0");
    // asm volatile ("fmv.s %0, f5" : "=f"(read_date));
    // printf("f0 = %f\r\n", read_date);

    // f6 = 1.0
    asm volatile ("li t0, 0x3F800000");
    asm volatile ("fmv.w.x f6, t0");  
    // asm volatile ("fmv.s %0, f6" : "=f"(read_date));
    // printf("f6 = %f\r\n", read_date);  

    // f7 = 1.0
    asm volatile ("li t0, 0x3F800000");
    asm volatile ("fmv.w.x f7, t0");   
    // asm volatile ("fmv.s %0, f7" : "=f"(read_date));
    // printf("f7 = %f\r\n", read_date);

    // f8 = 1.0
    asm volatile ("li t0, 0x3F800000");
    asm volatile ("fmv.w.x f8, t0");  
    // asm volatile ("fmv.s %0, f8" : "=f"(read_date));
    // printf("f8 = %f\r\n", read_date);

    // f9 = 2.0
    asm volatile ("li t0, 0x40000000");
    asm volatile ("fmv.w.x f9, t0");  
    // asm volatile ("fmv.s %0, f9" : "=f"(read_date));
    // printf("f9 = %f\r\n", read_date);

    //counter

    AL_U32 count = 10000000;
    while(count > 0){
    asm volatile ("fadd.s f5, f5, f6");

    asm volatile ("fneg.s f8, f8");
    asm volatile ("fadd.s f7, f7, f9");
    asm volatile ("fdiv.s f6, f8, f7");
    count--;
    }

    AL_FLOAT res;
    asm volatile ("fmv.s %0, f5" : "=f"(res));
    // printf("f5_f9_PI = %f\r\n", res*4.0);
}

AL_VOID calculate_PI_f10_f14(AL_VOID) {
/*
 * f10: the result (pi) 
 * f11: the current term
 * f12: the denominator
 * f13: the sign (-1 or 1)
 * f14: the constant 2.0
 * 
*/
    const AL_CHAR *str_startasm = "Test f10 - f14 start !!!";
    // printf("%s\r\n",str_startasm);
    AL_FLOAT read_date = 256.46;
    
    // f10 = 0.0

    asm volatile ("li t0, 0x00000000");
    asm volatile ("fmv.w.x f10, t0");
    // asm volatile ("fmv.s %0, f10" : "=f"(read_date));
    // printf("f10 = %f\r\n", read_date);

    // f11 = 1.0
    asm volatile ("li t0, 0x3F800000");
    asm volatile ("fmv.w.x f11, t0");  
    // asm volatile ("fmv.s %0, f11" : "=f"(read_date));
    // printf("f11 = %f\r\n", read_date);  

    // f12 = 1.0
    asm volatile ("li t0, 0x3F800000");
    asm volatile ("fmv.w.x f12, t0");   
    // asm volatile ("fmv.s %0, f12" : "=f"(read_date));
    // printf("f12 = %f\r\n", read_date);

    // f13 = 1.0
    asm volatile ("li t0, 0x3F800000");
    asm volatile ("fmv.w.x f13, t0");  
    // asm volatile ("fmv.s %0, f13" : "=f"(read_date));
    // printf("f13 = %f\r\n", read_date);

    // f14 = 2.0
    asm volatile ("li t0, 0x40000000");
    asm volatile ("fmv.w.x f14, t0");  
    // asm volatile ("fmv.s %0, f14" : "=f"(read_date));
    // printf("f14 = %f\r\n", read_date);

    //counter

    AL_U32 count = 10000000;
    while(count > 0){
    asm volatile ("fadd.s f10, f10, f11");

    asm volatile ("fneg.s f13, f13");
    asm volatile ("fadd.s f12, f12, f14");
    asm volatile ("fdiv.s f11, f13, f12");
    count--;
    }

    AL_FLOAT res;
    asm volatile ("fmv.s %0, f10" : "=f"(res));
    // printf("f10_f14_PI = %f\r\n", res*4.0);
}

AL_VOID calculate_PI_f15_f19(AL_VOID) {
/*
 * f15: the result (pi) 
 * f16: the current term
 * f17: the denominator
 * f18: the sign (-1 or 1)
 * f19: the constant 2.0
 * 
*/
    const AL_CHAR *str_startasm = "Test f15 - f19 start !!!";
    // printf("%s\r\n",str_startasm);
    AL_FLOAT read_date = 256.46;
    
    // f15 = 0.0

    asm volatile ("li t0, 0x00000000");
    asm volatile ("fmv.w.x f15, t0");
    // asm volatile ("fmv.s %0, f15" : "=f"(read_date));
    // printf("f15 = %f\r\n", read_date);

    // f16 = 1.0
    asm volatile ("li t0, 0x3F800000");
    asm volatile ("fmv.w.x f16, t0");  
    // asm volatile ("fmv.s %0, f16" : "=f"(read_date));
    // printf("f16 = %f\r\n", read_date);  

    // f17 = 1.0
    asm volatile ("li t0, 0x3F800000");
    asm volatile ("fmv.w.x f17, t0");   
    // asm volatile ("fmv.s %0, f17" : "=f"(read_date));
    // printf("f17 = %f\r\n", read_date);

    // f18 = 1.0
    asm volatile ("li t0, 0x3F800000");
    asm volatile ("fmv.w.x f18, t0");  
    // asm volatile ("fmv.s %0, f18" : "=f"(read_date));
    // printf("f18 = %f\r\n", read_date);

    // f19 = 2.0
    asm volatile ("li t0, 0x40000000");
    asm volatile ("fmv.w.x f19, t0");  
    // asm volatile ("fmv.s %0, f19" : "=f"(read_date));
    // printf("f19 = %f\r\n", read_date);

    //counter

    AL_U32 count = 10000000;
    while(count > 0){
    asm volatile ("fadd.s f15, f15, f16");

    asm volatile ("fneg.s f18, f18");
    asm volatile ("fadd.s f17, f17, f19");
    asm volatile ("fdiv.s f16, f18, f17");
    count--;
    }

    AL_FLOAT res;
    asm volatile ("fmv.s %0, f15" : "=f"(res));
    // printf("f15_f19_PI = %f\r\n", res*4.0);
}

AL_FLOAT calculate_PI_f20_f24(AL_VOID) {
/*
 * f20: the result (pi) 
 * f21: the current term
 * f22: the denominator
 * f23: the sign (-1 or 1)
 * f24: the constant 2.0
 * 
*/
    const AL_CHAR *str_startasm = "Test f20 - f24 start !!!";
    // printf("%s\r\n",str_startasm);
    AL_FLOAT read_date = 256.46;
    
    // f20 = 0.0

    asm volatile ("li t0, 0x00000000":::"t0");
    asm volatile ("fmv.w.x f20, t0":::"f20", "t0");
    // asm volatile ("fmv.s %0, f20" : "=f"(read_date));
    // printf("f20 = %f\r\n", read_date);

    // f21 = 1.0
    asm volatile ("li t0, 0x3F800000":::"t0");
    asm volatile ("fmv.w.x f21, t0":::"t0", "f21");  
    // asm volatile ("fmv.s %0, f21" : "=f"(read_date));
    // printf("f21 = %f\r\n", read_date);  

    // f22 = 1.0
    asm volatile ("li t0, 0x3F800000":::"t0");
    asm volatile ("fmv.w.x f22, t0":::"f22", "t0");   
    // asm volatile ("fmv.s %0, f22" : "=f"(read_date));
    // printf("f22 = %f\r\n", read_date);

    // f23 = 1.0
    asm volatile ("li t0, 0x3F800000":::"t0");
    asm volatile ("fmv.w.x f23, t0":::"f23", "t0");  
    // asm volatile ("fmv.s %0, f23" : "=f"(read_date));
    // printf("f23 = %f\r\n", read_date);

    // f24 = 2.0
    asm volatile ("li t0, 0x40000000":::"t0");
    asm volatile ("fmv.w.x f24, t0":::"f24", "t0");  
    // asm volatile ("fmv.s %0, f24" : "=f"(read_date));
    // printf("f24 = %f\r\n", read_date);

    //counter

    AL_U32 count = 100000;
    while(count > 0){
    asm volatile ("fadd.s f20, f20, f21":::"f20", "f21");

    asm volatile ("fneg.s f23, f23":::"f23");
    asm volatile ("fadd.s f22, f22, f24":::"f22", "f24");
    asm volatile ("fdiv.s f21, f23, f22":::"f21", "f23", "f22");
    count--;
    }

    AL_FLOAT res;
    asm volatile ("fmv.s %0, f20" : "=f"(res));
    // printf("f20_f24_PI = %f\r\n", res*4.0);

    return res*4.0;
}

AL_FLOAT calculate_PI(AL_VOID){
    calculate_PI_f0_f4();
    calculate_PI_f5_f9();
    calculate_PI_f10_f14();
    calculate_PI_f15_f19();
    return calculate_PI_f20_f24();
}

#endif


#if defined __aarch64__ || defined __arm__


AL_FLOAT calculate_PI(void) {  
    float pi = 0.0f;
    float sign = 1.0f;
    float denominator = 1.0f;
    int iterations = 10000000;  // 迭代次数

    for (int i = 0; i < iterations; i++) {
        pi += sign / denominator;
        sign = -sign;  // 切换符号
        denominator += 2.0f;  // 分母递增
    }

    pi *= 4.0f;  // 乘以 4
    return pi;

}  

#endif
#endif
