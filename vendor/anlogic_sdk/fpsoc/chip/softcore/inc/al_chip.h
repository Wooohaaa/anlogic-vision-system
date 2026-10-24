/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef __AL_CHIP_H_
#define __AL_CHIP_H_

#ifdef __cplusplus
 extern "C" {
#endif


void AlChip_SoftcoreInit(AL_VOID);

#define AlChip_Init AlChip_SoftcoreInit

//#include "al_hwcfg.h"
#include "soc_plat.h"
#include "al_rv32_core.h"

#define __riscv

#define SYSTEM_CLOCK  SOFTCORE_CLK_RATE
#define CPU_FREQUENCY SOFTCORE_CLK_RATE

/**
 * \brief Set the complete 64-bit machine cycle counter on RV32.
 */
__STATIC_FORCEINLINE void __set_rv_cycle(uint64_t Cycle)
{
    ARCH_SYSREG_WRITE(CSR_MCYCLE, 0);
    ARCH_SYSREG_WRITE(CSR_MCYCLEH, (uint32_t)(Cycle >> 32));
    ARCH_SYSREG_WRITE(CSR_MCYCLE, (uint32_t)Cycle);
}

/**
 * \brief Read the complete 64-bit machine cycle counter on RV32.
 */
__STATIC_FORCEINLINE uint64_t __get_rv_cycle(void)
{
    uint32_t HighBefore;
    uint32_t Low;
    uint32_t HighAfter;

    HighBefore = ARCH_SYSREG_READ(CSR_MCYCLEH);
    Low        = ARCH_SYSREG_READ(CSR_MCYCLE);
    HighAfter  = ARCH_SYSREG_READ(CSR_MCYCLEH);

    if (HighBefore != HighAfter) {
        Low = ARCH_SYSREG_READ(CSR_MCYCLE);
    }

    return ((uint64_t)HighAfter << 32) | Low;
}

/**
 * \brief Set the complete 64-bit machine instruction-retired counter on RV32.
 */
__STATIC_FORCEINLINE void __set_rv_instret(uint64_t Instret)
{
    ARCH_SYSREG_WRITE(CSR_MINSTRET, 0);
    ARCH_SYSREG_WRITE(CSR_MINSTRETH, (uint32_t)(Instret >> 32));
    ARCH_SYSREG_WRITE(CSR_MINSTRET, (uint32_t)Instret);
}

/**
 * \brief Read the complete 64-bit machine instruction-retired counter on RV32.
 */
__STATIC_FORCEINLINE uint64_t __get_rv_instret(void)
{
    uint32_t HighBefore;
    uint32_t Low;
    uint32_t HighAfter;

    HighBefore = ARCH_SYSREG_READ(CSR_MINSTRETH);
    Low        = ARCH_SYSREG_READ(CSR_MINSTRET);
    HighAfter  = ARCH_SYSREG_READ(CSR_MINSTRETH);

    if (HighBefore != HighAfter) {
        Low = ARCH_SYSREG_READ(CSR_MINSTRET);
    }

    return ((uint64_t)HighAfter << 32) | Low;
}

/*----------------------------------------------------------------------------
* Define Interrupt Number (should be passed from soc_plat.h)
*----------------------------------------------------------------------------*/

#define AL_DEFAULT_ATTR(name)  AL_INTR_AttrStrct name = {   \
            .TrigMode   =  LEVEL_HIGH_TRIGGER,              \
            .Priority   =  0,                               \
            .VectorMode =  NON_VECTOR_INTERRUPT,            \
};


#ifdef __cplusplus
}
#endif
#endif /* AL_CHIP_H */
