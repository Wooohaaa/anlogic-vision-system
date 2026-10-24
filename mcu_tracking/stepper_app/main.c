#include "al_core.h"
#include "al_gpio_hal.h"
#include "al_intr.h"
#include "al_rv_systimer.h"
#include "al_usart_ll.h"
#include "al_usart_hal.h"
#include "al_hwcfg.h"
#include "aruco_runtime.h"
#include "stepper_control.h"
#include "stepper_key.h"
static StepperControl motors;
static StepperKey motor_key;
static AL_GPIO_HalStruct *gpio;
static AL_USART_HalStruct *uart1;
static uint64_t ticks,last_byte;
static unsigned used,last_seq,seq_ready,packets,rejected;
static unsigned char packet_buffer[9];
static uint32_t now_ms(void){return (uint32_t)(SysTimer_GetLoadValue()/(ticks*1000u));}
static uint32_t motor_read(void *ctx,unsigned off)
{(void)ctx;return *(volatile uint32_t *)(uintptr_t)(0x80000000u+off);}
static void motor_write(void *ctx,unsigned off,uint32_t value)
{(void)ctx;*(volatile uint32_t *)(uintptr_t)(0x80000000u+off)=value;}
static void motor_status(void)
{
    AL_LOG(AL_LOG_LEVEL_NOTICE,"STEPPER v83 available=%u mode=%u status=%u pos=%u service_max_ms=%u packets=%u bad=%u target=%u x=%u y=%u age_ms=%u v0=%d v1=%d\r\n",
        motors.available,motors.mode,motor_read(0,0x184),motor_read(0,0x194),
        motors.service_max_ms,packets,rejected,motors.valid && motors.stable>=3 && now_ms()-motors.last_target_ms<=100,
        motors.pixel[0],motors.pixel[1],now_ms()-motors.last_target_ms,motors.velocity[0],motors.velocity[1]);
    ua_aruco_runtime_status();
}
static void motor_command(unsigned char c)
{
    // ?=status, s=hard OFF (origin lost), z=manual zero, n=finite scan.
    // No serial command silently installs demo calibration or starts tracking.
    if(c=='s')st_stop(&motors);
    else if(c=='z')st_zero(&motors);
    else if(c=='n')st_start(&motors,ST_SCAN,now_ms());
    else if(c=='x')st_start(&motors,ST_AXIS0,now_ms());
    else if(c=='y')st_start(&motors,ST_AXIS1,now_ms());
    // User-armed only: operator zero required. No target means armed WAIT;
    // motion resumes only after three fresh frames, without another g.
    else if(c=='g')st_start(&motors,ST_TRACK,now_ms());
    if(c=='?' || c=='s' || c=='z' || c=='n' || c=='g' || c=='x' || c=='y')motor_status();
}
static void target_receive(unsigned char c)
{
    uint64_t now=SysTimer_GetLoadValue();
    if(used && now-last_byte>ticks*50000u){used=0;rejected++;}
    last_byte=now;
    if(!used){if(c==0x2c)packet_buffer[used++]=c;return;}
    if(used==1 && c!=9){used=c==0x2c?1:0;rejected++;return;}
    packet_buffer[used++]=c;
    if(used==9){
        unsigned x=(unsigned)packet_buffer[2]|((unsigned)packet_buffer[3]<<8);
        unsigned y=(unsigned)packet_buffer[4]|((unsigned)packet_buffer[5]<<8);
        unsigned valid=packet_buffer[6],sequence=packet_buffer[7];
        used=0;
        if(c!=0x5b || valid>1 || (valid && (x>=320 || y>=180)) ||
           (seq_ready && sequence==last_seq)){rejected++;return;}
        last_seq=sequence;seq_ready=1;packets++;
        // Invalid packet coordinates are unspecified; pass an explicit lost target.
        st_target(&motors,valid?x:0,valid?y:0,valid,now_ms());
    }
}
int main(void)
{
    volatile unsigned unused=0;
    if(AlGpio_Hal_Init(&gpio,0,AL_NULL)!=AL_OK)return -1;
    // Keep diagnostic GPIO0 low, remove all old software servo IRQ/PWM.
    for(unsigned i=0;i<3;i++){AlGpio_Hal_WritePin(gpio,i,0);AlGpio_Hal_SetDirection(gpio,AL_GPIO_OUTPUT,i);}
    AlGpio_Hal_SetDirection(gpio,AL_GPIO_INPUT,4); // FPGA synchronized KEY2
    AlGpio_Hal_WritePin(gpio,6,0);AlGpio_Hal_SetDirection(gpio,AL_GPIO_OUTPUT,6);
    ticks=AlSys_GetTimerFreq()/1000000u;if(!ticks)return -1;
    SysTimer_SetCompareValue(UINT64_MAX);SysTimer_Start();AlIntr_SetLocalInterrupt(1);
    // Includes SDK AHB divider normalization before ANY fabric access.
    ua_aruco_runtime_init();
    st_init(&motors,motor_read,motor_write,0);
    if(AlUsart_Hal_Init(&uart1,1,AL_NULL,AL_NULL)!=AL_OK)return -1;
    AlUsart_ll_EnableRx(USART1_BASE_ADDR,1);AlUsart_ll_SetRxSize(USART1_BASE_ADDR,0xffffffffu);
    AlUsart_ll_EnableRx(USART0_BASE_ADDR,1);AlUsart_ll_SetRxSize(USART0_BASE_ADDR,0xffffffffu);
    AlGpio_Hal_WritePin(gpio,6,1); // target UART acquisition only, NOT motion authorization
    AL_LOG(AL_LOG_LEVEL_NOTICE,"STEPPER v83 OFF; KEY2 toggles track (current pose = zero); ? status, s OFF, z zero, g track; axis0 UP, axis1 LEFT\r\n");
    for(;;){
        st_key_poll(&motor_key,&motors,!AlGpio_Hal_ReadPin(gpio,4),now_ms());
        for(unsigned n=0;n<32 && !(AlUsart_ll_GetStatus(USART0_BASE_ADDR)&(1u<<AL_USART_STATUS_EMPTY));n++)
            motor_command((unsigned char)AlUsart_ll_RecvData(USART0_BASE_ADDR));
        for(unsigned n=0;n<32 && !(AlUsart_ll_GetStatus(USART1_BASE_ADDR)&(1u<<AL_USART_STATUS_EMPTY));n++)
            target_receive((unsigned char)AlUsart_ll_RecvData(USART1_BASE_ADDR));
        st_service(&motors,now_ms());
        ua_aruco_runtime_step(SysTimer_GetLoadValue(),ticks,&unused,&unused,&unused,0,0);
        // Measure and enforce the longest foreground gap after ArUco work too.
        st_service(&motors,now_ms());
    }
}
