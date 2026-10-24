/*
 * Copyright (c) 2025, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */


/***************************** Include Files ********************************/
#include "al_axi_uart_16550_hw.h"
#include "soc_plat.h"

/************************** Constant Definitions ****************************/

/**************************** Type Definitions ******************************/

/***************** Macros (Inline Functions) Definitions ********************/
#define AL_AXI_UART_16550_CLK           (100 * MHz)
#define AL_AXI_UART_16550_DEVICE_ID     0
#define AL_AXI_UART_16550_BASE_ADDR     0x80000000
#define AL_AXI_UART_16550_IRQ           114
#define AL_AXI_UART_16550_FIFO_SIZE     64


AlAxiUart16550_HwConfigStruct AlAxiUart16550_HwConfig[] =
{
#if defined(AL_AXI_UART_16550_NUM_INSTANCE) && (AL_AXI_UART_16550_NUM_INSTANCE > 0)
    {
        .DeviceId       = AL_AXI_UART_16550_DEVICE_ID,
        .BaseAddress    = AL_AXI_UART_16550_BASE_ADDR,
        .IntrId         = AL_AXI_UART_16550_IRQ,
        .InputClockHz   = AL_AXI_UART_16550_CLK,
        .FifoDepth      = AL_AXI_UART_16550_FIFO_SIZE,
    },
#endif
};