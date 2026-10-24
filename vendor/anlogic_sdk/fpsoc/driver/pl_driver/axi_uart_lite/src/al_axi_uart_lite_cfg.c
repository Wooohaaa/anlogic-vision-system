/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */


/***************************** Include Files ********************************/
#include "al_axi_uart_lite_hw.h"
#include "soc_plat.h"

/************************** Constant Definitions ****************************/

/**************************** Type Definitions ******************************/

/***************** Macros (Inline Functions) Definitions ********************/
/*  AXI_UART_LITE device information*/
#define AXI_UART_LITE0_DEV_ID 0
#define AXI_UART_LITE0_BASE_ADDR 0x80020000
#define AXI_UART_LITE0_IRQn 116
#define AXI_UART_LITE0_BAUD_RATE 115200
#define AXI_UART_LITE0_DATA_WIDTH 8
#define AXI_UART_LITE0_PARITY_EN  0
#define AXI_UART_LITE0_PARITY_ODD  0
#define AXI_UART_LITE0_PARITY_EVEN  0

AlAxiUartLite_HwConfigStruct AlAxiUartLite_HwConfig[] =
{
#if (AL_AXI_UART_LITE_NUM_INSTANCE > 0)
    {
        .DeviceId       = (AL_U32)AXI_UART_LITE0_DEV_ID,
        .BaseAddress    = (AL_U64)AXI_UART_LITE0_BASE_ADDR,
        .IntrId         = (AL_U32)AXI_UART_LITE0_IRQn,
        .BaudRate       = (AL_U32)AXI_UART_LITE0_BAUD_RATE,
        .DataWidth      = (AL_U8)AXI_UART_LITE0_DATA_WIDTH,
        .ParityEn       = (AL_BOOL)AXI_UART_LITE0_PARITY_EN,
        .ParityOdd      = (AL_BOOL)AXI_UART_LITE0_PARITY_ODD,
        .ParityEven     = (AL_BOOL)AXI_UART_LITE0_PARITY_EVEN,
    },
#endif
};
