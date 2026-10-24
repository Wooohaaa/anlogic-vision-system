/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef __AL_AXI_INTC_HAL_H_
#define __AL_AXI_INTC_HAL_H_

#ifdef __cplusplus
extern "C" {
#endif

#include "al_axi_intc_dev.h"

typedef struct
{
    AL_AXI_INTC_DevStruct   Dev;
    AL_Lock                 Lock;

} AL_AXI_INTC_HalStruct;

AL_S32 AlAxiIntc_Hal_Init(AL_AXI_INTC_HalStruct **Handle, AL_U32 DevId);

AL_S32 AlAxiIntc_Hal_RegHandler(AL_AXI_INTC_InitStruct *InitConfig, AL_INTR_Func Func, AL_VOID *Param);

AL_VOID AlAxiIntc_Hal_Enable(AL_AXI_INTC_HalStruct *Handle);

#ifdef __cplusplus
}
#endif


#endif /* __AL_AXI_INTC_HAL_H_ */