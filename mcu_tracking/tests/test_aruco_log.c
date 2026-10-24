#include "aruco_log.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
static char output[2048];static unsigned used;
static void sink(void *ctx,char byte)
{(void)ctx;assert(used<sizeof(output)-1);output[used++]=byte;output[used]=0;}
#ifdef ARUCO_LOG_WRAPPER_TEST
void AlLog_WriteByte(unsigned char byte){sink(0,(char)byte);}
extern int __wrap_al_simp_printf(const char *,...);
extern int __wrap_printf(const char *,...);
extern int __wrap_puts(const char *);
#endif
static int format(const char *fmt,...)
{
    va_list args;int count;used=0;output[0]=0;va_start(args,fmt);
    count=ua_log_vformat(sink,0,fmt,args);va_end(args);return count;
}
int main(void)
{
    char expected[256];int count;
    count=format("%d %u %lld %llu",INT32_MIN,UINT32_MAX,(-9223372036854775807LL-1),18446744073709551615ULL);
    assert(!strcmp(output,"-2147483648 4294967295 -9223372036854775808 18446744073709551615"));
    assert(count==(int)strlen(output));
    format("%08x %016lx %X",0x1234u,(unsigned long)0x80000000u,0xabcdU);
    assert(!strcmp(output,"00001234 0000000080000000 ABCD"));
    format("[%8s][%-8s][%.3s][%03d][%c]%%","ok","yes","abcdef",-1,'a');
    assert(!strcmp(output,"[      ok][yes     ][abc][-01][a]%"));
    format("%ld %zu %zd %p",(long)-123,(size_t)123,(ptrdiff_t)-123,(void *)(uintptr_t)0x80000000u);
    assert(!strcmp(output,"-123 123 -123 0x80000000"));
    format("%s",(const char *)0);assert(!strcmp(output,"(null)"));
    assert(format("%f then %u",1.0,5u)==-1);assert(!strcmp(output,"<unsupported-format>"));
    assert(format("%9999999u",0u)==-1);
    assert(format("dangling %")==-1);
    for(unsigned i=0;i<1000;i++){
        int value=(int)(i*2654435761u);
        snprintf(expected,sizeof(expected),"%d %u %08x",value,(unsigned)value,(unsigned)value);
        format("%d %u %08x",value,(unsigned)value,(unsigned)value);assert(!strcmp(output,expected));
    }
#ifdef ARUCO_LOG_WRAPPER_TEST
    used=0;output[0]=0;
    __wrap_al_simp_printf("TRACK armed=%u faults=%u\r\n",0u,0u);
    __wrap_printf("mcause=0x%08lx pc=0x%016lx\r\n",(unsigned long)0x38000005,(unsigned long)0x0800047a);
    __wrap_puts("Call Frame:");
    assert(!strcmp(output,"TRACK armed=0 faults=0\r\nmcause=0x38000005 pc=0x000000000800047a\r\nCall Frame:\n"));
#endif
    puts("ARUCO_INTEGER_LOG_PASS integer_limits SDK_fault_widths no_double no_heap");
    return 0;
}
