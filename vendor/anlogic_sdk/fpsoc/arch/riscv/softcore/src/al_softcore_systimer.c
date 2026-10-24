/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

 #include "al_type.h"
 #include "al_chip.h"
 #include "al_rv32_core.h"
 #include "al_rv32_sysregs.h"
 #include "al_softcore_systimer.h"
 #include "al_systimer.h"
 #include "al_arch_sysops.h"
 #include "al_intr.h"
 #include "soc_plat.h"

static AL_INTR_HandlerStruct TimerHandle;
static AlSoftcoreTimer_Dev_Struct SoftcoreTimer_DevCfg;
AL_U64 AlSys_GetTimerTickCount(AL_VOID)
{
    AL_U64 core_mcycle;
    volatile uint32_t high0, low, high;

    high0 = ARCH_SYSREG_READ(CSR_MCYCLEH);
    low = ARCH_SYSREG_READ(CSR_MCYCLE);
    high = ARCH_SYSREG_READ(CSR_MCYCLEH);
    if (high0 != high) {
        low = ARCH_SYSREG_READ(CSR_MCYCLE);
    }
    core_mcycle = (((uint64_t)high) << 32) | low;
    return core_mcycle;
}
 
 AL_VOID AlSys_DelayTicks(AL_U64 TickCount)
 {
    AL_U64 TickEnd, TickCur;

    TickCur = AlSys_GetTimerTickCount();
    TickEnd = TickCur + TickCount;

    do {
        TickCur = AlSys_GetTimerTickCount();
    } while (TickCur < TickEnd);
 }
 
 AL_U64 AlSys_GetTimerFreq(AL_VOID)
{
    return SOFTCORE_CLK_RATE;
}

 AL_VOID AlSys_UDelay(AL_U64 Usec)
 {
    AlSys_DelayTicks(Usec * AlSys_GetTimerFreq() / 1000000);
 }
 
 
 AL_VOID AlSys_MDelay(AL_U64 Msec)
 {
    AlSys_DelayTicks(Msec * AlSys_GetTimerFreq() / 1000);
 }

void SysTimerIntr_enable(void)
{
    ARCH_SYSREG_SET(CSR_MIE, 0x80) ;
}

void SysTimerIntr_disable(void)
{
    ARCH_SYSREG_CLEAR(CSR_MIE, 0x80) ;
}
void SysTimerIntr_RegHandler(AL_INTR_Func Func, AL_VOID *Param)
{
    TimerHandle.Func = Func;
    TimerHandle.Param = Param;
    SysTimerIntr_enable();
}
AL_S32 SysTimer_Dev_Init(AlSoftcoreTimer_HwConfigStruct *SysTimer){
#if SOFTCORE_USE_MTIME
    SetMTimeCmp(SysTimer->TimerCycle);
#else
    AL_U64 LongDelay;
    LongDelay = (SysTimer->TimerCycle)>>30;
    if(LongDelay == 0){
        SetSystickCfg((SysTimer->TimerCycle)&0x3FFFFFFF,AL_FUNC_ENABLE);
    }else{
        SoftcoreTimer_DevCfg.LongDelay=LongDelay;
        SoftcoreTimer_DevCfg.LongDelayLast=(SysTimer->TimerCycle)&0x3FFFFFFF;
        SetSystickCfg(0x3FFFFFFF,AL_FUNC_ENABLE);
    }
#endif
    SoftcoreTimer_DevCfg.TimerCycle=(SysTimer->TimerCycle);
    SoftcoreTimer_DevCfg.ReloadEn=(SysTimer->ReloadEn);
    return AL_OK;
}

void SysTimer_IntrHandler(void){
#if SOFTCORE_USE_MTIME
    if(SoftcoreTimer_DevCfg.ReloadEn){
        SetMTimeCmp(GetMTimeCmp()+SoftcoreTimer_DevCfg.TimerCycle);
    }else{
        SysTimerIntr_disable();
    }
    TimerHandle.Func(TimerHandle.Param);
#else
    static AL_U64 LongDelayCnt;
    if(SoftcoreTimer_DevCfg.LongDelay == 0){
        TimerHandle.Func(TimerHandle.Param);
        ClrSystickInt();
    }
    else if(LongDelayCnt < SoftcoreTimer_DevCfg.LongDelay){
        ClrSystickInt();
        LongDelayCnt++;
    }else{
        if(GetSystickCfg()!=0xBFFFFFFF){
            SetSystickCfg(0x3FFFFFFF,AL_FUNC_ENABLE);
            TimerHandle.Func(TimerHandle.Param);
            LongDelayCnt=0;
        }else{
            SetSystickCfg(SoftcoreTimer_DevCfg.LongDelayLast,AL_FUNC_ENABLE);
        }
    }
#endif
}