/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/***************************** Include Files *********************************/
#include "al_axi_dma_hal.h"
#include <string.h>
/************************** Constant Definitions *****************************/

/**************************** Type Definitions *******************************/

/**************************** Macros Definitions *****************************/
#define DMA_DEV_ID                    0
#define BUFFER_SIZE                   0x100
#define TEST_START_VALUE              0x0
#define TEST_ITERATIONS               100
#define NUM_BUFFERS                   1

#define DEFAULT_THRESHLOD             1
#define TRANSFER_METHOD               1  // 1 = BLOCK, 0 = POLLING

/************************** Variable Definitions *****************************/
AL_AXI_DMA_S2MM_BUFFER_ALIGN AL_U8 TxBuffer[BUFFER_SIZE];
AL_AXI_DMA_S2MM_BUFFER_ALIGN AL_U8 RxBuffer[BUFFER_SIZE];

// Array of buffer pointers
AL_U8 *TxPacket[NUM_BUFFERS] = {TxBuffer};
AL_U8 *RxPacket[NUM_BUFFERS] = {RxBuffer};

// Lengths for each buffer
AL_U32 bufferLengths[] = {BUFFER_SIZE};

AL_AXI_DMA_DESC_NOCACHE_ALIGN_RAM_SECTION AlAxiDma_Descriptor mm2s_descriptors[NUM_BUFFERS] = {0};
AL_AXI_DMA_DESC_NOCACHE_ALIGN_RAM_SECTION AlAxiDma_Descriptor s2mm_descriptors[NUM_BUFFERS] = {0};

AlAxiDma_InitStruct InitConfig = {
    .S2mm_Threshold       = DEFAULT_THRESHLOD,
    .S2mm_HasCyclic       = AL_AXI_DMA_FUNC_DISABLE,
    .S2mm_HasKeyHole      = AL_AXI_DMA_FUNC_DISABLE,
    .Mm2s_Threshold       = DEFAULT_THRESHLOD,
    .Mm2s_HasCyclic       = AL_AXI_DMA_FUNC_DISABLE,
    .Mm2s_HasKeyHole      = AL_AXI_DMA_FUNC_DISABLE,
};

/************************** Function Prototypes ******************************/
static AL_S32 AlAxiDma_SgMode_TransferExample(AL_U16 DeviceId);

AL_S32 main(AL_VOID)
{
    AL_S32 Ret = AL_OK;

    AL_LOG(AL_LOG_LEVEL_INFO, "--- Entering main() ---\r\n");

    Soc_PsPlInit();

    // Loop for multiple tests
    for (AL_U32 i = 0; i < TEST_ITERATIONS; i++) {
        AL_LOG(AL_LOG_LEVEL_INFO, "---- Scatter/Gather mode test Iteration: %d ----\r\n", i + 1);

        /* Run the example for simple transfer */
        Ret = AlAxiDma_SgMode_TransferExample(DMA_DEV_ID);
        if (Ret != AL_OK) {
            AL_LOG(AL_LOG_LEVEL_INFO, "Failed on iteration %d with error code %d\r\n", i + 1, Ret);
            return Ret;
        }
    }

    AL_LOG(AL_LOG_LEVEL_INFO, "Completed all iterations.\r\n");
    AL_LOG(AL_LOG_LEVEL_INFO, "--- Exiting main() ---\r\n");

    return Ret;
}

static AL_S32 AlAxiDma_SgMode_TransferExample(AL_U16 DeviceId)
{
    AlAxiDma_HalStruct *Handle;
    AL_U32 Value = TEST_START_VALUE;
    AL_S32 Ret = AL_OK;

/*********************** Initialize RxBuffer/TxBuffer and axi dma controller*********************/
    memset(RxBuffer, 0, BUFFER_SIZE);
    for (int i = 0; i < BUFFER_SIZE; i++) {
        TxBuffer[i] = Value;
        Value = (Value + 1) & 0xFF;
    }

    AlCache_InvalidateDcacheRange((AL_UINTPTR)RxBuffer, (AL_UINTPTR)RxBuffer + BUFFER_SIZE);
    AlCache_FlushDcacheRange((AL_UINTPTR)TxBuffer, (AL_UINTPTR)TxBuffer + BUFFER_SIZE);

    Ret = AlAxiDma_Hal_Init(&Handle, DeviceId, &InitConfig, AL_NULL);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_INFO, "AlAxiDma_Hal_Init failed %d\r\n", Ret);
        return Ret;
    }

    AlIntr_SetLocalInterrupt(AL_FUNC_ENABLE);

/************************************ S2MM ******************************************/
    AL_LOG(AL_LOG_LEVEL_INFO, "AXI DMA HP0(OCM/DDR)<--AXIStream(PL) S2MM Start\r\n");

    memset(s2mm_descriptors, 0, NUM_BUFFERS * sizeof(AlAxiDma_Descriptor));

    // Configure DMA transfer message
    ALAXIDMA_TransferMsg msg;
    msg.Buffers           = RxPacket;
    msg.BufferLengths     = bufferLengths;
    msg.NumBuffers        = NUM_BUFFERS;
    msg.Direction         = AL_AXIDMA_DEVICE_TO_DMA;
    msg.S2mm_descriptors  = s2mm_descriptors;

    // Set up descriptors for S2MM transfer
    Ret = AlAxiDma_Hal_SetupDescriptors(Handle, &msg);
    if (Ret != AL_OK) {
        return Ret;
    }

    // Start S2MM transfer
#if TRANSFER_METHOD == 1
    Ret = AlAxiDma_Dev_SgMode_Transfer(&Handle->Dma, msg.NumBuffers, msg.Direction, AL_AXIDMA_BLOCK);
#else
    Ret = AlAxiDma_Dev_SgMode_Transfer(&Handle->Dma, msg.NumBuffers, msg.Direction, AL_AXIDMA_POLLING);
#endif
    if (Ret != AL_OK) {
        return Ret;
    }

/************************************ MM2S ******************************************/
    AL_LOG(AL_LOG_LEVEL_INFO, "AXI DMA HP0(OCM/DDR)-->AXIStream(PL) MM2S Start\r\n");

    memset(mm2s_descriptors, 0, NUM_BUFFERS * sizeof(AlAxiDma_Descriptor));

    // Configure DMA transfer message
    msg.Buffers           = TxPacket;
    msg.BufferLengths     = bufferLengths;
    msg.NumBuffers        = NUM_BUFFERS;
    msg.Direction         = AL_AXIDMA_DMA_TO_DEVICE;
    msg.Mm2s_descriptors  = mm2s_descriptors;

    // Set up descriptors for MM2S transfer
    Ret = AlAxiDma_Hal_SetupDescriptors(Handle, &msg);
    if (Ret != AL_OK) {
        return Ret;
    }

    // Start MM2S transfer
#if TRANSFER_METHOD == 1
    Ret = AlAxiDma_Dev_SgMode_Transfer(&Handle->Dma, msg.NumBuffers, msg.Direction, AL_AXIDMA_BLOCK);
#else
    Ret = AlAxiDma_Dev_SgMode_Transfer(&Handle->Dma, msg.NumBuffers, msg.Direction, AL_AXIDMA_POLLING);
#endif
    if (Ret != AL_OK) {
        return Ret;
    }

/***************************** Wait till tranfer is done **********************************/
#if TRANSFER_METHOD == 1
    while (!AlAxiDma_ll_GetSrHalt(Handle->Dma.RegBase + AL_AXI_DMA_S2MM_OFFSET) ||
           !AlAxiDma_ll_GetSrHalt(Handle->Dma.RegBase + AL_AXI_DMA_MM2S_OFFSET));
#else
    while (AlAxiDma_Dev_Busy(&Handle->Dma, AL_AXIDMA_DEVICE_TO_DMA) &&
           AlAxiDma_Dev_Busy(&Handle->Dma, AL_AXIDMA_DMA_TO_DEVICE));

    AlAxiDma_Dev_Stop_Transfer(&Handle->Dma, AL_AXIDMA_DEVICE_TO_DMA);
    AlAxiDma_Dev_Stop_Transfer(&Handle->Dma, AL_AXIDMA_DMA_TO_DEVICE);
#endif

/************************************ Check Data ******************************************/

    Value = TEST_START_VALUE;
    for (int i = 0; i < BUFFER_SIZE; i++) {
        if (RxBuffer[i] != Value) {
            AL_LOG(AL_LOG_LEVEL_ERROR, "Data error %d: 0x%x/0x%x\r\n",
                       i, RxBuffer[i], Value);
            return AL_ERROR;
        }
        Value = (Value + 1) & 0xFF;
    }

    AL_LOG(AL_LOG_LEVEL_INFO, "AXI Stream loopback done, check data success!\r\n");

    return AL_OK;
}
