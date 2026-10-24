/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef __AL_AXI_INTC_LL_H_
#define __AL_AXI_INTC_LL_H_

#ifdef __cplusplus
extern "C" {
#endif

#include "al_axi_intc_hw.h"

typedef enum
{
    AL_AXI_INTC_FUNC_DISABLE    = 0,
    AL_AXI_INTC_FUNC_ENABLE     = 1
} AL_AXI_INTC_FunctionEnum;

typedef enum
{
    AL_AXI_INTC_NORMAL_INTR     = 0,
    AL_AXI_INTC_FAST_INTR       = 1
} AL_AXI_INTC_IntrModeEnum;


static inline AL_U32 AlAxiIntc_ll_GetIntrStatus(AL_REG BaseAddr)
{
    return (AL_PL_REG32_READ(BaseAddr + AXI_INTC_ISR_OFFSET) & AL_PL_REG32_READ(BaseAddr + AXI_INTC_IER_OFFSET));
}

static inline AL_U32 AlAxiIntc_ll_GetIntrPendindStatus(AL_REG BaseAddr)
{
    return AL_PL_REG32_READ(BaseAddr + AXI_INTC_IPR_OFFSET);
}

static inline AL_VOID AlAxiIntc_ll_EnableAllIntr(AL_REG BaseAddr, AL_U32 IntrMask)
{
    AL_REG32_WRITE(BaseAddr + AXI_INTC_IER_OFFSET, IntrMask);
}

static inline AL_VOID AlAxiIntc_ll_EnableIntr(AL_REG BaseAddr, AL_U32 IntrId)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AXI_INTC_IER_OFFSET, IntrId, AL_AXI_INTC_FUNC_ENABLE);
}

static inline AL_VOID AlAxiIntc_ll_AckAllIntr(AL_REG BaseAddr, AL_U32 IntrAckMask)
{
    AL_REG32_WRITE(BaseAddr + AXI_INTC_IAR_OFFSET, IntrAckMask);
}

static inline AL_VOID AlAxiIntc_ll_IntrAck(AL_REG BaseAddr, AL_U32 IntrId)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AXI_INTC_IAR_OFFSET, IntrId, AL_AXI_INTC_FUNC_ENABLE);
}

static inline AL_VOID AlAxiIntc_ll_AckIntrMask(AL_REG BaseAddr, AL_U32 Mask)
{
    AL_REG32_WRITE(BaseAddr + AXI_INTC_IAR_OFFSET, Mask);
}

static inline AL_VOID AlAxiIntc_ll_SetIntrEnable(AL_REG BaseAddr, AL_U32 IntrId)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AXI_INTC_SIE_OFFSET, IntrId, AL_AXI_INTC_FUNC_ENABLE);
}

static inline AL_VOID AlAxiIntc_ll_ClrIntrEnable(AL_REG BaseAddr, AL_U32 IntrId)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AXI_INTC_CIE_OFFSET, IntrId, AL_AXI_INTC_FUNC_ENABLE);
}

static inline AL_U32 AlAxiIntc_ll_GetIntrVector(AL_REG BaseAddr)
{
    return AL_PL_REG32_READ(BaseAddr + AXI_INTC_IVR_OFFSET);
}

static inline AL_VOID AlAxiIntc_ll_DisableIrq(AL_REG BaseAddr)
{
    AL_REG32_WRITE(BaseAddr + AXI_INTC_MER_OFFSET, AL_AXI_INTC_FUNC_DISABLE);
}

static inline AL_VOID AlAxiIntc_ll_EnableMasterIrq(AL_REG BaseAddr)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AXI_INTC_MER_OFFSET, AXI_INTC_MER_IRQ_ENABLE_SHIFT, AL_AXI_INTC_FUNC_ENABLE);
}

static inline AL_VOID AlAxiIntc_ll_EnableHardwareIntr(AL_REG BaseAddr)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AXI_INTC_MER_OFFSET, AXI_INTC_MER_HARDWARE_INTR_ENABLE_SHIFT, AL_AXI_INTC_FUNC_ENABLE);
}

static inline AL_VOID AlAxiIntc_ll_SetIntrMode(AL_REG BaseAddr, AL_U32 IntrId, AL_AXI_INTC_IntrModeEnum Mode)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AXI_INTC_IMR_OFFSET, IntrId, Mode);
}

static inline AL_U32 AlAxiIntc_ll_GetIntrLevel(AL_REG BaseAddr)
{
    return AL_PL_REG32_READ(BaseAddr + AXI_INTC_ILR_OFFSET);
}

static inline AL_VOID AlAxiIntc_ll_SetIntrLevel(AL_REG BaseAddr, AL_U32 IntrLevel)
{
    AL_REG32_WRITE(BaseAddr + AXI_INTC_ILR_OFFSET, IntrLevel);
}

static inline AL_U32 AlAxiIntc_ll_GetIntrVectorAddr(AL_REG BaseAddr)
{
    return AL_PL_REG32_READ(BaseAddr + AXI_INTC_IVAR_OFFSET);
}

static inline AL_VOID AlAxiIntc_ll_SetIntrVectorAddr(AL_REG BaseAddr, AL_U32 Addr)
{
    AL_REG32_WRITE(BaseAddr + AXI_INTC_IVAR_OFFSET, Addr);
}

#ifdef __cplusplus
}
#endif


#endif /* __AL_AXI_INTC_LL_H_ */