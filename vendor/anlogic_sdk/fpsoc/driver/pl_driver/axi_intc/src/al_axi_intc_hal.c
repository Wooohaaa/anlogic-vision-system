/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */


#include "al_axi_intc_hal.h"

AL_AXI_INTC_HalStruct AlAxiIntcHandle[AL_AXI_INTC_NUM_INSTANCE];

AL_S32 AlAxiIntc_Hal_Init(AL_AXI_INTC_HalStruct **Handle, AL_U32 DevId)
{
    AL_S32 Ret = AL_OK;
    AlAxiIntc_HwConfigStruct *HwConfig = AL_NULL;

    AL_ASSERT((Handle != AL_NULL), AL_AXI_INTC_ERR_ILLEGAL_PARAM);

    HwConfig = AlAxiIntc_Dev_LookupConfig(DevId);
    if (HwConfig != AL_NULL) {
        *Handle = &AlAxiIntcHandle[DevId];
    } else {
        return AL_AXI_INTC_ERR_ILLEGAL_PARAM;
    }

    Ret = AlAxiIntc_Dev_Init(&(*Handle)->Dev, HwConfig);
    if (Ret != AL_OK) {
        return Ret;
    }

#if defined(__riscv)
    AL_INTR_AttrStrct IntrAttr = {
        .TrigMode   =  HwConfig->IntrTrigMode,
        .Priority   =  0,
        .VectorMode =  NON_VECTOR_INTERRUPT,
    };
#else
    AL_INTR_AttrStrct IntrAttr = {
        .TrigMode   = HwConfig->IntrTrigMode,
        .Priority   = 137,
    };
#endif

    if (HwConfig->IntcType == AXI_INTC_NOCASCADE || HwConfig->IntcType == AXI_INTC_PRIMARY) {
        (AL_VOID)AlIntr_RegHandler((*Handle)->Dev.HwConfig.IntrId, &IntrAttr, AlAxiIntc_Dev_IntrHandler, &(*Handle)->Dev);
    }

    Ret = AlOsal_Lock_Init(&(*Handle)->Lock, "AxiIntc_Lock");
    if (Ret != AL_OK) {
        return Ret;
    }

    return AL_OK;
}

AL_VOID AlAxiIntc_Hal_Enable(AL_AXI_INTC_HalStruct *Handle)
{
    AL_S32 Ret = AL_OK;

    Ret = AlOsal_Lock_Take(&Handle->Lock, AL_WAITFOREVER);
    if (Ret != AL_OK) {
        return ;
    }

    AL_REG BaseAddr = Handle->Dev.HwConfig.BaseAddress;

    AlAxiIntc_ll_EnableMasterIrq(BaseAddr);
    AlAxiIntc_ll_EnableHardwareIntr(BaseAddr);

    (AL_VOID)AlOsal_Lock_Release(&Handle->Lock);
}

AL_VOID AlAxiIntc_Hal_Disable(AL_AXI_INTC_HalStruct *Handle)
{
    AL_S32 Ret = AL_OK;

    Ret = AlOsal_Lock_Take(&Handle->Lock, AL_WAITFOREVER);
    if (Ret != AL_OK) {
        return ;
    }

    AL_REG BaseAddr = Handle->Dev.HwConfig.BaseAddress;
    AlAxiIntc_ll_DisableIrq(BaseAddr);

    (AL_VOID)AlOsal_Lock_Release(&Handle->Lock);
}


AL_S32 AlAxiIntc_Hal_RegHandler(AL_AXI_INTC_InitStruct *InitConfig, AL_INTR_Func Func, AL_VOID *Param)
{
    AL_AXI_INTC_HalStruct *Handle;

    AL_ASSERT((InitConfig != AL_NULL), AL_AXI_INTC_ERR_ILLEGAL_PARAM);
    AL_ASSERT((Func != AL_NULL), AL_AXI_INTC_ERR_ILLEGAL_PARAM);
    AL_ASSERT((InitConfig->AxiIntcDevId < AL_AXI_INTC_NUM_INSTANCE), AL_AXI_INTC_ERR_ILLEGAL_PARAM);

    Handle = &AlAxiIntcHandle[InitConfig->AxiIntcDevId];

    AlAxiIntc_Dev_RegHandler(&Handle->Dev, InitConfig, Func, Param);

    return AL_OK;
}

AL_S32 AlIntr_Hal_RegHandler(AL_U32 IntrId, AL_INTR_AttrStrct *IntrAttr, AL_INTR_Func Func, AL_VOID *Param)
{
    AL_S32 Ret;
    AL_AXI_INTC_HalStruct *AxiIntcHandle;
    AL_AXI_INTC_InitStruct InitConfig;

    if (!AL_REG32_GET_BIT(&IntrId, AL_AXI_INTC_INTR_BIT)) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AlIntr_Hal_RegHandler invalid AXI INTC intr ID %d", IntrId);
        return AL_AXI_INTC_ERR_ILLEGAL_PARAM;
    }

    (AL_VOID)IntrAttr;

    InitConfig.AxiIntcDevId = AL_REG32_GET_BITS(&IntrId, AL_AXI_INTC_INTR_DEVID_BIT, AL_AXI_INTC_INTR_DEVID_BIT_SIZE);
    InitConfig.IntrId = AL_REG32_GET_BITS(&IntrId, AL_AXI_INTC_INTR_ID_BIT, AL_AXI_INTC_INTR_ID_BIT_SIZE);
    InitConfig.IntrMode = AL_AXI_INTC_NORMAL_INTR;

    Ret = AlAxiIntc_Hal_Init(&AxiIntcHandle, InitConfig.AxiIntcDevId);
    if ((Ret != AL_OK) && (Ret != AL_AXI_INTC_ERR_READY)) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AlAxiIntc_Hal_Init fail\r\n");
        return Ret;
    }

    AlAxiIntc_Hal_RegHandler(&InitConfig, Func, Param);

    return AL_OK;
}