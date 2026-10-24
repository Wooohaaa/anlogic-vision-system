/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/***************************** Include Files *********************************/
#include "al_axi_vdma_dev.h"


/************************** Constant Definitions ****************************/

/**************************** Type Definitions ******************************/

/***************** Macros (Inline Functions) Definitions ********************/


#define AXI_VDMA0_DEV_ID 0
#define AXI_VDMA0_BASEADDR 0x80002000
#define AXI_VDMA0_ADDRWIDTH 32

#define AXI_VDMA0_MAXFRAMESTOENUM 5

#define AXI_VDMA0_HASS2MM 1
#define AXI_VDMA0_S2MM_INTRID 114
#define AXI_VDMA0_S2MMMMDATAWIDTH 128
#define AXI_VDMA0_S2MMBURSTSIZE 8
#define AXI_VDMA0_S2MMSTREAMDATAWIDITH 32
#define AXI_VDMA0_S2MMLINEBUFFERDEPTH 512
#define AXI_VDMA0_S2MMFSYNCOPTIONS 0
#define AXI_VDMA0_S2MMGENLOCKMODE 3
#define AXI_VDMA0_S2MMHASDRE 0

#define AXI_VDMA0_HASMM2S 1
#define AXI_VDMA0_MM2S_INTRID 115
#define AXI_VDMA0_MM2SMMDATAWIDTH 128
#define AXI_VDMA0_MM2SBURSTSIZE 8
#define AXI_VDMA0_MM2SSTREAMDATAWIDTH 32
#define AXI_VDMA0_MM2SLINEBUFFERDEPTH 512
#define AXI_VDMA0_MM2SFSYNCOPTIONS 0
#define AXI_VDMA0_MM2SGENLOCKMODE 2
#define AXI_VDMA0_MM2SHASDRE 0

#define AXI_VDMA0_ENABLEASYNSMODE 0
#define AXI_VDMA0_HASVFLIP 1


/************************** Variable Prototypes ******************************/
AlAxiVdma_HwConfigStruct AlAxiVdma_HwConfig[] =
{
#if (AL_AXI_VDMA_NUM_INSTANCE > 0)
    {
        .DeviceId               = AXI_VDMA0_DEV_ID,
        .BaseAddress            = AXI_VDMA0_BASEADDR,
        .AddrWidth              = AXI_VDMA0_ADDRWIDTH,

        .MaxFrameStoreNum       = AXI_VDMA0_MAXFRAMESTOENUM,

        .HasS2Mm                = AXI_VDMA0_HASS2MM,
        .S2Mm_IntrId            = AXI_VDMA0_S2MM_INTRID,
        .S2MmMmDataWidth        = AXI_VDMA0_S2MMMMDATAWIDTH,
        .S2MmBurstSize          = AXI_VDMA0_S2MMBURSTSIZE,
        .S2MmStreamDataWidth    = AXI_VDMA0_S2MMSTREAMDATAWIDITH,
        .S2MmLineBufferDepth    = AXI_VDMA0_S2MMLINEBUFFERDEPTH,
        .S2MmFsyncOptions       = AXI_VDMA0_S2MMFSYNCOPTIONS,
        .S2MmGenlockMode        = AXI_VDMA0_S2MMGENLOCKMODE,
        .S2MmHasDRE             = AXI_VDMA0_S2MMHASDRE,

        .HasMm2s                = AXI_VDMA0_HASMM2S,
        .Mm2s_IntrId            = AXI_VDMA0_MM2S_INTRID,
        .Mm2sMmDataWidth        = AXI_VDMA0_MM2SMMDATAWIDTH,
        .Mm2sBurstSize          = AXI_VDMA0_MM2SBURSTSIZE,
        .Mm2sStreamDataWidth    = AXI_VDMA0_MM2SSTREAMDATAWIDTH,
        .Mm2sLineBufferDepth    = AXI_VDMA0_MM2SLINEBUFFERDEPTH,
        .Mm2sFsyncOptions       = AXI_VDMA0_MM2SFSYNCOPTIONS,
        .Mm2sGenlockMode        = AXI_VDMA0_MM2SGENLOCKMODE,
        .Mm2sHasDRE             = AXI_VDMA0_MM2SHASDRE,

        .EnableAsynsMode        = AXI_VDMA0_ENABLEASYNSMODE,
        .HasVFlip               = AXI_VDMA0_HASVFLIP,
    }
#endif
};
