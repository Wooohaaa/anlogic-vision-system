#ifndef MOCK_SDK_H
#define MOCK_SDK_H
#include <stdint.h>
#include <stddef.h>
typedef uint32_t AL_U32;
typedef uintptr_t AL_REG;
typedef struct {struct {AL_REG BaseAddr;} Dev;} AL_GPIO_HalStruct;
typedef struct {unsigned unused;} AL_USART_HalStruct;
typedef struct {unsigned VectorMode,TrigMode,Priority;} AL_INTR_AttrStrct;
static uint64_t mock_now,mock_compare;
static unsigned mock_output;
static AL_GPIO_HalStruct mock_gpio;
static AL_USART_HalStruct mock_uart;
#define GPIO_GRP0_OVAL_ADDR 0
#define AL_REG32_READ(a) (mock_output)
#define AL_REG32_WRITE(a,v) ((void)(a),mock_output=(v))
#define AL_NULL NULL
#define AL_OK 0
#define AL_GPIO_OUTPUT 1
#define AL_GPIO_INPUT 0
#define AL_LOG_LEVEL_NOTICE 0
#define AL_LOG(...) ((void)0)
#define NON_VECTOR_INTERRUPT 0
#define LEVEL_HIGH_TRIGGER 0
#define SysTimer_IRQn 0
#define USART0_BASE_ADDR 0
#define USART1_BASE_ADDR 1
#define AL_USART_STATUS_EMPTY 0
static void AlIntr_SetLocalInterrupt(unsigned v){(void)v;}
static void AlGpio_Hal_WritePin(AL_GPIO_HalStruct *g,unsigned p,unsigned v){(void)g;if(v)mock_output|=1U<<p;else mock_output&=~(1U<<p);}
static unsigned AlGpio_Hal_ReadPin(AL_GPIO_HalStruct *g,unsigned p){(void)g;(void)p;return 1;}
static int AlGpio_Hal_Init(AL_GPIO_HalStruct **g,unsigned n,void *v){(void)n;(void)v;*g=&mock_gpio;return 0;}
static void AlGpio_Hal_SetDirection(AL_GPIO_HalStruct *g,unsigned d,unsigned p){(void)g;(void)d;(void)p;}
static int AlUsart_Hal_Init(AL_USART_HalStruct **u,unsigned n,void *a,void *b){(void)n;(void)a;(void)b;*u=&mock_uart;return 0;}
static unsigned AlUsart_ll_GetStatus(unsigned b){(void)b;return 1;}
static unsigned AlUsart_ll_RecvData(unsigned b){(void)b;return 0;}
static void AlUsart_ll_EnableRx(unsigned b,unsigned v){(void)b;(void)v;}
static void AlUsart_ll_SetRxSize(unsigned b,unsigned v){(void)b;(void)v;}
static uint64_t SysTimer_GetLoadValue(void){return mock_now;}
static void SysTimer_SetCompareValue(uint64_t v){mock_compare=v;}
static unsigned AlSys_GetTimerFreq(void){return 1000000;}
static void SysTimer_Stop(void){}
static void SysTimer_Start(void){}
static int AlIntr_RegHandler(unsigned n,AL_INTR_AttrStrct *a,void (*f)(void*),void *v){(void)n;(void)a;(void)f;(void)v;return 0;}
#endif
