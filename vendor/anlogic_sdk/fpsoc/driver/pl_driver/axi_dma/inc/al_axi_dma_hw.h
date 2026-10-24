/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef __AL_AXI_DMA_HW_H_
#define __AL_AXI_DMA_HW_H_

#ifdef __cplusplus
extern "C" {
#endif

/***************************** Include Files *********************************/
#include "al_core.h"
#include "soc_plat.h"
/**************************** Type Definitions ******************************/
typedef enum {
    AL_AXIDMA_DIRECT_MODE      = 0,
    AL_AXIDMA_SG_MODE          = 1
} AlAxiDma_ModeEnum;

typedef struct {
    // General device configuration
    AL_U32      DeviceId;                    // Unique device ID for identifying the DMA device
    AL_U64      BaseAddress;                 // Base address of the device registers
    AL_U32      AddrWidth;                   // Address width of the Memory-Mapped interface in bits (e.g., 32, 64)
    AL_U32      BufferlenWidth;              // Width of the buffer length register in bits
    AL_U32      EnableMicroMode;             // Enable Micro Mode: 0 for disable, 1 for enable
    AL_U32      DmaMode;                     // DMA mode: 0 for Direct Mode, 1 for Scatter-Gather Mode
    AL_U32      EnableStatusControlStream;   // Enable status/control stream: 0 for disable, 1 for enable

    // MM2S (Memory-Mapped to Stream) configuration
    AL_U32      IntrNum_Mm2s;                // Interrupt number for the MM2S channel
    AL_U32      HasMm2s;                     // Enable MM2S channel: 0 for disable, 1 for enable
    AL_U32      HasMm2sDRE;                  // Enable unaligned data access (DRE) in MM2S channel: 0 for disable, 1 for enable
    AL_U32      Mm2sMemoryMapDataWidth;      // Data width of the MM2S Memory-Mapped interface in bits
    AL_U32      Mm2sStreamDataWidth;         // Data width of the MM2S Stream interface in bits
    AL_U32      Mm2sBurstSize;               // Maximum burst size for the MM2S channel in bytes
    AL_U32      Mm2sMicroMaxTransferLen;     // Maximum transfer length in Micro Mode for the MM2S channel in bytes

    // S2MM (Stream to Memory-Mapped) configuration
    AL_U32      IntrNum_S2mm;                // Interrupt number for the S2MM channel
    AL_U32      HasS2mm;                     // Enable S2MM channel: 0 for disable, 1 for enable
    AL_U32      HasS2mmDRE;                  // Enable unaligned data access (DRE) in S2MM channel: 0 for disable, 1 for enable
    AL_U32      S2mmMemoryMapDataWidth;      // Data width of the S2MM Memory-Mapped interface in bits
    AL_U32      S2mmStreamDataWidth;         // Data width of the S2MM Stream interface in bits
    AL_U32      S2mmBurstSize;               // Maximum burst size for the S2MM channel in bytes
    AL_U32      S2mmMicroMaxTransferLen;     // Maximum transfer length in Micro Mode for the S2MM channel in bytes
    AL_U32      EnableRxLength;              // Enable reception of the data length register: 0 for disable, 1 for enable
} AlAxiDma_HwConfigStruct;

/***************** Macros (Inline Functions) Definitions ********************/
#define AXI_DMA_DESC_ALIGN_SIZE                   0x40
#define AXI_DMA_MICRO_ALIGN_SIZE                  0x1000
#define AXI_DMA_MM2S_ALIGN_SIZE                   0x40
#define AXI_DMA_S2MM_ALIGN_SIZE                   0x40

#define AL_AXI_DMA_MAX_BURST_SIZE                 128

/* Attribute for aligning the buffer address for MM2S transfers */
#define AL_AXI_DMA_MM2S_BUFFER_ALIGN __attribute__((aligned(AXI_DMA_MM2S_ALIGN_SIZE)))

/* Attribute for aligning the buffer address for S2MM transfers */
#define AL_AXI_DMA_S2MM_BUFFER_ALIGN __attribute__((aligned(AXI_DMA_S2MM_ALIGN_SIZE)))

/* Attribute for aligning the buffer address for micro transfers */
#define AL_AXI_DMA_MICRO_BUFFER_ALIGN __attribute__((aligned(AXI_DMA_MICRO_ALIGN_SIZE)))

/* Attribute for placing descriptors in non-cacheable RAM section with alignment */
#define AL_AXI_DMA_DESC_NOCACHE_ALIGN_RAM_SECTION __attribute__((aligned(AXI_DMA_DESC_ALIGN_SIZE))) __attribute__((section(".noncacheable")))

/***************************** Register Offsets（MM2S / S2MM）*****************************/
#define AL_AXI_DMA_MM2S_OFFSET                  0x00
#define AL_AXI_DMA_S2MM_OFFSET                  0x30
#define AL_AXI_DMA_CR_OFFSET                    0x00
#define AL_AXI_DMA_SR_OFFSET                    0x04
#define AL_AXI_DMA_CURDESR_OFFSET               0x08
#define AL_AXI_DMA_CURDESR_MSB_OFFSET           0x0C
#define AL_AXI_DMA_TAILDESR_OFFSET              0x10
#define AL_AXI_DMA_TAILDESR_MSB_OFFSET          0x14
#define AL_AXI_DMA_ADDR_OFFSET                  0x18
#define AL_AXI_DMA_ADDR_MSB_OFFSET              0x1C
#define AL_AXI_DMA_LENTH_OFFSET                 0x28

/***************************** AXI_DMA_CR_OFFSET Register *****************************/
#define AL_AXI_DMA_CR_RUNSTOP_SHIFT                0
#define AL_AXI_DMA_CR_RESET_SHIFT                  2
#define AL_AXI_DMA_CR_KEYHOLE_SHIFT                3
#define AL_AXI_DMA_CR_CYCLIC_SHIFT                 4
#define AL_AXI_DMA_CR_IOC_SHIFT                   12
#define AL_AXI_DMA_CR_ERR_SHIFT                   14

/***************************** AXI_DMA_SR_OFFSET Register *****************************/
#define AL_AXI_DMA_SR_HALT_SHIFT                   0
#define AL_AXI_DMA_SR_IDLE_SHIFT                   1
#define AL_AXI_DMA_SR_IOC_SHIFT                   12
#define AL_AXI_DMA_SR_ERR_SHIFT                   14

#define AL_AXI_DMA_SR_INTR_SHIFT                  12
#define AL_AXI_DMA_SR_INTR_SIZE                    3

/***************************** AXI_DMA_LENTH_OFFSET Register *****************************/
#define AL_AXI_DMA_LENTH_START_SHIFT               0
#define AL_AXI_DMA_LENGTH_SIZE                    26

/***************************** AXI_DMA_Threshold_OFFSET Register *****************************/
#define AL_AXI_DMA_THRE_START_SHIFT               16
#define AL_AXI_DMA_THRE_SIZE                       8

/***************************** Scatter Gather Descriptor *********************************/
#define AL_AXI_DMA_DESC_CONTROL_SOF_SHIFT         27
#define AL_AXI_DMA_DESC_CONTROL_EOF_SHIFT         26

#ifdef __cplusplus
}
#endif

#endif
