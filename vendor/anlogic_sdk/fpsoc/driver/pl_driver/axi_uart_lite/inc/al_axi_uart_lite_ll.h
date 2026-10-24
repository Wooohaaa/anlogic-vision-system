/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef AL_AXI_UART_LITE_LL_H_
#define AL_AXI_UART_LITE_LL_H_

#ifdef __cplusplus
extern "C" {
#endif

#include "al_axi_uart_lite_hw.h"

typedef enum
{
    AL_AXIUARTLITE_BANDRATE_9600               = 0,
    AL_AXIUARTLITE_BANDRATE_110                = 1,
    AL_AXIUARTLITE_BANDRATE_300                = 2,
    AL_AXIUARTLITE_BANDRATE_1200               = 3,
    AL_AXIUARTLITE_BANDRATE_2400               = 4,
    AL_AXIUARTLITE_BANDRATE_4800               = 5,
    AL_AXIUARTLITE_BANDRATE_19200              = 6,
    AL_AXIUARTLITE_BANDRATE_38400              = 7,
    AL_AXIUARTLITE_BANDRATE_57600              = 8,
    AL_AXIUARTLITE_BANDRATE_115200             = 9,
    AL_AXIUARTLITE_BANDRATE_128000             = 10,
    AL_AXIUARTLITE_BANDRATE_230400             = 11,
    AL_AXIUARTLITE_BANDRATE_460800             = 12,
    AL_AXIUARTLITE_BANDRATE_921600             = 13,
} AlAxiUartLite_BandRateEnum;

static inline AL_U32 AlAxiUartLite_RecvData(AL_U64 BaseAddr)
{
    return AL_PL_REG32_READ(BaseAddr + AL_AXI_UART_LITE_RX_FIFO_OFFSET);
}

static inline AL_VOID AlAxiUartLite_SendData(AL_U64 BaseAddr, AL_U32 Data)
{
    AL_REG32_WRITE(BaseAddr + AL_AXI_UART_LITE_TX_FIFO_OFFSET, Data);
}

static inline AL_U32 AlAxiUartLite_GetStatus(AL_U64 BaseAddr)
{
    return AL_PL_REG32_READ(BaseAddr + AL_AXI_UART_LITE_SR_OFFSET);
}

static inline AL_VOID AlAxiUartLite_SetCfgReg(AL_U64 BaseAddr, AL_U32 Data)
{
    AL_REG32_WRITE(BaseAddr + AL_AXI_UART_LITE_CR_OFFSET, Data);
}


#ifdef __cplusplus
}
#endif

#endif /* AL_AXI_UART_LITE_LL_H_ */
