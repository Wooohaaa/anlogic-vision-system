/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <stdio.h>

#include "al_log.h"
#include "al_printf.h"
#include "al_core.h"
#include "al_chip.h"
#include "al_hal.h"


extern void AlMpu_Init(void);

AL_U64 SystemCoreClock = SYSTEM_CLOCK;  /* System Clock Frequency (Core Clock) */

/*
 * When compiling C++ code with static objects, the compiler inserts
 * a call to __cxa_atexit() with __dso_handle as one of the arguments.
 * The dummy versions of these symbols should be provided.
 */

void *__dso_handle = (void *) &__dso_handle;

__WEAK void _init()
{
}

__WEAK void _fini()
{
}


void cplusplus_init()
{
    typedef void (*pfunc)(void);
    extern const pfunc __ctors_start__;
    extern const pfunc __ctors_end__;

    const uintptr_t start_addr = (uintptr_t)&__ctors_start__;
    const uintptr_t end_addr = (uintptr_t)&__ctors_end__;
    const size_t func_size = sizeof(pfunc);
    const size_t num_ctors = (end_addr - start_addr) / func_size;

    for (size_t i = 0; i < num_ctors; i++) {
        const pfunc func = (&__ctors_start__)[i];
        if (func != NULL) {
            func();
        }
    }
}

void components_init(void)
{
    AL_S32 Ret;

    AlLog_Init();
    cplusplus_init();

#ifdef HAVE_IPCPS_DRIVER
#ifdef SMP
	if (AlCore_GetCoreId() == 0) {
		AlIpc_ll_SpinLockInit();
	}
#else
#ifndef ARM_CORE_SLAVE
	AlIpc_ll_SpinLockInit();
#endif
#endif
#endif

#ifdef AL_PRINT_ASYNC
    AlPrint_Init();
#endif

#ifdef ENABLE_MMU
    /* defined in the link script */
    extern AL_U32 _no_cache_section_start, _no_cache_section_end;
    if (&(_no_cache_section_start) != &(_no_cache_section_end)) {
        Ret = AlCache_SetMemoryAttr((AL_UINTPTR) &(_no_cache_section_start), (AL_UINTPTR) &(_no_cache_section_end), Al_MEM_DMA);
        if (Ret != AL_OK) {
            AL_LOG(AL_LOG_LEVEL_ERROR, "AlCache_SetMemoryAttr failed ret = 0x%x\r\n", Ret);
        }
    }
#endif

#if (defined __aarch64__) && (MPU_PROTECT_MODE != 0)
    AlMpu_Init();
#endif

    (AL_VOID)Ret;
}
