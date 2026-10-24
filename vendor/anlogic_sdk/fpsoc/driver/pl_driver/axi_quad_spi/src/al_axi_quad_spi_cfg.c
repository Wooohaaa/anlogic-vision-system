/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */
/***************************** Include Files ********************************/
#include "al_axi_quad_spi_hw.h"
#include "soc_plat.h"

/************************** Constant Definitions ****************************/

/**************************** Type Definitions ******************************/

/***************** Macros (Inline Functions) Definitions ********************/
/*  AXI_QSPI device information*/
#define AXI_QSPI_DEV_ID  0
#define AXI_QSPI_IRQn  114
#define AXI_QSPI_BASE_ADDR  0x80000000ULL
#define AXI_QSPI_CLK_IN  25000000
#define AXI_QSPI_IS_ASYNC_CLK  0
#define AXI_QSPI_AXI_TYPE  0
#define AXI_QSPI_AXI_ID_WIDTH  1
#define AXI_QSPI_XIP_PERF_MODE  0
#define AXI_QSPI_IS_XIP_MODE  0
#define AXI_QSPI_SLAVE_NUM  2
#define AXI_QSPI_SCK_RATIO  2
#define AXI_QSPI_SPI_MODE  0
#define AXI_QSPI_FLASH_TYPE  3
#define AXI_QSPI_TRANS_BITS  8
#define AXI_QSPI_FIFO_DEPTH  256
#define AXI_QSPI_FLASH_ADDR_LEN  24

/************************** Variable Definitions *****************************/
AlAxiQspi_HwConfigStruct AlAxiQspi_HwConfig[] =
{
#if (AL_AXI_QSPI_NUM_INSTANCE > 0)
    {
        .DeviceId       = (AL_U32)AXI_QSPI_DEV_ID,
        .IntrId         = (AL_U32)AXI_QSPI_IRQn,
        .BaseAddress    = (AL_U64)AXI_QSPI_BASE_ADDR,
        .InputClk       = (AL_U32)AXI_QSPI_CLK_IN,

        .IsAsyncClk     = (AL_U32)AXI_QSPI_IS_ASYNC_CLK,
        .AxiType        = (AL_U32)AXI_QSPI_AXI_TYPE,
        .AxiIdWidth     = (AL_U32)AXI_QSPI_AXI_ID_WIDTH,
        .XipPerfMode    = (AL_U32)AXI_QSPI_XIP_PERF_MODE,
        .IsXipMode      = (AL_U32)AXI_QSPI_IS_XIP_MODE,
        .SlaveNums      = (AL_U32)AXI_QSPI_SLAVE_NUM,
        .SCK_RATIO      = (AL_U32)AXI_QSPI_SCK_RATIO,
        .SpiMode        = (AlAxiQspi_ModeEnum)AXI_QSPI_SPI_MODE,
        .FlashType      = (AlAxiQspi_FlashTypeEnum)AXI_QSPI_FLASH_TYPE,
        .TransBits      = (AlAxiQspi_TransBitsEnum)AXI_QSPI_TRANS_BITS,
        .FifoDepth      = (AlAxiQspi_FifoDepthEnum)AXI_QSPI_FIFO_DEPTH,
        .FlashAddrLen   = (AlAxiQspi_FlashAddrLenEnum)AXI_QSPI_FLASH_ADDR_LEN,
    },
#endif
};

