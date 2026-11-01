#include "aruco_log.h"
#include <stdint.h>
#include <stddef.h>
#include <limits.h>
static void log_repeat(ua_log_sink sink,void *context,char byte,unsigned count)
{while(count--)sink(context,byte);}
int ua_log_vformat(ua_log_sink sink,void *context,const char *format,va_list args)
{
    int count=0;
    if(!sink||!format)return -1;
    while(*format){
        unsigned width=0,left=0,zero=0,length=0,precision=UINT_MAX;
        char spec,buffer[24],sign=0;unsigned n=0,pad=0,base=10,i;uint64_t number;
        if(*format!='%'){sink(context,*format++);count++;continue;}
        format++;
        if(*format=='%'){sink(context,*format++);count++;continue;}
        if(*format=='-'){left=1;format++;}
        if(*format=='0'){zero=1;format++;}
        while(*format>='0'&&*format<='9'){
            width=width*10+(unsigned)(*format++-'0');if(width>64)return -1;
        }
        if(*format=='.'){
            precision=0;format++;
            while(*format>='0'&&*format<='9'){
                precision=precision*10+(unsigned)(*format++-'0');if(precision>1024)return -1;
            }
        }
        if(*format=='l'){length=1;format++;if(*format=='l'){length=2;format++;}}
        else if(*format=='z'){length=3;format++;}
        spec=*format;if(!spec)return -1;format++;
        if(spec=='s'){
            const char *s=va_arg(args,const char *);if(!s)s="(null)";
            while(s[n]&&n<precision)n++;
            pad=width>n?width-n:0;
            if(!left)log_repeat(sink,context,' ',pad);
            for(i=0;i<n;i++)sink(context,s[i]);
            if(left)log_repeat(sink,context,' ',pad);
            count+=(int)(n+pad);continue;
        }
        if(spec=='c'){
            char byte=(char)va_arg(args,int);pad=width>1?width-1:0;
            if(!left)log_repeat(sink,context,' ',pad);
            sink(context,byte);if(left)log_repeat(sink,context,' ',pad);
            count+=(int)(1+pad);continue;
        }
        if(spec=='d'||spec=='i'){
            int64_t value=length==2?va_arg(args,long long):length==1?va_arg(args,long):
                length==3?va_arg(args,ptrdiff_t):va_arg(args,int);
            /* Unsigned subtraction handles INT64_MIN without signed overflow. */
            if(value<0){sign='-';number=UINT64_C(0)-(uint64_t)value;}else number=(uint64_t)value;
        }else if(spec=='u'||spec=='x'||spec=='X'){
            number=length==2?va_arg(args,unsigned long long):length==1?va_arg(args,unsigned long):
                length==3?va_arg(args,size_t):va_arg(args,unsigned int);
            if(spec!='u')base=16;
        }else if(spec=='p'){
            number=(uintptr_t)va_arg(args,void *);base=16;
            sink(context,'0');sink(context,'x');count+=2;
        }else{
            const char *s="<unsupported-format>";while(*s)sink(context,*s++);return -1;
        }
        do{
            unsigned digit;
            if(base==16){digit=(unsigned)(number&15);number>>=4;}
            else if(number<=UINT32_MAX){unsigned value=(unsigned)number;digit=value%10;number=value/10;}
            else {uint64_t quotient=number/10;digit=(unsigned)(number-quotient*10);number=quotient;}
            buffer[n++]=(char)(digit<10?'0'+digit:(spec=='X'?'A':'a')+digit-10);
        }while(number);
        pad=width>n+(sign!=0)?width-n-(sign!=0):0;
        if(!left&&!zero)log_repeat(sink,context,' ',pad);
        if(sign)sink(context,sign);
        if(!left&&zero)log_repeat(sink,context,'0',pad);
        for(i=n;i>0;i--)sink(context,buffer[i-1]);
        if(left)log_repeat(sink,context,' ',pad);
        count+=(int)(n+pad+(sign!=0));
    }
    return count;
}
#ifndef ARUCO_LOG_HOST_TEST
#include "al_log.h"
#endif
#if !defined(ARUCO_LOG_HOST_TEST) || defined(ARUCO_LOG_WRAPPER_TEST)
#ifdef ARUCO_LOG_WRAPPER_TEST
extern void AlLog_WriteByte(unsigned char byte);
#endif
static void log_uart(void *context,char byte)
{(void)context;AlLog_WriteByte((unsigned char)byte);}
/* Linker wrapper is local to this firmware, not a patch of the shared SDK. */
int __wrap_al_simp_printf(const char *format,...)
{
    int count;va_list args;va_start(args,format);
    count=ua_log_vformat(log_uart,0,format,args);va_end(args);return count;
}
/* SDK exception/backtrace code also calls newlib printf/puts. Preserve those
 * integer diagnostics through the same UART sink, without stdio FILE buffers. */
int __wrap_printf(const char *format,...) __attribute__((alias("__wrap_al_simp_printf")));
int __wrap_puts(const char *text)
{
    if(!text)return -1;
    while(*text)log_uart(0,*text++);
    log_uart(0,'\n');return 0;
}
#endif
