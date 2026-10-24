/*
 * Copyright (c) 2025, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef AL_AXI_UART_16550_LL_H_
#define AL_AXI_UART_16550_LL_H_

#ifdef __cplusplus
extern "C" {
#endif

#include "al_axi_uart_16550_hw.h"

typedef enum
{
    AlAxiUart16550_CHAR_5BITS                = 0,
    AlAxiUart16550_CHAR_6BITS                = 1,
    AlAxiUart16550_CHAR_7BITS                = 2,
    AlAxiUart16550_CHAR_8BITS                = 3
} AlAxiUart16550_DataWidthEnum;

typedef enum
{
    AlAxiUart16550_STOP_1BIT                 = 0,
    AlAxiUart16550_STOP_1_5BIT_OR_2BIT       = 1
} AlAxiUart16550_StopBitsEnum;

typedef enum
{
    AlAxiUart16550_NO_PARITY                 = 0x0,
    AlAxiUart16550_ODD_PARITY                = 0x1,
    AlAxiUart16550_EVEN_PARITY               = 0x3,
} AlAxiUart16550_ParityEnum;

typedef enum
{
    AlAxiUart16550_MODEM_STATUS              = 0x0,
    AlAxiUart16550_NO_INTERRUPT_PENDING      = 0x1,
    AlAxiUart16550_THR_EMPTY                 = 0x2,
    AlAxiUart16550_RECEIVED_DATA_AVAILABLE   = 0x4,
    AlAxiUart16550_RECEIVER_LINE_STATUS      = 0x6,
    AlAxiUart16550_CHARACTER_TIMEOUT         = 0xc
} AlAxiUart16550_IntrEnum;

typedef enum
{
    AlAxiUart16550_RxFIFO_CHAR_1             = 0x0,
    AlAxiUart16550_RxFIFO_CHAR_4             = 0x1,
    AlAxiUart16550_RxFIFO_CHAR_8             = 0x2,
    AlAxiUart16550_RxFIFO_CHAR_62            = 0x3
} AlAxiUart16550_RxFifoThrEnum;

typedef enum
{
    AlAxiUart16550_DmaMode0    = 0,
    AlAxiUart16550_DmaMode1    = 1,
} AlAxiUart16550_DmaModeEnum;

static inline AL_VOID AlAxiUart16550_ll_SendByte(AL_REG BaseAddr, AL_U8 Data)
{
    AL_REG32_WRITE(BaseAddr + AL_AXI_UART_16550_TX_FIFO_OFFSET, Data);
}

static inline AL_U8 AlAxiUart16550_ll_RecvByte(AL_REG BaseAddr)
{
    return AL_PL_REG32_READ(BaseAddr + AL_AXI_UART_16550_RX_FIFO_OFFSET);
}

static inline AL_VOID AlAxiUart16550_ll_SetRxIntr(AL_REG BaseAddr, AL_FUNCTION State)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AL_AXI_UART_16550_INTR_CR_OFFSET, AL_AXI_UART_16550_INTR_CR_RECV_SHIFT, State);
}

static inline AL_VOID AlAxiUart16550_ll_SetTxIntr(AL_REG BaseAddr, AL_FUNCTION State)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AL_AXI_UART_16550_INTR_CR_OFFSET, AL_AXI_UART_16550_INTR_CR_THRE_SHIFT, State);
}

static inline AL_VOID AlAxiUart16550_ll_EnableRecvLineIntr(AL_REG BaseAddr, AL_BOOL State)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AL_AXI_UART_16550_INTR_CR_OFFSET, AL_AXI_UART_16550_INTR_CR_LINE_SHIFT, State);
}


static inline AlAxiUart16550_IntrEnum AlAxiUart16550_ll_GetIntrStatus(AL_REG BaseAddr)
{
    return (AlAxiUart16550_IntrEnum)AL_PL_REG32_GET_BITS(BaseAddr + AL_AXI_UART_16550_INTR_SR_OFFSET,
                           AL_AXI_UART_16550_INTR_SR_ID_SHIFT, AL_AXI_UART_16550_INTR_SR_ID_SIZE);
}

static inline AL_BOOL AlAxiUart16550_ll_IsEmptyTsrAndTxFifo(AL_REG BaseAddr)
{
    return AL_PL_REG32_GET_BIT(BaseAddr + AL_AXI_UART_16550_LINE_SR_OFFSET, AL_AXI_UART_16550_LINE_SR_TEMT_SHIFT);
}

static inline AL_BOOL AlAxiUart16550_ll_IsEmptyTxFifo(AL_REG BaseAddr)
{
    return AL_PL_REG32_GET_BIT(BaseAddr + AL_AXI_UART_16550_LINE_SR_OFFSET, AL_AXI_UART_16550_LINE_SR_THRE_SHIFT);
}

static inline AL_BOOL AlAxiUart16550_ll_IsRxDataReady(AL_REG BaseAddr)
{
    return AL_PL_REG32_GET_BIT(BaseAddr + AL_AXI_UART_16550_LINE_SR_OFFSET, AL_AXI_UART_16550_LINE_SR_DR_SHIFT);
}

static inline AL_U32 AlAxiUart16550_ll_GetLineCtrl(AL_U64 BaseAddr)
{
    return AL_PL_REG32_READ(BaseAddr + AL_AXI_UART_16550_LINE_CR_OFFSET);
}

static inline AL_VOID AlAxiUart16550_ll_SetLineCtrl(AL_U64 BaseAddr, AL_U32 LineCtrl)
{
    AL_REG32_WRITE(BaseAddr + AL_AXI_UART_16550_LINE_CR_OFFSET, LineCtrl);
}

static inline AL_U32 AlAxiUart16550_ll_GetLineState(AL_U64 BaseAddr)
{
    return AL_PL_REG32_READ(BaseAddr + AL_AXI_UART_16550_LINE_SR_OFFSET);
}

static inline AL_VOID AlAxiUart16550_ll_ResetTxFifo(AL_U64 BaseAddr)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AL_AXI_UART_16550_LINE_CR_OFFSET, AL_AXI_UART_16550_LINE_CR_DLAB_SHIFT, AL_FUNC_ENABLE);
    AL_PL_REG32_SET_BIT(BaseAddr + AL_AXI_UART_16550_FIFO_CR_OFFSET, AL_AXI_UART_16550_FIFO_CR_TXFIFO_RESET_SHIFT, true);
    AL_PL_REG32_SET_BIT(BaseAddr + AL_AXI_UART_16550_LINE_CR_OFFSET, AL_AXI_UART_16550_LINE_CR_DLAB_SHIFT, AL_FUNC_DISABLE);
}

static inline AL_VOID AlAxiUart16550_ll_ResetRxFifo(AL_U64 BaseAddr)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AL_AXI_UART_16550_LINE_CR_OFFSET, AL_AXI_UART_16550_LINE_CR_DLAB_SHIFT, AL_FUNC_ENABLE);
    AL_PL_REG32_SET_BIT(BaseAddr + AL_AXI_UART_16550_FIFO_CR_OFFSET,  AL_AXI_UART_16550_FIFO_CR_RXFIFO_RESET_SHIFT, true);
    AL_PL_REG32_SET_BIT(BaseAddr + AL_AXI_UART_16550_LINE_CR_OFFSET, AL_AXI_UART_16550_LINE_CR_DLAB_SHIFT, AL_FUNC_DISABLE);
}

static inline AL_VOID AlAxiUart16550_ll_EnableFifo(AL_REG BaseAddr, AL_BOOL State)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AL_AXI_UART_16550_LINE_CR_OFFSET, AL_AXI_UART_16550_LINE_CR_DLAB_SHIFT, AL_FUNC_ENABLE);
    AL_PL_REG32_SET_BIT(BaseAddr + AL_AXI_UART_16550_FIFO_CR_OFFSET, AL_AXI_UART_16550_FIFO_CR_ENABLE_SHIFT, State);
    AL_PL_REG32_SET_BIT(BaseAddr + AL_AXI_UART_16550_LINE_CR_OFFSET, AL_AXI_UART_16550_LINE_CR_DLAB_SHIFT, AL_FUNC_DISABLE);
}

static inline AL_VOID AlAxiUart16550_ll_SetRxFifoThre(AL_REG BaseAddr, AlAxiUart16550_RxFifoThrEnum FifoThre)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AL_AXI_UART_16550_LINE_CR_OFFSET, AL_AXI_UART_16550_LINE_CR_DLAB_SHIFT, AL_FUNC_ENABLE);
    AL_PL_REG32_SET_BITS(BaseAddr + AL_AXI_UART_16550_FIFO_CR_OFFSET, AL_AXI_UART_16550_FIFO_CR_RXFIFO_LEVEL_SHIFT,
                                 AL_AXI_UART_16550_FIFO_CR_RXFIFO_LEVEL_SIZE, FifoThre);
    AL_PL_REG32_SET_BIT(BaseAddr + AL_AXI_UART_16550_LINE_CR_OFFSET, AL_AXI_UART_16550_LINE_CR_DLAB_SHIFT, AL_FUNC_DISABLE);
}

static inline AL_VOID AlAxiUart16550_ll_SetDataWidth(AL_REG BaseAddr, AlAxiUart16550_DataWidthEnum DataWidth)
{
    AL_PL_REG32_SET_BITS(BaseAddr + AL_AXI_UART_16550_LINE_CR_OFFSET, AL_AXI_UART_16550_LINE_CR_WORD_LEN_SHIFT,
                                 AL_AXI_UART_16550_LINE_CR_WORD_LEN_SIZE, DataWidth);
}

static inline AL_U32 AlAxiUart16550_ll_GetDataWidth(AL_REG BaseAddr)
{
    return AL_PL_REG32_GET_BITS(BaseAddr + AL_AXI_UART_16550_LINE_CR_OFFSET, AL_AXI_UART_16550_LINE_CR_WORD_LEN_SHIFT,
                                 AL_AXI_UART_16550_LINE_CR_WORD_LEN_SIZE);
}

static inline AL_VOID AlAxiUart16550_ll_SetStopBitsLength(AL_REG BaseAddr, AlAxiUart16550_StopBitsEnum StopBits)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AL_AXI_UART_16550_LINE_CR_OFFSET, AL_AXI_UART_16550_LINE_CR_STOP_BIT_SHIFT, StopBits);
}

static inline AL_BOOL AlAxiUart16550_ll_GetStopBitsLength(AL_REG BaseAddr)
{
    return AL_PL_REG32_GET_BIT(BaseAddr + AL_AXI_UART_16550_LINE_CR_OFFSET, AL_AXI_UART_16550_LINE_CR_STOP_BIT_SHIFT);
}

static inline AL_VOID AlAxiUart16550_ll_SetParity(AL_REG BaseAddr, AlAxiUart16550_ParityEnum Parity)
{
    AL_PL_REG32_SET_BITS(BaseAddr + AL_AXI_UART_16550_LINE_CR_OFFSET, AL_AXI_UART_16550_LINE_CR_PARITY_SHIFT,
                                 AL_AXI_UART_16550_LINE_CR_PARITY_SIZE, Parity);
}

static inline AL_U32 AlAxiUart16550_ll_GetParity(AL_REG BaseAddr)
{
    return AL_PL_REG32_GET_BITS(BaseAddr + AL_AXI_UART_16550_LINE_CR_OFFSET, AL_AXI_UART_16550_LINE_CR_PARITY_SHIFT,
                                 AL_AXI_UART_16550_LINE_CR_PARITY_SIZE);
}

static inline AL_VOID AlAxiUart16550_ll_SetBaudRate(AL_REG BaseAddr, AL_U8 Dll, AL_U8 Dlh)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AL_AXI_UART_16550_LINE_CR_OFFSET, AL_AXI_UART_16550_LINE_CR_DLAB_SHIFT, AL_FUNC_ENABLE);
    AL_REG32_WRITE(BaseAddr + AL_AXI_UART_16550_DLL_OFFSET, Dll);
    AL_REG32_WRITE(BaseAddr + AL_AXI_UART_16550_DLH_OFFSET, Dlh);
    AL_PL_REG32_SET_BIT(BaseAddr + AL_AXI_UART_16550_LINE_CR_OFFSET, AL_AXI_UART_16550_LINE_CR_DLAB_SHIFT, AL_FUNC_DISABLE);
}

static inline AL_U32 AlAxiUart16550_ll_GetBaudRate(AL_REG BaseAddr, AL_U32 InputClockHz)
{
    AL_U16 Divisor;
    AL_U32 BaudRate;
    AL_PL_REG32_SET_BIT(BaseAddr + AL_AXI_UART_16550_LINE_CR_OFFSET, AL_AXI_UART_16550_LINE_CR_DLAB_SHIFT, AL_FUNC_ENABLE);
    Divisor = (AL_PL_REG32_READ(BaseAddr + AL_AXI_UART_16550_DLH_OFFSET) << 8) | (AL_PL_REG32_READ(BaseAddr + AL_AXI_UART_16550_DLL_OFFSET));
    AL_PL_REG32_SET_BIT(BaseAddr + AL_AXI_UART_16550_LINE_CR_OFFSET, AL_AXI_UART_16550_LINE_CR_DLAB_SHIFT, AL_FUNC_DISABLE);
    BaudRate = (AL_U32)((InputClockHz >> 4) / Divisor);
    return BaudRate;
}

static inline AL_VOID AlAxiUart16550_ll_DisableAllIntr(AL_REG BaseAddr)
{
    AL_U32 IntrStatus = AL_PL_REG32_READ(BaseAddr + AL_AXI_UART_16550_INTR_CR_OFFSET) & (~0x0f);
    AL_REG32_WRITE(BaseAddr + AL_AXI_UART_16550_INTR_CR_OFFSET, IntrStatus);
}


#ifdef __cplusplus
}
#endif

#endif /* AL_AXI_UART_16550_LL_H_ */
