
/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef __AL_AXI_INTC_DEV_H_
#define __AL_AXI_INTC_DEV_H_

#ifdef __cplusplus
extern "C" {
#endif

#include "al_axi_intc_ll.h"

#define AL_AXI_INTC_MAX_INTR_NUMBER         32

typedef enum
{
    AL_AXI_INTC_NOT_READY = 1,
    AL_AXI_INTC_READY,
} AL_AXI_INTC_ErrorCodeEnum;

#define AL_AXI_INTC_ERR_ILLEGAL_PARAM        (AL_DEF_ERR(AL_AXI_INTC, AL_LOG_LEVEL_ERROR, AL_ERR_ILLEGAL_PARAM))
#define AL_AXI_INTC_ERR_NOT_READY            (AL_DEF_ERR(AL_AXI_INTC, AL_LOG_LEVEL_ERROR, AL_ERR_NOT_READY))
#define AL_AXI_INTC_ERR_READY                (AL_DEF_ERR(AL_AXI_INTC, AL_LOG_LEVEL_ERROR, AL_AXI_INTC_READY))

typedef AL_VOID (*AL_AXI_INTC_INTR_Func)(AL_VOID *Param);

typedef struct
{
    AL_INTR_Func    Func;
    AL_VOID         *Param;
} AL_AXI_INTC_INTR_HandlerStruct;

typedef struct
{
    AL_U32 AxiIntcDevId;
    AL_U32 IntrId;
    AL_AXI_INTC_IntrModeEnum IntrMode;
} AL_AXI_INTC_InitStruct;

typedef enum
{
    AL_AXI_INTC_STATE_NOT_INIT     = (0x0),
    AL_AXI_INTC_STATE_READY        = (0x01 << 0),
} AL_AXI_INTC_StateEnum;

typedef struct
{
    AlAxiIntc_HwConfigStruct        HwConfig;
    AL_AXI_INTC_StateEnum           State;

} AL_AXI_INTC_DevStruct;

/* PL IP Interrupt ID define */
#define AL_AXI_INTC_INTR_BIT                31
#define AL_AXI_INTC_INTR_DEVID_BIT          24
#define AL_AXI_INTC_INTR_ID_BIT             0

#define AL_AXI_INTC_INTR_DEVID_BIT_SIZE     7
#define AL_AXI_INTC_INTR_ID_BIT_SIZE        24


AL_S32 AlAxiIntc_Dev_Init(AL_AXI_INTC_DevStruct *AxiIntc, AlAxiIntc_HwConfigStruct *HwConfig);

AL_S32 AlAxiIntc_Dev_RegHandler(AL_AXI_INTC_DevStruct *AxiIntc, AL_AXI_INTC_InitStruct *InitConfig, AL_INTR_Func Func, AL_VOID *Param);

AlAxiIntc_HwConfigStruct *AlAxiIntc_Dev_LookupConfig(AL_U32 DevId);

AL_VOID AlAxiIntc_Dev_IntrHandler(AL_VOID *Instance);

#ifdef __cplusplus
}
#endif


#endif /* __AL_AXI_INTC_DEV_H_ */