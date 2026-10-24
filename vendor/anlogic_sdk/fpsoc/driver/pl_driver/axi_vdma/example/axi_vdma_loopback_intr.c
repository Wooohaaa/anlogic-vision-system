/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/**
 * @file    axi_vdma_loopback_intr.c
 * @author  Anlogic esw team
 * @version V0.0.1
 * @date    2024-09-08
 * @brief   axi vdma loopback interrupt example
 * @example axi_vdma_loopback_intr.c
 */

#include <stdlib.h>
#include <string.h>
#include "al_axi_vdma_hal.h"

AlAxiVdma_Hal_Struct *Vdma;
AlAxiVdma_ChannelCfg *Mm2sChannelCfg;
AlAxiVdma_ChannelCfg *S2MmChannelCfg;

volatile AL_BOOL TransFlag = AL_FALSE;
AL_U8 ReadArray[64*64*5];
AL_U8 WriteArray[64*64*5];


static AL_VOID AlAxiVdma_EventHandler(AlAxiVdma_EventStruct VdmaEvent, AL_VOID *CallbackRef)
{
    switch (VdmaEvent.Events)
    {
    case ALAXIVDMA_EVENT_MM2S_FRAMECNT:
        AL_LOG(AL_LOG_LEVEL_INFO, "Al AxiVdma Mm2s interrupt");
        AlAxiVdma_Hal_Stop(Vdma, AL_VDMA_MM2S_CHANNEL);
        break;
    case ALAXIVDMA_EVENT_MM2S_ERRIRQ:
        AL_LOG(AL_LOG_LEVEL_INFO, "Al AxiVdma Mm2s error interrupt");
        AlAxiVdma_Hal_Stop(Vdma, AL_VDMA_MM2S_CHANNEL);
        break;
    case ALAXIVDMA_EVENT_S2MM_FRAMECNT:
        AL_LOG(AL_LOG_LEVEL_INFO, "Al AxiVdma S2Mm interrupt");
        TransFlag = AL_TRUE;
        AlAxiVdma_Hal_Stop(Vdma, AL_VDMA_S2MM_CHANNEL);
        break;
    case ALAXIVDMA_EVENT_S2MM_ERRIRQ:
        AL_LOG(AL_LOG_LEVEL_INFO, "Al AxiVdma S2Mm error interrupt");
        TransFlag = AL_TRUE;
        AlAxiVdma_Hal_Stop(Vdma, AL_VDMA_S2MM_CHANNEL);
        break;
    default:
        break;
    }
}

AL_VOID AxiVdmaLoopbackTest()
{
    for (AL_S32 i = 0; i < 64 * 64 * 5; i++) {
        ReadArray[i] = (AL_U8)i;
    }

    for (AL_S32 i = 0; i < 64 * 64 * 5; i++) {
        WriteArray[i] = (AL_U8)i + 5;
    }

    AlCache_FlushDcacheAll();

    Mm2sChannelCfg = (AlAxiVdma_ChannelCfg *)malloc(sizeof(AlAxiVdma_ChannelCfg));
    memset(Mm2sChannelCfg, 0, sizeof(AlAxiVdma_ChannelCfg));

    S2MmChannelCfg = (AlAxiVdma_ChannelCfg *)malloc(sizeof(AlAxiVdma_ChannelCfg));
    memset(S2MmChannelCfg, 0, sizeof(AlAxiVdma_ChannelCfg));


    Mm2sChannelCfg->CircularPark = 1;
    Mm2sChannelCfg->FrameCount = 5;
    Mm2sChannelCfg->FrmCntIrqEn = AL_TRUE;
    Mm2sChannelCfg->ErrIrqEn = AL_TRUE;
    Mm2sChannelCfg->GenlockSrc = 1;
    Mm2sChannelCfg->GenlockEn = AL_TRUE;
    Mm2sChannelCfg->Hsize = 64 ;
    Mm2sChannelCfg->Vsize = 64;
    Mm2sChannelCfg->Stride = 64;
    Mm2sChannelCfg->FrameStoreStartAddr[0]= (AL_UINTPTR)&ReadArray[0];
    Mm2sChannelCfg->FrameStoreStartAddr[1]= (AL_UINTPTR)&ReadArray[64*64];
    Mm2sChannelCfg->FrameStoreStartAddr[2]= (AL_UINTPTR)&ReadArray[64*64*2];
    Mm2sChannelCfg->FrameStoreStartAddr[3]= (AL_UINTPTR)&ReadArray[64*64*3];
    Mm2sChannelCfg->FrameStoreStartAddr[4]= (AL_UINTPTR)&ReadArray[64*64*4];

    S2MmChannelCfg->CircularPark = 1;
    S2MmChannelCfg->FrameCount = 5;
    S2MmChannelCfg->FrmCntIrqEn = AL_TRUE;
    S2MmChannelCfg->ErrIrqEn = AL_TRUE;
    S2MmChannelCfg->GenlockSrc = 1;
    S2MmChannelCfg->GenlockEn = AL_TRUE;
    S2MmChannelCfg->Hsize = 64;
    S2MmChannelCfg->Vsize = 64;
    S2MmChannelCfg->Stride = 64;
    S2MmChannelCfg->FrameStoreStartAddr[0]= (AL_UINTPTR)&WriteArray[0];
    S2MmChannelCfg->FrameStoreStartAddr[1]= (AL_UINTPTR)&WriteArray[64*64];
    S2MmChannelCfg->FrameStoreStartAddr[2]= (AL_UINTPTR)&WriteArray[64*64*2];
    S2MmChannelCfg->FrameStoreStartAddr[3]= (AL_UINTPTR)&WriteArray[64*64*3];
    S2MmChannelCfg->FrameStoreStartAddr[4]= (AL_UINTPTR)&WriteArray[64*64*4];
    S2MmChannelCfg->EnableVerticalFlip = AL_TRUE;

    AlIntr_SetLocalInterrupt(AL_FUNC_ENABLE);

    AlAxiVdma_Hal_Init(&Vdma, 0, AlAxiVdma_EventHandler);

    AlAxiVdma_Hal_Start(Vdma, AL_VDMA_MM2S_CHANNEL, Mm2sChannelCfg);
    AlAxiVdma_Hal_Start(Vdma, AL_VDMA_S2MM_CHANNEL, S2MmChannelCfg);
}

AL_S32 main()
{
    AL_BOOL IsEqual = AL_TRUE;

    AL_LOG(AL_LOG_LEVEL_INFO, "Axi vdma loopback test!");

    Soc_PsPlInit();

    AxiVdmaLoopbackTest();

    while (1) {
        if (TransFlag == 1)
            break;
    }

    AlCache_InvalidateDcacheRange((AL_UINTPTR)&WriteArray[0], (AL_UINTPTR)&WriteArray[0] + sizeof(WriteArray));

    for (AL_S32 i = 0; i < 64 * 64 * 5; i++) {
        if (WriteArray [i] != ReadArray[i]) {
                IsEqual = AL_FALSE;
                AL_LOG(AL_LOG_LEVEL_INFO, "Test Failed at index %d: ReadArray[%d] = %u, WriteArray[%d] = %u\n", i, i, ReadArray[i], i, WriteArray[i]);
            break;
        }
    }

    if (IsEqual) {
        AL_LOG(AL_LOG_LEVEL_INFO, "Test Passed: All elements are equal.\n");
    } else {
        AL_LOG(AL_LOG_LEVEL_INFO,"Test Failed: Not all elements are equal.\n");
    }

    return AL_OK;
}