/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */


#include <stdio.h>
#include "soc_plat.h"
#include "al_log.h"
#include "al_printf.h"
#include "al_core.h"
#include "al_chip.h"


AL_U64 SystemCoreClock = SOFTCORE_CLK_RATE;  /* System Clock Frequency (Core Clock) */
void AlChip_SoftcoreInit(AL_VOID){
	CLSIC_Init();
}
void cache_config(void)
{
#ifdef ENABLE_ICACHE
    AlCache_EnableICache();
#endif

#ifdef ENABLE_DCACHE
    AlCache_EnableDCache();
#endif
}


void _premain_init(void)
{
    cache_config();
    AlChip_Init();
}

void components_init(void)
{
    AlLog_Init();

#ifdef AL_PRINT_ASYNC
    AlPrint_Init();
#endif
}
