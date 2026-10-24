/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */



/***************************** Include Files *********************************/
#include "al_axi_vdma_dev.h"

extern AlAxiVdma_HwConfigStruct AlAxiVdma_HwConfig[AL_AXI_VDMA_NUM_INSTANCE];

/**
 * This function searches through the list of hardware configurations to find the
 * configuration that matches the provided device ID.
 *
 * @param DevId The ID of the VDMA device.
 *
 * @return AlAxiVdma_HwConfigStruct* Pointer to the hardware configuration structure.
 */
AlAxiVdma_HwConfigStruct *AlAxiVdma_Dev_LookupConfig(AL_U32 DevId)
{
    AL_U32 Index;
    AlAxiVdma_HwConfigStruct *ConfigPtr = AL_NULL;
    for (Index = 0; Index < AL_AXI_VDMA_NUM_INSTANCE; Index++)
    {
        if (AlAxiVdma_HwConfig[Index].DeviceId == DevId)
        {
            ConfigPtr = &AlAxiVdma_HwConfig[Index];
            break;
        }
    }
    return ConfigPtr;
}

/**
 * This function checks if the MM2S (Memory-Mapped to Stream) channel of the VDMA is running.
 *
 * @param Vdma Pointer to the VDMA device structure.
 *
 * @return AL_BOOL Returns AL_TRUE if the MM2S channel is running, AL_FALSE otherwise.
 */
AL_BOOL AlAxiVdma_Dev_IsRuningMm2s(AlAxiVdma_Dev_Struct *Vdma)
{
    AL_BOOL Status;

    Status = AlAxiVdma_ll_IsHaltMm2s(Vdma->HwConfig.BaseAddress);
    if (Status) {
        return 0;
    }

    Status = AlAxiVdma_ll_IsRunMm2s(Vdma->HwConfig.BaseAddress);
    if (!Status) {
        return 0;
    }

    return AL_TRUE;
}

/**
 * This function starts the MM2S (Memory-Mapped to Stream) channel of the VDMA.
 *
 * @param Vdma Pointer to the VDMA device structure.
 * @param ChannelCfg Pointer to the channel configuration structure.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_U32 AlAxiVdma_Dev_StartMm2s(AlAxiVdma_Dev_Struct *Vdma, AlAxiVdma_ChannelCfg *Mm2sChannelCfg)
{
    if (!AlAxiVdma_Dev_IsRuningMm2s(Vdma)) {
        AlAxiVdma_ll_SetMm2sStart(Vdma->HwConfig.BaseAddress, AL_TRUE);
    }

    if (AlAxiVdma_Dev_IsRuningMm2s(Vdma)) {
        AlAxiVdma_ll_SetMm2sVsize(Vdma->HwConfig.BaseAddress, Mm2sChannelCfg->Vsize);
    } else {
        return AL_AXI_VDMA_ERR_BUSY;
    }

    return AL_OK;
}

/**
 * This function stops the MM2S (Memory-Mapped to Stream) channel of the VDMA.
 *
 * @param Vdma Pointer to the VDMA device structure.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_U32 AlAxiVdma_Dev_SetMm2sBufferAddr(AlAxiVdma_Dev_Struct *Vdma, AlAxiVdma_ChannelCfg *Mm2sChannelCfg)
{
    AL_S32 AddrWidth;
    AL_S32 FrmBound;
    AL_S32 NumFrames;
    AL_S32 Loop16 = 0;
    AL_S32 HiFrmAddr = 0;
    AL_S32 i;

    NumFrames = Vdma->HwConfig.MaxFrameStoreNum;

    if (Vdma->HwConfig.AddrWidth > 32) {
        AddrWidth = 64;
    } else {
        AddrWidth = 32;
    }

    if (AddrWidth > 32) {
        FrmBound = (AL_AXIVDMA_MAX_FRAMESTORE_64) / 2 - 1;
    } else {
        FrmBound = (AL_AXIVDMA_MAX_FRAMESTORE_32) / 2 - 1;
    }

    for (i = 0; i < NumFrames; i++, Loop16++) {
        if ((i > FrmBound) && !HiFrmAddr) {
            AlAxiVdma_ll_SetMm2sRegIndex(Vdma->HwConfig.BaseAddress, AL_TRUE);
            HiFrmAddr = 1;
            Loop16 = 0;
        }

        if (AddrWidth > 32) {
            AlAxiVdma_ll_SetMm2sStartAddr((Vdma->HwConfig.BaseAddress + i * 4 * 2),
                                            Mm2sChannelCfg->FrameStoreStartAddr[i]);

            AlAxiVdma_ll_SetMm2sStartAddr((Vdma->HwConfig.BaseAddress + 4 + i * 4 * 2),
                                            (Mm2sChannelCfg->FrameStoreStartAddr[i] >> 32));
        } else {
            AlAxiVdma_ll_SetMm2sStartAddr((Vdma->HwConfig.BaseAddress + i * 4),
                                            Mm2sChannelCfg->FrameStoreStartAddr[i]);
        }

        if ((NumFrames > FrmBound) && (i == (NumFrames - 1))) {
            AlAxiVdma_ll_SetMm2sRegIndex(Vdma->HwConfig.BaseAddress, AL_FALSE);
        }
    }

    return AL_OK;
}

/**
 * This function sets the MM2S (Memory-Mapped to Stream) channel configuration of the VDMA.
 *
 * @param Vdma Pointer to the VDMA device structure.
 * @param Mm2sChannelCfg Pointer to the channel configuration structure.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_U32 AlAxiVdma_Dev_SetMm2sConfig(AlAxiVdma_Dev_Struct *Vdma, AlAxiVdma_ChannelCfg *Mm2sChannelCfg)
{
    AlAxiVdma_ll_SetMm2sIrqDelayCount(Vdma->HwConfig.BaseAddress, Mm2sChannelCfg->DelayCount);
    AlAxiVdma_ll_SetMm2sIrqFrameCount(Vdma->HwConfig.BaseAddress, Mm2sChannelCfg->FrameCount);
    AlAxiVdma_ll_SetMm2sRepeatEn(Vdma->HwConfig.BaseAddress, Mm2sChannelCfg->RepeatEn);
    AlAxiVdma_ll_SetMm2sErrIrqEn(Vdma->HwConfig.BaseAddress, Mm2sChannelCfg->ErrIrqEn);
    AlAxiVdma_ll_SetMm2sDlyCntIrqEn(Vdma->HwConfig.BaseAddress, Mm2sChannelCfg->DlyCntIrqEn);
    AlAxiVdma_ll_SetMm2sFrmCntIrqEn(Vdma->HwConfig.BaseAddress, Mm2sChannelCfg->FrmCntIrqEn);
    AlAxiVdma_ll_SetMm2sRdPntrNum(Vdma->HwConfig.BaseAddress, Mm2sChannelCfg->PntrNum);
    AlAxiVdma_ll_SetMm2sGenlockSrc(Vdma->HwConfig.BaseAddress, Mm2sChannelCfg->GenlockSrc);
    AlAxiVdma_ll_SetMm2sFrameCntEn(Vdma->HwConfig.BaseAddress, Mm2sChannelCfg->FrameCntEn);
    AlAxiVdma_ll_SetMm2sGenlockEn(Vdma->HwConfig.BaseAddress, Mm2sChannelCfg->GenlockEn);
    AlAxiVdma_ll_SetMm2sCircularPark(Vdma->HwConfig.BaseAddress, Mm2sChannelCfg->CircularPark);
    AlAxiVdma_ll_SetMm2sRegIndex(Vdma->HwConfig.BaseAddress, Mm2sChannelCfg->RegIndex);

    AlAxiVdma_Dev_SetMm2sBufferAddr(Vdma, Mm2sChannelCfg);

    AlAxiVdma_ll_SetMm2sHsize(Vdma->HwConfig.BaseAddress, Mm2sChannelCfg->Hsize);
    AlAxiVdma_ll_SetMm2sFrameDelay(Vdma->HwConfig.BaseAddress, Mm2sChannelCfg->FrameDelay);
    AlAxiVdma_ll_SetMm2sStride(Vdma->HwConfig.BaseAddress,Mm2sChannelCfg->Stride);

    return AL_OK;
}

/**
 * This function checks if the S2MM (Stream to Memory-Mapped) channel of the VDMA is running.
 *
 * @param Vdma Pointer to the VDMA device structure.
 *
 * @return AL_BOOL Returns AL_TRUE if the S2MM channel is running, AL_FALSE otherwise.
 */
AL_BOOL AlAxiVdma_Dev_IsRuningS2Mm(AlAxiVdma_Dev_Struct *Vdma)
{
    AL_BOOL Status;

    Status = AlAxiVdma_ll_IsHaltS2Mm(Vdma->HwConfig.BaseAddress);
    if (Status) {
        return AL_FALSE;
    }

    Status = AlAxiVdma_ll_IsRunS2Mm(Vdma->HwConfig.BaseAddress);
    if (!Status) {
        return AL_FALSE;
    }

    return AL_TRUE;
}

/**
 * This function starts the S2MM (Stream to Memory-Mapped) channel of the VDMA.
 *
 * @param Vdma Pointer to the VDMA device structure.
 * @param ChannelCfg Pointer to the channel configuration structure.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_U32 AlAxiVdma_Dev_StartS2Mm(AlAxiVdma_Dev_Struct *Vdma, AlAxiVdma_ChannelCfg *S2MmChannelCfg)
{
    if (!AlAxiVdma_Dev_IsRuningS2Mm(Vdma)) {
        AlAxiVdma_ll_SetS2MmStart(Vdma->HwConfig.BaseAddress, AL_TRUE);
    }

    if (AlAxiVdma_Dev_IsRuningS2Mm(Vdma)) {
        AlAxiVdma_ll_SetS2MmVsize(Vdma->HwConfig.BaseAddress, S2MmChannelCfg->Vsize);
    } else {
        return AL_AXI_VDMA_ERR_BUSY;
    }

    return AL_OK;
}

/**
 * This function sets the S2MM (Stream to Memory-Mapped) channel buffer address of the VDMA.
 *
 * @param Vdma Pointer to the VDMA device structure.
 * @param S2MmChannelCfg Pointer to the channel configuration structure.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_U32 AlAxiVdma_Dev_SetS2MmBufferAddr(AlAxiVdma_Dev_Struct *Vdma, AlAxiVdma_ChannelCfg *S2MmChannelCfg)
{
    AL_S32 AddrWidth;
    AL_S32 FrmBound;
    AL_S32 NumFrames;
    AL_S32 Loop16 = 0;
    AL_S32 HiFrmAddr = 0;
    AL_S32 i;

    NumFrames = Vdma->HwConfig.MaxFrameStoreNum;

    if (Vdma->HwConfig.AddrWidth > 32) {
        AddrWidth = 64;
    } else {
        AddrWidth = 32;
    }

    if (AddrWidth > 32) {
        FrmBound = (AL_AXIVDMA_MAX_FRAMESTORE_64) / 2 - 1;
    } else {
        FrmBound = (AL_AXIVDMA_MAX_FRAMESTORE_32) / 2 - 1;
    }

    for (i = 0; i < NumFrames; i++, Loop16++) {
        if ((i > FrmBound) && !HiFrmAddr) {
            AlAxiVdma_ll_SetS2MmRegIndex(Vdma->HwConfig.BaseAddress, AL_TRUE);
            HiFrmAddr = 1;
            Loop16 = 0;
        }

        if (AddrWidth > 32) {
            AlAxiVdma_ll_SetS2MmStartAddr((Vdma->HwConfig.BaseAddress + i * 4 * 2),
                                            S2MmChannelCfg->FrameStoreStartAddr[i]);

            AlAxiVdma_ll_SetS2MmStartAddr((Vdma->HwConfig.BaseAddress + 4 + i * 4 * 2),
                                            (S2MmChannelCfg->FrameStoreStartAddr[i] >> 32));
        } else {
            AlAxiVdma_ll_SetS2MmStartAddr((Vdma->HwConfig.BaseAddress + i * 4),
                                            S2MmChannelCfg->FrameStoreStartAddr[i]);
        }

        if ((NumFrames > FrmBound) && (i == (NumFrames - 1))) {
            AlAxiVdma_ll_SetS2MmRegIndex(Vdma->HwConfig.BaseAddress, AL_FALSE);
        }
    }

    return AL_OK;
}

/**
 * This function sets the S2MM (Stream to Memory-Mapped) channel configuration of the VDMA.
 *
 * @param Vdma Pointer to the VDMA device structure.
 * @param S2MmChannelCfg Pointer to the channel configuration structure.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_U32 AlAxiVdma_Dev_SetS2MmConfig(AlAxiVdma_Dev_Struct *Vdma, AlAxiVdma_ChannelCfg *S2MmChannelCfg)
{
    AlAxiVdma_ll_SetS2MmIrqDelayCount(Vdma->HwConfig.BaseAddress, S2MmChannelCfg->DelayCount);
    AlAxiVdma_ll_SetS2MmIrqFrameCount(Vdma->HwConfig.BaseAddress, S2MmChannelCfg->FrameCount);
    AlAxiVdma_ll_SetS2MmRepeatEn(Vdma->HwConfig.BaseAddress, S2MmChannelCfg->RepeatEn);
    AlAxiVdma_ll_SetS2MmErrIrqEn(Vdma->HwConfig.BaseAddress, S2MmChannelCfg->ErrIrqEn);
    AlAxiVdma_ll_SetS2MmDlyCntIrqEn(Vdma->HwConfig.BaseAddress, S2MmChannelCfg->DlyCntIrqEn);
    AlAxiVdma_ll_SetS2MmFrmCntIrqEn(Vdma->HwConfig.BaseAddress, S2MmChannelCfg->FrmCntIrqEn);
    AlAxiVdma_ll_SetS2MmRdPntrNum(Vdma->HwConfig.BaseAddress, S2MmChannelCfg->PntrNum);
    AlAxiVdma_ll_SetS2MmGenlockSrc(Vdma->HwConfig.BaseAddress, S2MmChannelCfg->GenlockSrc);
    AlAxiVdma_ll_SetS2MmFrameCntEn(Vdma->HwConfig.BaseAddress, S2MmChannelCfg->FrameCntEn);
    AlAxiVdma_ll_SetS2MmGenlockEn(Vdma->HwConfig.BaseAddress, S2MmChannelCfg->GenlockEn);
    AlAxiVdma_ll_SetS2MmCircularPark(Vdma->HwConfig.BaseAddress, S2MmChannelCfg->CircularPark);
    AlAxiVdma_ll_SetS2MmRegIndex(Vdma->HwConfig.BaseAddress, S2MmChannelCfg->RegIndex);

    AlAxiVdma_Dev_SetS2MmBufferAddr(Vdma, S2MmChannelCfg);

    AlAxiVdma_ll_SetS2MmHsize(Vdma->HwConfig.BaseAddress, S2MmChannelCfg->Hsize);
    AlAxiVdma_ll_SetS2MmFrameDelay(Vdma->HwConfig.BaseAddress, S2MmChannelCfg->FrameDelay);
    AlAxiVdma_ll_SetS2MmStride(Vdma->HwConfig.BaseAddress, S2MmChannelCfg->Stride);

    if (Vdma->HwConfig.HasVFlip) {
        AlAxiVdma_ll_EnableVerticalFlip(Vdma->HwConfig.BaseAddress, S2MmChannelCfg->EnableVerticalFlip);
    }

    return AL_OK;
}

/**
 * This function stops the S2MM (Stream to Memory-Mapped) channel of the VDMA.
 *
 * @param Vdma Pointer to the VDMA device structure.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_U32 AlAxiVdma_Dev_MaskIrqS2Mm(AlAxiVdma_Dev_Struct *Vdma, AlAxiVdma_S2MmMaskIntrEnum MaskIrqS2Mm)
{
    AlAxiVdma_ll_MaskIrqS2Mm(Vdma->HwConfig.BaseAddress, (MaskIrqS2Mm << 1));

    return AL_OK;
}

/**
 * This function initializes the VDMA device with the specified device ID.
 *
 * @param Vdma Pointer to the VDMA device structure.
 * @param DevId The device ID of the VDMA.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiVdma_Dev_Init(AlAxiVdma_Dev_Struct *Vdma, AL_U32 DevId)
{
    AlAxiVdma_HwConfigStruct *VdmaHwConfig = AL_NULL;

    VdmaHwConfig = AlAxiVdma_Dev_LookupConfig(DevId);

    Vdma->HwConfig = *VdmaHwConfig;

    if (VdmaHwConfig->HasMm2s) {
        AlAxiVdma_ll_SetMm2sReset(Vdma->HwConfig.BaseAddress, 1);
        while (AlAxiVdma_ll_GetMm2sResetStatus(Vdma->HwConfig.BaseAddress));
    }

    if (VdmaHwConfig->HasS2Mm) {
        AlAxiVdma_ll_SetS2MmReset(Vdma->HwConfig.BaseAddress, 1);
        while (AlAxiVdma_ll_GetS2MmResetStatus(Vdma->HwConfig.BaseAddress));
    }

    return AL_OK;
}

/**
 * This function registers an event callback function for the VDMA device.
 *
 * @param Vdma Pointer to the VDMA device structure.
 * @param CallBack Pointer to the callback function.
 * @param CallBackRef Pointer to the callback reference.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
static AL_U32 AlAxiVdma_Dev_GetMm2sPendingIntr(AlAxiVdma_Dev_Struct *Vdma)
{
    return (AlAxiVdma_ll_GetMm2sStatus(Vdma->HwConfig.BaseAddress) & AL_AXI_VDMA_ALL_INTR_MASK);
}

/**
 * This function registers an event callback function for the VDMA device.
 *
 * @param Vdma Pointer to the VDMA device structure.
 * @param CallBack Pointer to the callback function.
 * @param CallBackRef Pointer to the callback reference.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
static AL_U32 AlAxiVdma_Dev_GetMm2sEnableIntr(AlAxiVdma_Dev_Struct *Vdma)
{
    return (AlAxiVdma_ll_GetMm2sControlReg(Vdma->HwConfig.BaseAddress) & AL_AXI_VDMA_ALL_INTR_MASK);
}

/**
 * This function handles the MM2S (Memory-Mapped to Stream) channel interrupts of the VDMA.
 *
 * @param Vdma Pointer to the VDMA device structure.
 * @param Mm2sIntrStatus The MM2S interrupt status.
 *
 * @return AL_VOID
 */
static AL_VOID AlAxiVdma_Dev_Mm2sHandler(AlAxiVdma_Dev_Struct *Vdma, AL_U32 Mm2sIntrStatus)
{
    AL_U32 PendingIntr;
    AlAxiVdma_EventStruct VdmaEvent = {
        .Events = 0,
    };

    PendingIntr = AlAxiVdma_Dev_GetMm2sPendingIntr(Vdma);
    PendingIntr &= AlAxiVdma_Dev_GetMm2sEnableIntr(Vdma);

    if (PendingIntr & BIT(MM2S_INTR_ERROR)) {
        VdmaEvent.Events = ALAXIVDMA_EVENT_MM2S_ERRIRQ;

        if (Vdma->EventCallBack) {
            (*Vdma->EventCallBack)(VdmaEvent, Vdma->EventCallBackRef);
        }
    }

    if (PendingIntr & BIT(MM2S_INTR_FRM_CNT)) {
        VdmaEvent.Events = ALAXIVDMA_EVENT_MM2S_FRAMECNT;

        if (Vdma->EventCallBack) {
            (*Vdma->EventCallBack)(VdmaEvent, Vdma->EventCallBackRef);
        }
    }

    AlAxiVdma_ll_ClearMm2sIntr(Vdma->HwConfig.BaseAddress, (PendingIntr & AL_AXI_VDMA_ALL_INTR_MASK));
}

/**
 * This function is the MM2S (Memory-Mapped to Stream) channel interrupt handler.
 *
 * @param Instance Pointer to the VDMA device structure.
 *
 * @return AL_VOID
 */
AL_VOID AlAxiVdma_Dev_Mm2sIntrHandler(AL_VOID *Instance)
{
    AlAxiVdma_Dev_Struct *Vdma = (AlAxiVdma_Dev_Struct *)Instance;
    AL_U32 Mm2sIntrStatus = AlAxiVdma_ll_GetMm2sStatus(Vdma->HwConfig.BaseAddress);

    if (Mm2sIntrStatus) {
        AlAxiVdma_Dev_Mm2sHandler(Vdma, Mm2sIntrStatus);
    }
}

/**
 * This function registers an event callback function for the VDMA device.
 *
 * @param Vdma Pointer to the VDMA device structure.
 * @param CallBack Pointer to the callback function.
 * @param CallBackRef Pointer to the callback reference.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
static AL_U32 AlAxiVdma_Dev_GetS2MmPendingIntr(AlAxiVdma_Dev_Struct *Vdma)
{
    return (AlAxiVdma_ll_GetS2MmStatus(Vdma->HwConfig.BaseAddress) & AL_AXI_VDMA_ALL_INTR_MASK);
}

/**
 * This function registers an event callback function for the VDMA device.
 *
 * @param Vdma Pointer to the VDMA device structure.
 * @param CallBack Pointer to the callback function.
 * @param CallBackRef Pointer to the callback reference.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
static AL_U32 AlAxiVdma_Dev_GetS2MmEnableIntr(AlAxiVdma_Dev_Struct *Vdma)
{
    return (AlAxiVdma_ll_GetS2MmControlReg(Vdma->HwConfig.BaseAddress) & AL_AXI_VDMA_ALL_INTR_MASK);
}

/**
 * This function handles the S2MM (Stream to Memory-Mapped) channel interrupts of the VDMA.
 *
 * @param Vdma Pointer to the VDMA device structure.
 * @param S2MmIntrStatus The S2MM interrupt status.
 *
 * @return AL_VOID
 */
static AL_VOID AlAxiVdma_Dev_S2MmHandler(AlAxiVdma_Dev_Struct *Vdma, AL_U32 S2MmIntrStatus)
{
    AL_U32 PendingIntr;
    AlAxiVdma_EventStruct VdmaEvent = {
        .Events = 0,
    };

    PendingIntr = AlAxiVdma_Dev_GetS2MmPendingIntr(Vdma);
    PendingIntr &= AlAxiVdma_Dev_GetS2MmEnableIntr(Vdma);

    if (PendingIntr & BIT(S2MM_INTR_ERROR)) {
        VdmaEvent.Events = ALAXIVDMA_EVENT_S2MM_ERRIRQ;

        if (Vdma->EventCallBack) {
            (*Vdma->EventCallBack)(VdmaEvent, Vdma->EventCallBackRef);
        }
    }

    if (PendingIntr & BIT(S2MM_INTR_FRM_CNT)) {
        VdmaEvent.Events = ALAXIVDMA_EVENT_S2MM_FRAMECNT;

        if (Vdma->EventCallBack) {
            (*Vdma->EventCallBack)(VdmaEvent, Vdma->EventCallBackRef);
        }
    }

    AlAxiVdma_ll_ClearS2MmIntr(Vdma->HwConfig.BaseAddress, (PendingIntr & AL_AXI_VDMA_ALL_INTR_MASK));
}

AL_VOID AlAxiVdma_Dev_S2MmIntrHandler(AL_VOID *Instance)
{
    AlAxiVdma_Dev_Struct *Vdma = (AlAxiVdma_Dev_Struct *)Instance;
    AL_U32 S2MmIntrStatus = AlAxiVdma_ll_GetS2MmStatus(Vdma->HwConfig.BaseAddress);

    if (S2MmIntrStatus) {
        AlAxiVdma_Dev_S2MmHandler(Vdma, S2MmIntrStatus);
    }
}

/**
 * This function registers an event callback function for the VDMA device.
 *
 * @param Vdma Pointer to the VDMA device structure.
 * @param CallBack Pointer to the callback function.
 * @param CallBackRef Pointer to the callback reference.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiVdma_Dev_RegisterEventCallBack(AlAxiVdma_Dev_Struct *Vdma, AlAxiVdma_EventCallBack Callback, void *CallbackRef)
{
    Vdma->EventCallBack        = Callback;
    Vdma->EventCallBackRef     = CallbackRef;

    return AL_OK;
}

/**
 * This function unregisters an event callback function for the VDMA device.
 *
 * @param Vdma Pointer to the VDMA device structure.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiVdma_Dev_UnRegisterEventCallBack(AlAxiVdma_Dev_Struct *Vdma)
{
    Vdma->EventCallBack = (AlAxiVdma_EventCallBack)AL_NULL;

    return AL_OK;
}
