
#ifndef __AL_CORE_FEATURE_TIMER_H_
#define __AL_CORE_FEATURE_TIMER_H_
/*!
 * @file     core_feature_timer.h
 * @brief    System Timer feature API header file for Nuclei N/NX Core
 */
/*
 * System Timer Feature Configuration Macro:
 * 1. __SYSTIMER_PRESENT:  Define whether Private System Timer is present or not.
 *   * 0: Not present
 *   * 1: Present
 * 2. SYSTIMER__BASE_ADDR:  Define the base address of the System Timer.
 */
#ifdef __cplusplus
 extern "C" {
#endif

#include "al_rv32_core.h"
#include "soc_plat.h"
#include "al_intr.h"
typedef struct
{
    AL_U64        TimerCycle;
    AL_BOOL       ReloadEn;
#if !SOFTCORE_USE_MTIME
    AL_U64        LongDelay;
    AL_U32        LongDelayLast;
#endif
} AlSoftcoreTimer_Dev_Struct;

typedef struct
{
    AL_U64        TimerCycle;
    AL_BOOL       ReloadEn;
} AlSoftcoreTimer_HwConfigStruct;
#define CSR_MIE 0x304

#define SYSTIMER_BASE_ADDR       (0xFFF00000UL)
#define MTIME_CMPL  *(volatile AL_U32*)(SYSTIMER_BASE_ADDR+0x4000)
#define MTIME_CMPH  *(volatile AL_U32*)(SYSTIMER_BASE_ADDR+0x4004)
#define MTIME_CNTL  *(volatile AL_U32*)(SYSTIMER_BASE_ADDR+0xBFF8)
#define MTIME_CNTH  *(volatile AL_U32*)(SYSTIMER_BASE_ADDR+0xBFFC)
//By poking CSR MIE
void SysTimerIntr_enable(void);
void SysTimerIntr_disable(void);
void SysTimerIntr_RegHandler(AL_INTR_Func Func, AL_VOID *Param);
AL_S32 SysTimer_Dev_Init(AlSoftcoreTimer_HwConfigStruct *SysTimer);
void SysTimer_IntrHandler(void);


#if SOFTCORE_USE_MTIME


static uint64_t GetMTimeCnt()
{
  while (1)
  {
    uint32_t hi=MTIME_CNTH;
    uint32_t lo=MTIME_CNTL;
    if(hi==MTIME_CNTH)
      return ((uint64_t) hi<<32 | lo);
  }
}

static inline uint64_t GetMTimeCmp()
{
  uint32_t hi=MTIME_CMPH;
  uint32_t lo=MTIME_CMPL;
  return ((uint64_t) hi<<32 | lo);
}
static inline void SetMTimeCmp(uint64_t value)
{
  MTIME_CMPL=0xffffffff;
  MTIME_CMPH=(uint32_t)(value >> 32);
  MTIME_CMPL=(uint32_t)value;
  return;
}

#else


static inline void SetSystickCfg(uint32_t data,uint8_t enable)
{
  MTIME_CMPL=(data&0xEFFFFFFF) | ((enable!=0)<<31);
}
static inline uint32_t GetSystickCfg()
{
  return MTIME_CMPL;
}

static void ClrSystickInt()
{
  MTIME_CNTL=0x00000000;
  return;
}

#endif 
#ifdef __cplusplus
}
#endif
#endif /** AL_CORE_FEATURE_TIMER_H  */
