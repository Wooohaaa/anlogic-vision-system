/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "al_type.h"
#include "al_chip.h"
#include "al_intr.h"
#include "al_systimer.h"

extern void AlGic_Init(void);
extern AL_U32 AlGic_CorePos(void);
extern AL_VOID AlCpu_WakeUpMultipleCpus(AL_U64 CpuId, AL_U64 ResetAddr);
extern AL_VOID _start(AL_VOID);


AL_VOID AlChip_Init(AL_VOID) __attribute__((alias ("AlChip_Dr1m90Init")));

AL_VOID AlChip_Dr1m90Init(AL_VOID)
{
#ifndef SUPPORT_NONSECURE
	AlGic_Init();
	AlSys_StartTimer();
#endif

#ifdef SMP
	AlCpu_WakeUpMultipleCpus(AlGic_CorePos(), _start);
#endif
}
