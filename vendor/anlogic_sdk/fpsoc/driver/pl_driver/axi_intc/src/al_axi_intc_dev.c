/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */


#include "al_axi_intc_dev.h"

extern AlAxiIntc_HwConfigStruct AlAxiIntc_HwConfig[];

AL_AXI_INTC_INTR_HandlerStruct AlAxiIntcHandleList[AL_AXI_INTC_NUM_INSTANCE][AL_AXI_INTC_MAX_INTR_NUMBER];

AL_U32 ALAxiIntc_BitPosMask[AL_AXI_INTC_MAX_INTR_NUMBER];

AlAxiIntc_HwConfigStruct *AlAxiIntc_Dev_LookupConfig(AL_U32 DevId)
{
    AL_U32 IntrNum;
    AlAxiIntc_HwConfigStruct *ConfigPtr = AL_NULL;

    for (IntrNum = 0; IntrNum < AL_AXI_INTC_NUM_INSTANCE; IntrNum++) {
        if (AlAxiIntc_HwConfig[IntrNum].DeviceId == DevId) {
            ConfigPtr = &AlAxiIntc_HwConfig[IntrNum];
            break;
        }
    }

    return ConfigPtr;
}

AL_S32 AlAxiIntc_Dev_Init(AL_AXI_INTC_DevStruct *AxiIntc, AlAxiIntc_HwConfigStruct *HwConfig)
{
    AL_ASSERT((AxiIntc != AL_NULL) && (HwConfig != AL_NULL), AL_AXI_INTC_ERR_ILLEGAL_PARAM);

    if ((AxiIntc->State) & AL_AXI_INTC_STATE_READY) {
        return AL_AXI_INTC_ERR_READY;
    }

    AL_REG BaseAddr;

    AxiIntc->HwConfig = *HwConfig;
    BaseAddr = HwConfig->BaseAddress;

    /*
     * Disable IRQ output signal
     * Disable all interrupt sources
     * Acknowledge all sources
     */
    AlAxiIntc_ll_DisableIrq(BaseAddr);
    AlAxiIntc_ll_EnableAllIntr(BaseAddr, 0x0);
    AlAxiIntc_ll_AckAllIntr(BaseAddr, 0xFFFFFFFF);

    AlAxiIntc_ll_EnableMasterIrq(BaseAddr);
    AlAxiIntc_ll_EnableHardwareIntr(BaseAddr);

    AxiIntc->State |= AL_AXI_INTC_STATE_READY;

    return AL_OK;
}

AL_S32 AlAxiIntc_Dev_RegHandler(AL_AXI_INTC_DevStruct *AxiIntc, AL_AXI_INTC_InitStruct *InitConfig, AL_INTR_Func Func, AL_VOID *Param)
{
    AL_REG BaseAddr;

    AL_ASSERT((AxiIntc != AL_NULL) && (InitConfig != AL_NULL), AL_AXI_INTC_ERR_ILLEGAL_PARAM);
    AL_ASSERT(((AxiIntc->State & AL_AXI_INTC_STATE_READY) == AL_AXI_INTC_STATE_READY), AL_AXI_INTC_ERR_NOT_READY);

    if (InitConfig->IntrId >= (AxiIntc->HwConfig.InputSoftIntrNum + AxiIntc->HwConfig.InputHardWareIntrNum)) {
        return AL_AXI_INTC_ERR_ILLEGAL_PARAM;
    }

    BaseAddr = AxiIntc->HwConfig.BaseAddress;

    AlAxiIntcHandleList[InitConfig->AxiIntcDevId][InitConfig->IntrId].Func = Func;
    AlAxiIntcHandleList[InitConfig->AxiIntcDevId][InitConfig->IntrId].Param = Param;

    AlAxiIntc_ll_EnableIntr(BaseAddr, InitConfig->IntrId);

    return AL_OK;
}

AL_VOID AlAxiIntc_Dev_IntrHandler(AL_VOID *Instance)
{
    AL_U32 IntrStatus;
    AL_U32 IntrMask = 1;
    AL_S32 IntrNum = 0;

    AlAxiIntc_HwConfigStruct *HwConfig = &((AL_AXI_INTC_DevStruct *)Instance)->HwConfig;

    AL_REG BaseAddr = HwConfig->BaseAddress;
    AL_U32 AxiIntcDevId = HwConfig->DeviceId;

    IntrStatus = AlAxiIntc_ll_GetIntrStatus(BaseAddr);

    for (IntrNum = 0; IntrNum < HwConfig->InputSoftIntrNum+HwConfig->InputHardWareIntrNum; IntrNum++) {

        if (IntrStatus & 0x1) {

            AlAxiIntcHandleList[AxiIntcDevId][IntrNum].Func(AlAxiIntcHandleList[AxiIntcDevId][IntrNum].Param);

            AlAxiIntc_ll_GetIntrStatus(BaseAddr);

            AlAxiIntc_ll_AckIntrMask(BaseAddr, IntrMask);

            return ;
        }

        /* Move to the next interrupt to check */
        IntrMask <<= 1;
        IntrStatus >>= 1;

        /* If there are no other bits set indicating that all
            * interrupts have been serviced, then exit the loop
            */
        if (IntrStatus == 0) {
            break;
        }
    }

}